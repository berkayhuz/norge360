-- Bounded public profile/post copy. Private account details are stored
-- separately under owner-only RLS and never enter community profile queries.
alter table public.community_profiles
  add column if not exists biography text
  check (biography is null or char_length(trim(biography)) between 1 and 160);

alter table public.community_posts
  add column if not exists title text
  check (title is null or char_length(trim(title)) between 1 and 220);
