-- Aggregate each one-to-many relationship independently so profile stats do
-- not materialize a likes x comments intermediate result for every post.
create or replace view public.community_member_profile_stats
with (security_invoker = true)
as
with post_counts as (
  select
    post.author_id as user_id,
    count(*)::integer as posts_count
  from public.community_posts as post
  group by post.author_id
),
like_counts as (
  select
    post.author_id as user_id,
    count(*)::integer as likes_count
  from public.community_posts as post
  join public.community_post_likes as like_row on like_row.post_id = post.id
  group by post.author_id
),
comment_counts as (
  select
    post.author_id as user_id,
    count(*)::integer as comments_count
  from public.community_posts as post
  join public.community_comments as comment on comment.post_id = post.id
  group by post.author_id
)
select
  post_counts.user_id,
  post_counts.posts_count,
  coalesce(like_counts.likes_count, 0)::integer as likes_count,
  coalesce(comment_counts.comments_count, 0)::integer as comments_count
from post_counts
left join like_counts on like_counts.user_id = post_counts.user_id
left join comment_counts on comment_counts.user_id = post_counts.user_id;
