-- Page only posts that actually have media. The client hydrates the returned
-- post IDs through the existing RLS-protected post/media projection path.
drop function if exists public.list_community_member_media_posts_page(uuid, text, integer);

create function public.list_community_member_media_posts_page(
  target_user_id uuid,
  page_cursor text default null,
  page_limit integer default 30
)
returns table (
  post_id uuid,
  next_cursor text
)
language sql
stable
security definer
set search_path = ''
as $$
  with viewer_context as (
    select (select auth.uid()) as viewer_id
  ),
  settings as (
    select least(greatest(coalesce(page_limit, 30), 1), 30) as page_size
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
      community_post.created_at
    from public.community_posts as community_post
    join public.community_profiles as author_profile
      on author_profile.user_id = community_post.author_id
    cross join viewer_context
    where viewer_context.viewer_id is not null
      and community_post.author_id = target_user_id
      and community_post.moderation_state = 'active'
      and author_profile.moderation_state = 'active'
      and (
        community_post.author_id = viewer_context.viewer_id
        or author_profile.is_public
      )
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
      and exists (
        select 1
        from public.community_post_media as post_media
        where post_media.post_id = community_post.id
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
        select 1
        from numbered_posts
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
    page_post.id as post_id,
    page_cursor_value.next_cursor
  from numbered_posts as page_post
  cross join page_cursor_value
  where page_post.row_number <= (select page_size from settings)
  order by page_post.created_at desc, page_post.id desc;
$$;

revoke all on function public.list_community_member_media_posts_page(uuid, text, integer) from public;
grant execute on function public.list_community_member_media_posts_page(uuid, text, integer) to authenticated;
