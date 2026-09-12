-- Liked-post visibility is enforced by security-definer RPCs. The iOS client
-- receives the liked-post tab only after this database boundary approves it.

create table if not exists public.community_liked_posts_visibility (
  user_id uuid primary key references auth.users(id) on delete cascade,
  visibility text not null default 'only_me'
    check (visibility in ('everyone', 'only_me')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.community_liked_posts_visibility enable row level security;
revoke all on public.community_liked_posts_visibility from anon, authenticated;

create or replace function public.get_community_liked_posts_visibility()
returns table (visibility text)
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(preference.visibility, 'only_me')
  from (select (select auth.uid()) as user_id) as actor
  left join public.community_liked_posts_visibility as preference
    on preference.user_id = actor.user_id;
$$;

create or replace function public.update_community_liked_posts_visibility(
  next_visibility text
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
  if next_visibility not in ('everyone', 'only_me') then
    raise exception 'invalid liked-post visibility';
  end if;

  insert into public.community_liked_posts_visibility (user_id, visibility)
  values (actor_id, next_visibility)
  on conflict (user_id) do update set
    visibility = excluded.visibility,
    updated_at = now();
end;
$$;

create or replace function public.can_view_community_liked_posts(target_user_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  target_visibility text;
begin
  if actor_id is null then
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

  select preference.visibility
  into target_visibility
  from public.community_liked_posts_visibility as preference
  where preference.user_id = target_user_id;

  return coalesce(target_visibility, 'only_me') = 'everyone';
end;
$$;

create or replace function public.list_community_liked_post_ids(target_user_id uuid)
returns table (post_id uuid)
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
  if not public.can_view_community_liked_posts(target_user_id) then
    raise exception 'liked posts unavailable';
  end if;

  return query
  select like_row.post_id
  from public.community_post_likes as like_row
  join public.community_posts as post on post.id = like_row.post_id
  join public.community_profiles as profile on profile.user_id = post.author_id
  where like_row.user_id = target_user_id
    and (
      post.author_id = actor_id
      or (
        profile.is_public
        and public.can_view_community_user(post.author_id)
      )
    )
  order by like_row.created_at desc
  limit 30;
end;
$$;

drop function if exists public.community_follow_state(uuid);

create function public.community_follow_state(target_user_id uuid)
returns table (
  is_following boolean,
  followers_count integer,
  following_count integer,
  can_view_followers boolean,
  can_view_following boolean,
  can_view_liked_posts boolean
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
    public.can_view_community_follow_list(target_user_id, 'following'),
    public.can_view_community_liked_posts(target_user_id);
end;
$$;

revoke all on function public.get_community_liked_posts_visibility() from public;
revoke all on function public.update_community_liked_posts_visibility(text) from public;
revoke all on function public.can_view_community_liked_posts(uuid) from public;
revoke all on function public.list_community_liked_post_ids(uuid) from public;
revoke all on function public.community_follow_state(uuid) from public;
grant execute on function public.get_community_liked_posts_visibility() to authenticated;
grant execute on function public.update_community_liked_posts_visibility(text) to authenticated;
grant execute on function public.list_community_liked_post_ids(uuid) to authenticated;
grant execute on function public.community_follow_state(uuid) to authenticated;
