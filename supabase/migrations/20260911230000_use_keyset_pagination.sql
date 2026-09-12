-- Replace offset pagination with stable keyset pagination for the feed. The
-- cursor is a base64-encoded JSON object containing only the last visible
-- row's ordering values; it is opaque to the iOS client.
drop function if exists public.list_community_feed_page(integer, integer);

create or replace function public.list_community_feed_page(
  page_cursor text default null,
  page_limit integer default 20
)
returns table (
  post jsonb,
  author jsonb,
  media jsonb,
  likes_count bigint,
  is_liked_by_current_user boolean,
  comments_count bigint,
  edit_history_count bigint,
  next_cursor text
)
language sql
stable
security definer
set search_path = ''
as $$
  with settings as (
    select least(greatest(coalesce(page_limit, 20), 1), 30) as page_size
  ),
  cursor_value as (
    select case
      when nullif(btrim(page_cursor), '') is null then null::jsonb
      else convert_from(decode(page_cursor, 'base64'), 'UTF8')::jsonb
    end as payload
  ),
  visible_posts as (
    select
      community_post.id,
      community_post.author_id,
      community_post.group_id,
      community_post.body,
      community_post.title,
      community_post.kind,
      community_post.created_at,
      community_post.updated_at,
      jsonb_build_object(
        'user_id', author_profile.user_id,
        'display_name', author_profile.display_name,
        'username', author_profile.username,
        'preferred_locale', author_profile.preferred_locale,
        'public_languages', author_profile.public_languages,
        'interests', author_profile.interests,
        'is_public', author_profile.is_public,
        'avatar_path', author_profile.avatar_path,
        'created_at', author_profile.created_at,
        'updated_at', author_profile.updated_at
      ) as author
    from public.community_posts as community_post
    join public.community_profiles as author_profile
      on author_profile.user_id = community_post.author_id
    where (select auth.uid()) is not null
      and community_post.moderation_state = 'active'
      and author_profile.is_public
      and author_profile.moderation_state = 'active'
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
        or (community_post.created_at, community_post.id) < (
          ((select payload from cursor_value)->>'value')::timestamptz,
          ((select payload from cursor_value)->>'id')::uuid
        )
      )
    order by community_post.created_at desc, community_post.id desc
    limit (select page_size + 1 from settings)
  ),
  numbered_posts as (
    select
      visible_posts.*,
      row_number() over (order by visible_posts.created_at desc, visible_posts.id desc) as row_number
    from visible_posts
  ),
  page_cursor_value as (
    select case
      when exists (
        select 1 from numbered_posts
        where row_number > (select page_size from settings)
      ) then (
        select encode(
          convert_to(
            json_build_object('value', last_page.created_at::text, 'id', last_page.id)::text,
            'UTF8'
          ),
          'base64'
        )
        from numbered_posts as last_page
        where last_page.row_number = (select page_size from settings)
      )
      else null
    end as next_cursor
  )
  select
    jsonb_build_object(
      'id', feed_post.id,
      'author_id', feed_post.author_id,
      'group_id', feed_post.group_id,
      'body', feed_post.body,
      'title', feed_post.title,
      'kind', feed_post.kind,
      'created_at', feed_post.created_at,
      'updated_at', feed_post.updated_at
    ) as post,
    feed_post.author,
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', post_media.id,
            'post_id', post_media.post_id,
            'storage_path', post_media.storage_path,
            'sort_order', post_media.sort_order,
            'width', post_media.width,
            'height', post_media.height,
            'created_at', post_media.created_at
          )
          order by post_media.sort_order
        )
        from public.community_post_media as post_media
        where post_media.post_id = feed_post.id
      ),
      '[]'::jsonb
    ) as media,
    (
      select count(*)
      from public.community_post_likes as post_like
      where post_like.post_id = feed_post.id
    ) as likes_count,
    exists (
      select 1
      from public.community_post_likes as current_user_like
      where current_user_like.post_id = feed_post.id
        and current_user_like.user_id = (select auth.uid())
    ) as is_liked_by_current_user,
    (
      select count(*)
      from public.community_comments as comment
      join public.community_profiles as comment_author
        on comment_author.user_id = comment.author_id
      where comment.post_id = feed_post.id
        and comment.moderation_state = 'active'
        and comment_author.is_public
        and comment_author.moderation_state = 'active'
        and public.can_view_community_user(comment.author_id)
    ) as comments_count,
    (
      select count(*)
      from public.community_post_edit_history as edit_history
      where edit_history.post_id = feed_post.id
    ) as edit_history_count,
    page_cursor_value.next_cursor
  from numbered_posts as feed_post
  cross join page_cursor_value
  where feed_post.row_number <= (select page_size from settings)
  order by feed_post.created_at desc, feed_post.id desc;
$$;

revoke all on function public.list_community_feed_page(text, integer) from public;
grant execute on function public.list_community_feed_page(text, integer) to authenticated;

-- Composite ordering keys let PostgreSQL seek directly to the next page.
create index if not exists community_posts_active_created_id_index
  on public.community_posts (created_at desc, id desc)
  where moderation_state = 'active';

create index if not exists community_events_starts_id_index
  on public.community_events (starts_at, id);

create index if not exists community_groups_name_id_index
  on public.community_groups (name, id);
