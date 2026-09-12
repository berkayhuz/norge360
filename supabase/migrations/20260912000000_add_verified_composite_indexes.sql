-- Composite indexes are limited to query patterns that currently exist in the
-- iOS persistence layer or security-definer RPCs. Candidate indexes without a
-- matching runtime query are intentionally not created here.

create index if not exists community_posts_author_created_id_index
  on public.community_posts (author_id, created_at desc, id desc);

create index if not exists community_comments_author_created_id_index
  on public.community_comments (author_id, created_at desc, id desc);

create index if not exists community_events_group_starts_id_index
  on public.community_events (group_id, starts_at, id);

create index if not exists community_event_rsvps_user_event_index
  on public.community_event_rsvps (user_id, event_id);

create index if not exists community_group_memberships_user_group_index
  on public.community_group_memberships (user_id, group_id);

create index if not exists user_blocks_blocked_blocker_index
  on public.user_blocks (blocked_user_id, blocker_id);

create index if not exists community_post_likes_user_created_post_index
  on public.community_post_likes (user_id, created_at desc, post_id);
