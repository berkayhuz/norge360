-- A member can review only the people they have personally blocked. The
-- function intentionally does not act as a profile-discovery endpoint: its
-- result set is constrained to the caller's own user_blocks rows.

create or replace function public.list_own_community_blocks()
returns table (
  user_id uuid,
  display_name text,
  username text,
  avatar_path text,
  blocked_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    profile.user_id,
    profile.display_name,
    profile.username,
    profile.avatar_path,
    block.created_at as blocked_at
  from public.user_blocks as block
  join public.community_profiles as profile
    on profile.user_id = block.blocked_user_id
  where block.blocker_id = (select auth.uid())
  order by block.created_at desc;
$$;

revoke all on function public.list_own_community_blocks() from public;
grant execute on function public.list_own_community_blocks() to authenticated;
