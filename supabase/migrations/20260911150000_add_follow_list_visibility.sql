-- Follow-list visibility is enforced by security-definer RPCs. The iOS
-- client only receives a list after this database boundary approves it.

create table if not exists public.community_follow_visibility (
  user_id uuid primary key references auth.users(id) on delete cascade,
  followers_visibility text not null default 'everyone'
    check (followers_visibility in ('everyone', 'followers_only', 'following_only', 'nobody')),
  following_visibility text not null default 'everyone'
    check (following_visibility in ('everyone', 'followers_only', 'following_only', 'nobody')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.community_follow_visibility enable row level security;
revoke all on public.community_follow_visibility from anon, authenticated;

create or replace function public.get_community_follow_visibility()
returns table (followers_visibility text, following_visibility text)
language sql
stable
security definer
set search_path = ''
as $$
  select
    coalesce(preference.followers_visibility, 'everyone'),
    coalesce(preference.following_visibility, 'everyone')
  from (select (select auth.uid()) as user_id) as actor
  left join public.community_follow_visibility as preference
    on preference.user_id = actor.user_id;
$$;

create or replace function public.update_community_follow_visibility(
  followers_visibility text,
  following_visibility text
)
returns void
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

  if followers_visibility not in ('everyone', 'followers_only', 'following_only', 'nobody')
     or following_visibility not in ('everyone', 'followers_only', 'following_only', 'nobody') then
    raise exception 'invalid follow visibility';
  end if;

  insert into public.community_follow_visibility (
    user_id, followers_visibility, following_visibility
  )
  values (actor_id, followers_visibility, following_visibility)
  on conflict (user_id) do update set
    followers_visibility = excluded.followers_visibility,
    following_visibility = excluded.following_visibility,
    updated_at = now();
end;
$$;

create or replace function public.can_view_community_follow_list(
  target_user_id uuid,
  relationship text
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  visibility text;
begin
  if actor_id is null then
    return false;
  end if;
  if relationship not in ('followers', 'following') then
    return false;
  end if;
  if target_user_id = actor_id then
    return true;
  end if;
  if not exists (
    select 1
    from public.community_profiles as profile
    where profile.user_id = target_user_id
      and profile.is_public
      and public.can_view_community_user(target_user_id)
  ) then
    return false;
  end if;

  select case
    when relationship = 'followers' then preference.followers_visibility
    else preference.following_visibility
  end
  into visibility
  from public.community_follow_visibility as preference
  where preference.user_id = target_user_id;

  visibility := coalesce(visibility, 'everyone');
  return visibility = 'everyone'
    or (
      visibility = 'followers_only'
      and exists (
        select 1
        from public.community_follows as follow
        where follow.follower_id = actor_id
          and follow.following_id = target_user_id
      )
    )
    or (
      visibility = 'following_only'
      and exists (
        select 1
        from public.community_follows as follow
        where follow.follower_id = target_user_id
          and follow.following_id = actor_id
      )
    );
end;
$$;

drop function if exists public.list_community_follow_profiles(uuid, text);

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
  if not public.can_view_community_follow_list(target_user_id, relationship) then
    raise exception 'follow list unavailable';
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

drop function if exists public.community_follow_state(uuid);

create function public.community_follow_state(target_user_id uuid)
returns table (
  is_following boolean,
  followers_count integer,
  following_count integer,
  can_view_followers boolean,
  can_view_following boolean
)
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
  if target_user_id <> actor_id and (
    not public.can_view_community_user(target_user_id)
    or not exists (
      select 1
      from public.community_profiles as profile
      where profile.user_id = target_user_id and profile.is_public
    )
  ) then
    raise exception 'profile is not available';
  end if;

  return query
  select
    exists (
      select 1
      from public.community_follows
      where follower_id = actor_id and following_id = target_user_id
    ),
    (select count(*)::integer from public.community_follows where following_id = target_user_id),
    (select count(*)::integer from public.community_follows where follower_id = target_user_id),
    public.can_view_community_follow_list(target_user_id, 'followers'),
    public.can_view_community_follow_list(target_user_id, 'following');
end;
$$;

revoke all on function public.get_community_follow_visibility() from public;
revoke all on function public.update_community_follow_visibility(text, text) from public;
revoke all on function public.can_view_community_follow_list(uuid, text) from public;
revoke all on function public.list_community_follow_profiles(uuid, text) from public;
revoke all on function public.community_follow_state(uuid) from public;
grant execute on function public.get_community_follow_visibility() to authenticated;
grant execute on function public.update_community_follow_visibility(text, text) to authenticated;
grant execute on function public.list_community_follow_profiles(uuid, text) to authenticated;
grant execute on function public.community_follow_state(uuid) to authenticated;
