-- Replace the bounded first-page comments RPC with an opaque keyset cursor.
-- The visibility and moderation predicates intentionally mirror the previous
-- function so pagination does not widen the data exposed to the client.
drop function if exists public.list_community_post_comments(uuid);

create function public.list_community_post_comments(
  target_post_id uuid,
  page_cursor text default null,
  page_limit integer default 50
)
returns table (
  comment jsonb,
  author jsonb,
  next_cursor text
)
language sql
stable
security definer
set search_path = ''
as $$
  with settings as (
    select least(greatest(coalesce(page_limit, 50), 1), 50) as page_size
  ),
  cursor_value as (
    select case
      when nullif(btrim(page_cursor), '') is null then null::jsonb
      else convert_from(decode(page_cursor, 'base64'), 'UTF8')::jsonb
    end as payload
  ),
  visible_comments as (
    select
      community_comment.id,
      community_comment.post_id,
      community_comment.author_id,
      community_comment.body,
      community_comment.created_at,
      community_comment.updated_at,
      jsonb_build_object(
        'user_id', comment_author.user_id,
        'display_name', comment_author.display_name,
        'username', comment_author.username,
        'preferred_locale', comment_author.preferred_locale,
        'public_languages', comment_author.public_languages,
        'interests', comment_author.interests,
        'is_public', comment_author.is_public,
        'avatar_path', comment_author.avatar_path,
        'created_at', comment_author.created_at,
        'updated_at', comment_author.updated_at
      ) as author
    from public.community_comments as community_comment
    join public.community_profiles as comment_author
      on comment_author.user_id = community_comment.author_id
    join public.community_posts as community_post
      on community_post.id = community_comment.post_id
    join public.community_profiles as post_author
      on post_author.user_id = community_post.author_id
    where (select auth.uid()) is not null
      and community_comment.post_id = target_post_id
      and community_comment.moderation_state = 'active'
      and comment_author.is_public
      and comment_author.moderation_state = 'active'
      and public.can_view_community_user(community_comment.author_id)
      and community_post.moderation_state = 'active'
      and post_author.is_public
      and post_author.moderation_state = 'active'
      and public.can_view_community_user(community_post.author_id)
      and (
        community_post.group_id is null
        or exists (
          select 1
          from public.community_groups as community_group
          where community_group.id = community_post.group_id
            and community_group.moderation_state = 'active'
        )
      )
      and (
        (select payload from cursor_value) is null
        or (community_comment.created_at, community_comment.id) > (
          ((select payload from cursor_value)->>'value')::timestamptz,
          ((select payload from cursor_value)->>'id')::uuid
        )
      )
    order by community_comment.created_at, community_comment.id
    limit (select page_size + 1 from settings)
  ),
  numbered_comments as (
    select
      visible_comments.*,
      row_number() over (order by visible_comments.created_at, visible_comments.id) as row_number
    from visible_comments
  ),
  page_cursor_value as (
    select case
      when exists (
        select 1
        from numbered_comments
        where row_number > (select page_size from settings)
      ) then (
        select encode(
          convert_to(
            json_build_object('value', last_page.created_at::text, 'id', last_page.id)::text,
            'UTF8'
          ),
          'base64'
        )
        from numbered_comments as last_page
        where last_page.row_number = (select page_size from settings)
      )
      else null
    end as next_cursor
  )
  select
    jsonb_build_object(
      'id', page_comment.id,
      'post_id', page_comment.post_id,
      'author_id', page_comment.author_id,
      'body', page_comment.body,
      'created_at', page_comment.created_at,
      'updated_at', page_comment.updated_at
    ) as comment,
    page_comment.author,
    page_cursor_value.next_cursor
  from numbered_comments as page_comment
  cross join page_cursor_value
  where page_comment.row_number <= (select page_size from settings)
  order by page_comment.created_at, page_comment.id;
$$;

revoke all on function public.list_community_post_comments(uuid, text, integer) from public;
grant execute on function public.list_community_post_comments(uuid, text, integer) to authenticated;
