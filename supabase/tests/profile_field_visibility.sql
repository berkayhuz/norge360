-- Run against a disposable migrated database as its owner. Everything rolls back.
begin;

insert into auth.users(id) values
  ('10000000-0000-4000-8000-000000000011'),
  ('10000000-0000-4000-8000-000000000012');

insert into public.community_profiles(
  user_id, display_name, username, preferred_locale, norway_status, city_or_region,
  show_norway_status, show_location
) values
  ('10000000-0000-4000-8000-000000000011', 'Hidden Profile', 'hidden_profile', 'en', 'planning_move', 'Oslo', false, false),
  ('10000000-0000-4000-8000-000000000012', 'Viewer Profile', 'viewer_profile', 'en', 'resident', 'Bergen', true, true);

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000012', true);

do $$
declare
  public_status text;
  public_city text;
begin
  select norway_status, city_or_region
    into public_status, public_city
  from public.community_public_profiles
  where user_id = '10000000-0000-4000-8000-000000000011';

  if public_status is not null or public_city is not null then
    raise exception 'hidden profile fields returned by public projection';
  end if;

  begin
    execute $sql$select norway_status from public.community_profiles where user_id = '10000000-0000-4000-8000-000000000011'$sql$;
    raise exception 'hidden profile column is directly readable';
  exception when insufficient_privilege then
    null;
  end;
end $$;

select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000011', true);
do $$
declare
  owner_status text;
  owner_city text;
begin
  select norway_status, city_or_region
    into owner_status, owner_city
  from public.get_my_community_profile();

  if owner_status <> 'planning_move' or owner_city <> 'Oslo' then
    raise exception 'owner profile RPC did not return the unmasked profile';
  end if;
end $$;

reset role;
rollback;
