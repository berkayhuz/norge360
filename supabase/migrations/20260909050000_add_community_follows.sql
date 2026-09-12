create table if not exists public.community_follows (
  follower_id uuid not null references auth.users(id) on delete cascade,
  following_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, following_id),
  constraint community_follows_no_self_follow check (follower_id <> following_id)
);

create index if not exists community_follows_following_created_idx
  on public.community_follows (following_id, created_at desc);

alter table public.community_follows enable row level security;

drop policy if exists "Users can view follows for visible profiles" on public.community_follows;
drop policy if exists "Users can follow visible profiles" on public.community_follows;
drop policy if exists "Users can unfollow profiles themselves" on public.community_follows;

create policy "Users can view follows for visible profiles"
on public.community_follows for select to authenticated
using (
  follower_id = (select auth.uid())
  or (
    public.can_view_community_user(following_id)
    and exists (
      select 1 from public.community_profiles as profile
      where profile.user_id = following_id and profile.is_public
    )
  )
);

create policy "Users can follow visible profiles"
on public.community_follows for insert to authenticated
with check (
  follower_id = (select auth.uid())
  and following_id <> (select auth.uid())
  and public.can_view_community_user(following_id)
  and exists (
    select 1 from public.community_profiles as profile
    where profile.user_id = following_id and profile.is_public
  )
);

create policy "Users can unfollow profiles themselves"
on public.community_follows for delete to authenticated
using (follower_id = (select auth.uid()));

create or replace function public.toggle_community_follow(target_user_id uuid)
returns boolean
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
  if target_user_id = actor_id then
    raise exception 'users cannot follow themselves';
  end if;
  if not public.can_view_community_user(target_user_id)
     or not exists (
       select 1 from public.community_profiles as profile
       where profile.user_id = target_user_id and profile.is_public
     ) then
    raise exception 'profile is not available';
  end if;

  if exists (
    select 1 from public.community_follows
    where follower_id = actor_id and following_id = target_user_id
  ) then
    delete from public.community_follows
    where follower_id = actor_id and following_id = target_user_id;
    return false;
  end if;

  insert into public.community_follows (follower_id, following_id)
  values (actor_id, target_user_id);
  return true;
end;
$$;

revoke all on function public.toggle_community_follow(uuid) from public;
grant execute on function public.toggle_community_follow(uuid) to authenticated;

create or replace function public.community_follow_state(target_user_id uuid)
returns table (is_following boolean, followers_count integer, following_count integer)
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
      select 1 from public.community_profiles as profile
      where profile.user_id = target_user_id and profile.is_public
    )
  ) then
    raise exception 'profile is not available';
  end if;

  return query
  select
    exists (
      select 1 from public.community_follows
      where follower_id = actor_id and following_id = target_user_id
    ),
    (select count(*)::integer from public.community_follows where following_id = target_user_id),
    (select count(*)::integer from public.community_follows where follower_id = target_user_id);
end;
$$;

revoke all on function public.community_follow_state(uuid) from public;
grant execute on function public.community_follow_state(uuid) to authenticated;
