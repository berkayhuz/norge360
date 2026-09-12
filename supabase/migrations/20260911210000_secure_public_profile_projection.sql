-- Keep public profile reads on an explicit, database-owned projection. The
-- source table contains relocation context and moderation state that must not
-- be exposed as a generic PostgREST row.
drop view if exists public.community_public_profiles;

create view public.community_public_profiles
with (security_barrier = true)
as
select
  profile.user_id,
  profile.display_name,
  profile.username,
  profile.preferred_locale,
  case when profile.show_norway_status then profile.norway_status else null end as norway_status,
  case when profile.show_location then profile.city_or_region else null end as city_or_region,
  profile.public_languages,
  profile.interests,
  profile.is_public,
  profile.show_norway_status,
  profile.show_location,
  profile.biography,
  profile.avatar_path,
  profile.cover_path,
  profile.created_at,
  profile.updated_at
from public.community_profiles as profile
where profile.is_public
  and profile.moderation_state = 'active'
  and public.can_view_community_user(profile.user_id);

revoke all on public.community_public_profiles from public, anon;
grant select on public.community_public_profiles to authenticated;

-- The owner still needs the unmasked profile for settings and editing. Keep
-- this contract explicit so future columns do not leak through an RPC result.
create or replace function public.get_my_community_profile()
returns table (
  user_id uuid,
  display_name text,
  username text,
  preferred_locale text,
  norway_status text,
  city_or_region text,
  public_languages text[],
  interests text[],
  is_public boolean,
  show_norway_status boolean,
  show_location boolean,
  biography text,
  avatar_path text,
  cover_path text,
  created_at timestamptz,
  updated_at timestamptz
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
    profile.preferred_locale,
    profile.norway_status,
    profile.city_or_region,
    profile.public_languages,
    profile.interests,
    profile.is_public,
    profile.show_norway_status,
    profile.show_location,
    profile.biography,
    profile.avatar_path,
    profile.cover_path,
    profile.created_at,
    profile.updated_at
  from public.community_profiles as profile
  where profile.user_id = (select auth.uid());
$$;

revoke all on function public.get_my_community_profile() from public;
grant execute on function public.get_my_community_profile() to authenticated;

-- Preserve RLS/policy checks that inspect non-sensitive profile state while
-- removing the table-level SELECT privilege. Hidden relocation fields are not
-- granted, so direct REST queries for them fail at the database boundary.
revoke select on public.community_profiles from public, anon, authenticated;
grant select (
  user_id,
  display_name,
  username,
  preferred_locale,
  public_languages,
  interests,
  is_public,
  show_norway_status,
  show_location,
  biography,
  avatar_path,
  cover_path,
  moderation_state,
  created_at,
  updated_at
) on public.community_profiles to authenticated;

drop function if exists public.search_community_profiles(text);

create function public.search_community_profiles(search_query text)
returns setof public.community_public_profiles
language sql
stable
security definer
set search_path = ''
as $$
  with normalized as (
    select btrim(replace(replace(replace(search_query, E'\\', ''), '%', ''), '_', '')) as value
  )
  select profile.*
  from public.community_public_profiles as profile, normalized
  where char_length(normalized.value) between 3 and 80
    and (
      profile.display_name ilike '%' || normalized.value || '%'
      or profile.username ilike '%' || normalized.value || '%'
    )
  order by
    case when profile.username ilike normalized.value || '%' then 0 else 1 end,
    profile.username asc
  limit 12;
$$;

revoke all on function public.search_community_profiles(text) from public;
grant execute on function public.search_community_profiles(text) to authenticated;

drop function if exists public.list_community_follow_profiles(uuid, text);

create function public.list_community_follow_profiles(
  target_user_id uuid,
  relationship text
)
returns setof public.community_public_profiles
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
      join public.community_public_profiles as profile on profile.user_id = follow.follower_id
      where follow.following_id = target_user_id
      order by follow.created_at desc
      limit 100;
  end if;

  return query
    select profile.*
    from public.community_follows as follow
    join public.community_public_profiles as profile on profile.user_id = follow.following_id
    where follow.follower_id = target_user_id
    order by follow.created_at desc
    limit 100;
end;
$$;

revoke all on function public.list_community_follow_profiles(uuid, text) from public;
grant execute on function public.list_community_follow_profiles(uuid, text) to authenticated;
