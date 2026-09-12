-- Run against a disposable migrated database as its owner. Everything rolls back.
begin;

do $$
begin
  if not has_column_privilege('authenticated', 'public.community_profiles', 'display_name', 'INSERT') then
    raise exception 'authenticated role cannot insert community profiles';
  end if;

  if not has_column_privilege('authenticated', 'public.community_profiles', 'display_name', 'UPDATE') then
    raise exception 'authenticated role cannot update community profile details';
  end if;

  if not has_column_privilege('authenticated', 'public.community_profiles', 'is_public', 'UPDATE') then
    raise exception 'authenticated role cannot update community profile visibility';
  end if;

  if not has_table_privilege('authenticated', 'public.community_profiles', 'DELETE') then
    raise exception 'authenticated role cannot delete its community profile';
  end if;

  if has_column_privilege('authenticated', 'public.community_profiles', 'norway_status', 'SELECT') then
    raise exception 'authenticated role can directly read private relocation status';
  end if;
end $$;

insert into auth.users(id)
values ('10000000-0000-4000-8000-000000000013')
on conflict (id) do nothing;

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000013', true);

select public.upsert_own_community_profile(
  'Grant Test Member',
  'grant_test_member',
  'en',
  'planning_move',
  'Oslo',
  array['en']::text[],
  array['work']::text[],
  true
);

do $$
declare
  saved_name text;
  saved_city text;
begin
  select display_name, city_or_region
    into saved_name, saved_city
  from public.get_my_community_profile();

  if saved_name <> 'Grant Test Member' or saved_city <> 'Oslo' then
    raise exception 'owner profile upsert RPC did not persist the profile';
  end if;
end $$;

reset role;

rollback;
