-- Keep counter payloads bounded to one row per requested resource. The
-- security-invoker functions preserve the caller's RLS visibility while
-- keeping raw like/comment/history rows inside PostgreSQL.
create or replace function public.list_community_post_counters(target_post_ids uuid[])
returns table (
  post_id uuid,
  likes_count bigint,
  is_liked_by_current_user boolean,
  comments_count bigint,
  edit_history_count bigint
)
language sql
stable
security invoker
set search_path = ''
as $$
  with requested_posts as (
    select community_post.id
    from public.community_posts as community_post
    where community_post.id = any(coalesce(target_post_ids[1:100], '{}'::uuid[]))
  ),
  like_counts as (
    select post_like.post_id, count(*) as likes_count
    from public.community_post_likes as post_like
    join requested_posts on requested_posts.id = post_like.post_id
    group by post_like.post_id
  ),
  comment_counts as (
    select comment.post_id, count(*) as comments_count
    from public.community_comments as comment
    join requested_posts on requested_posts.id = comment.post_id
    group by comment.post_id
  ),
  history_counts as (
    select edit_history.post_id, count(*) as edit_history_count
    from public.community_post_edit_history as edit_history
    join requested_posts on requested_posts.id = edit_history.post_id
    group by edit_history.post_id
  )
  select
    requested_posts.id as post_id,
    coalesce(like_counts.likes_count, 0)::bigint as likes_count,
    exists (
      select 1
      from public.community_post_likes as current_user_like
      where current_user_like.post_id = requested_posts.id
        and current_user_like.user_id = (select auth.uid())
    ) as is_liked_by_current_user,
    coalesce(comment_counts.comments_count, 0)::bigint as comments_count,
    coalesce(history_counts.edit_history_count, 0)::bigint as edit_history_count
  from requested_posts
  left join like_counts on like_counts.post_id = requested_posts.id
  left join comment_counts on comment_counts.post_id = requested_posts.id
  left join history_counts on history_counts.post_id = requested_posts.id
  order by requested_posts.id;
$$;

create or replace function public.list_community_event_counters(target_event_ids uuid[])
returns table (
  event_id uuid,
  likes_count bigint,
  is_liked_by_current_user boolean
)
language sql
stable
security invoker
set search_path = ''
as $$
  with requested_events as (
    select community_event.id
    from public.community_events as community_event
    where community_event.id = any(coalesce(target_event_ids[1:100], '{}'::uuid[]))
  ),
  like_counts as (
    select event_like.event_id, count(*) as likes_count
    from public.community_event_likes as event_like
    join requested_events on requested_events.id = event_like.event_id
    group by event_like.event_id
  )
  select
    requested_events.id as event_id,
    coalesce(like_counts.likes_count, 0)::bigint as likes_count,
    exists (
      select 1
      from public.community_event_likes as current_user_like
      where current_user_like.event_id = requested_events.id
        and current_user_like.user_id = (select auth.uid())
    ) as is_liked_by_current_user
  from requested_events
  left join like_counts on like_counts.event_id = requested_events.id
  order by requested_events.id;
$$;

revoke all on function public.list_community_post_counters(uuid[]) from public;
grant execute on function public.list_community_post_counters(uuid[]) to authenticated;

revoke all on function public.list_community_event_counters(uuid[]) from public;
grant execute on function public.list_community_event_counters(uuid[]) to authenticated;
