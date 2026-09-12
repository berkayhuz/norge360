-- Run against a disposable migrated database as its owner. Everything rolls back.
begin;

do $$
begin
  if to_regprocedure('public.swap_own_community_profile_media(text,text)') is null
     or to_regclass('public.community_profile_media_cleanup_outbox') is null then
    raise exception
      'Missing prerequisite migrations: 20260912080000_secure_community_profile_media_updates.sql and 20260912081000_revoke_anon_profile_media_rpc.sql. Apply migrations in filename order before running this test.';
  end if;
end $$;

do $$
declare
  function_definition text;
begin
  select pg_get_functiondef(
    'public.swap_own_community_profile_media(text,text)'::regprocedure
  ) into function_definition;

  if position('for update' in lower(function_definition)) = 0
     or position('community_profile_media_cleanup_outbox' in lower(function_definition)) = 0
     or position('auth.uid()' in lower(function_definition)) = 0 then
    raise exception 'profile media swap RPC is not lock-aware, authenticated and cleanup-aware';
  end if;

  if has_function_privilege('anon', 'public.swap_own_community_profile_media(text,text)', 'execute') then
    raise exception 'anonymous role can execute profile media swap RPC';
  end if;
end $$;

insert into auth.users(id) values
  ('82000000-0000-4000-8000-000000000001'),
  ('82000000-0000-4000-8000-000000000002');

insert into public.community_profiles(user_id, display_name, username, preferred_locale, norway_status)
values
  ('82000000-0000-4000-8000-000000000001', 'Media Owner', 'media_owner', 'en', 'resident'),
  ('82000000-0000-4000-8000-000000000002', 'Other Member', 'other_member', 'en', 'resident');

set local role authenticated;
select set_config('request.jwt.claim.sub', '82000000-0000-4000-8000-000000000001', true);

select public.swap_own_community_profile_media(
  'avatar',
  '82000000-0000-4000-8000-000000000001/avatar-82000000-0000-4000-8000-000000000011.jpg'
);

do $$
begin
  if not exists (
    select 1
    from public.community_profiles
    where user_id = '82000000-0000-4000-8000-000000000001'
      and avatar_path = '82000000-0000-4000-8000-000000000001/avatar-82000000-0000-4000-8000-000000000011.jpg'
  ) then
    raise exception 'avatar path was not swapped';
  end if;
end $$;

select public.swap_own_community_profile_media(
  'avatar',
  '82000000-0000-4000-8000-000000000001/avatar-82000000-0000-4000-8000-000000000012.jpg'
);

reset role;

do $$
begin
  if not exists (
    select 1
    from public.community_profile_media_cleanup_outbox
    where bucket_id = 'avatars'
      and storage_path = '82000000-0000-4000-8000-000000000001/avatar-82000000-0000-4000-8000-000000000011.jpg'
      and processed_at is null
  ) then
    raise exception 'old avatar path was not queued for server cleanup';
  end if;
end $$;

set local role authenticated;

do $$
begin
  perform public.swap_own_community_profile_media(
    'avatar',
    '82000000-0000-4000-8000-000000000002/avatar-82000000-0000-4000-8000-000000000021.jpg'
  );
  raise exception 'cross-user profile media path was accepted';
exception
  when sqlstate '22023' then null;
end $$;

reset role;
rollback;
