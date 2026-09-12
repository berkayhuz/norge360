-- The public profile projection intentionally removed direct table access.
-- Reassert the complete privilege boundary here because Supabase's automatic
-- API exposure can otherwise leave broad role grants in a local or existing
-- project. RLS remains the authorization boundary for every write below.
revoke all on public.community_profiles from public, anon, authenticated;

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

grant insert (
  user_id,
  display_name,
  username,
  preferred_locale,
  norway_status,
  city_or_region,
  public_languages,
  interests,
  is_public
) on public.community_profiles to authenticated;

grant update (
  display_name,
  username,
  preferred_locale,
  norway_status,
  city_or_region,
  public_languages,
  interests,
  is_public,
  show_norway_status,
  show_location,
  biography
) on public.community_profiles to authenticated;

grant delete on public.community_profiles to authenticated;

-- PostgreSQL requires SELECT privileges on columns read by an
-- INSERT ... ON CONFLICT DO UPDATE statement. The onboarding upsert includes
-- private relocation fields, so keep those fields behind an owner-only RPC
-- instead of granting them direct table SELECT access to the client role.
create or replace function public.upsert_own_community_profile(
  profile_display_name text,
  profile_username text,
  profile_preferred_locale text,
  profile_norway_status text,
  profile_city_or_region text,
  profile_public_languages text[],
  profile_interests text[],
  profile_is_public boolean
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
    raise exception 'authentication required' using errcode = '42501';
  end if;

  insert into public.community_profiles (
    user_id,
    display_name,
    username,
    preferred_locale,
    norway_status,
    city_or_region,
    public_languages,
    interests,
    is_public
  ) values (
    actor_id,
    profile_display_name,
    profile_username,
    profile_preferred_locale,
    profile_norway_status,
    profile_city_or_region,
    profile_public_languages,
    profile_interests,
    profile_is_public
  )
  on conflict (user_id) do update set
    display_name = excluded.display_name,
    username = excluded.username,
    preferred_locale = excluded.preferred_locale,
    norway_status = excluded.norway_status,
    city_or_region = excluded.city_or_region,
    public_languages = excluded.public_languages,
    interests = excluded.interests,
    is_public = excluded.is_public;
end;
$$;

revoke all on function public.upsert_own_community_profile(
  text, text, text, text, text, text[], text[], boolean
) from public, anon;
grant execute on function public.upsert_own_community_profile(
  text, text, text, text, text, text[], text[], boolean
) to authenticated;
