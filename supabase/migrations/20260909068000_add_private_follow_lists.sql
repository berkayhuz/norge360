-- Follow lists must not become a side channel for private profiles or blocks.
-- This RPC returns only profiles that the requesting member is allowed to see.

create index if not exists community_follows_follower_created_idx
  on public.community_follows (follower_id, created_at desc);

create or replace function public.list_community_follow_profiles(
  target_user_id uuid,
  relationship text
)
returns setof public.community_profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
begin
  if actor_id is null then
    raise exception 'authentication required';
  end if;

  if relationship not in ('followers', 'following') then
    raise exception 'invalid follow relationship';
  end if;

  if target_user_id <> actor_id and not exists (
    select 1
    from public.community_profiles as target_profile
    where target_profile.user_id = target_user_id
      and target_profile.is_public
      and public.can_view_community_user(target_user_id)
  ) then
    raise exception 'profile is not available';
  end if;

  if relationship = 'followers' then
    return query
      select profile.*
      from public.community_follows as follow
      join public.community_profiles as profile on profile.user_id = follow.follower_id
      where follow.following_id = target_user_id
        and profile.is_public
        and public.can_view_community_user(profile.user_id)
      order by follow.created_at desc
      limit 100;
  end if;

  return query
    select profile.*
    from public.community_follows as follow
    join public.community_profiles as profile on profile.user_id = follow.following_id
    where follow.follower_id = target_user_id
      and profile.is_public
      and public.can_view_community_user(profile.user_id)
    order by follow.created_at desc
    limit 100;
end;
$$;

revoke all on function public.list_community_follow_profiles(uuid, text) from public;
grant execute on function public.list_community_follow_profiles(uuid, text) to authenticated;
