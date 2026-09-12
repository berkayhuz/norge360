-- Run against a disposable migrated database as its owner. Everything rolls back.
begin;

do $$
begin
  if has_table_privilege('anon', 'public.community_public_profiles', 'SELECT') then
    raise exception 'anonymous role can read public profile projection';
  end if;

  if not has_table_privilege('authenticated', 'public.community_public_profiles', 'SELECT') then
    raise exception 'authenticated role cannot read public profile projection';
  end if;

  if has_table_privilege('authenticated', 'public.community_public_profiles', 'INSERT')
     or has_table_privilege('authenticated', 'public.community_public_profiles', 'UPDATE')
     or has_table_privilege('authenticated', 'public.community_public_profiles', 'DELETE') then
    raise exception 'authenticated role has write privilege on public profile projection';
  end if;

  if has_table_privilege('anon', 'public.community_member_profile_stats', 'SELECT') then
    raise exception 'anonymous role can read member profile stats projection';
  end if;

  if not has_table_privilege('authenticated', 'public.community_member_profile_stats', 'SELECT') then
    raise exception 'authenticated role cannot read member profile stats projection';
  end if;

  if has_table_privilege('authenticated', 'public.community_member_profile_stats', 'INSERT')
     or has_table_privilege('authenticated', 'public.community_member_profile_stats', 'UPDATE')
     or has_table_privilege('authenticated', 'public.community_member_profile_stats', 'DELETE') then
    raise exception 'authenticated role has write privilege on member profile stats projection';
  end if;

  if has_table_privilege('authenticated', 'public.community_profiles', 'SELECT') then
    raise exception 'authenticated role has broad table SELECT on private profile source';
  end if;
end $$;

rollback;
