-- Search results should be renderable without returning post IDs and making a
-- second round of post, author, media, counter, and visibility queries.

create or replace function public.search_community_post_results(search_query text)
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
volatile
security definer
set search_path = ''
as $$
with rate as materialized (
  select quota.allowed
  from public.consume_community_request_rate_limit('search_post_results', 60, 60) as quota
), normalized as (
  select lower(
    btrim(replace(replace(replace(search_query, E'\\', ''), '%', ''), '_', ''))
  ) as value
), visible_posts as (
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
      'norway_status', case when author_profile.show_norway_status then author_profile.norway_status else null end,
      'city_or_region', case when author_profile.show_location then author_profile.city_or_region else null end,
      'public_languages', author_profile.public_languages,
      'interests', author_profile.interests,
      'is_public', author_profile.is_public,
      'show_norway_status', author_profile.show_norway_status,
      'show_location', author_profile.show_location,
      'biography', author_profile.biography,
      'avatar_path', author_profile.avatar_path,
      'created_at', author_profile.created_at,
      'updated_at', author_profile.updated_at
    ) as author
  from public.community_posts as community_post
  join public.community_profiles as author_profile
    on author_profile.user_id = community_post.author_id
  cross join normalized
  cross join rate
  where rate.allowed
    and char_length(normalized.value) between 3 and 80
    and community_post.moderation_state = 'active'
    and author_profile.is_public
    and author_profile.moderation_state = 'active'
    and public.can_view_community_user(community_post.author_id)
    and lower(community_post.body) like '%' || normalized.value || '%'
    and (
      community_post.group_id is null
      or exists (
        select 1
        from public.community_groups as community_group
        where community_group.id = community_post.group_id
          and community_group.moderation_state = 'active'
      )
    )
  order by community_post.created_at desc, community_post.id desc
  limit 20
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
  null::text as next_cursor
from visible_posts as feed_post
order by feed_post.created_at desc, feed_post.id desc;
$$;

revoke all on function public.search_community_post_results(text) from public, anon;
grant execute on function public.search_community_post_results(text) to authenticated;

comment on function public.search_community_post_results(text) is
  'Returns bounded, viewer-authorized, render-ready post search rows so clients avoid a second hydration round trip.';
