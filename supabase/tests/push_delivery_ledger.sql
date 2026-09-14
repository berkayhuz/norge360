-- Run against a disposable, fully migrated database as its owner.
-- The ledger and RPCs are service-role-only; everything rolls back.
begin;

do $$
begin
  if to_regprocedure('public.claim_community_push_deliveries(text,uuid,uuid[],integer)') is null
     or to_regprocedure('public.finalize_community_push_deliveries(jsonb)') is null then
    raise exception 'Missing push delivery ledger migration';
  end if;

  if has_function_privilege(
       'anon',
       'public.claim_community_push_deliveries(text,uuid,uuid[],integer)',
       'execute'
     )
     or has_function_privilege(
       'authenticated',
       'public.claim_community_push_deliveries(text,uuid,uuid[],integer)',
       'execute'
     )
     or has_function_privilege(
       'anon',
       'public.finalize_community_push_deliveries(jsonb)',
       'execute'
     )
     or has_function_privilege(
       'authenticated',
       'public.finalize_community_push_deliveries(jsonb)',
       'execute'
     ) then
    raise exception 'client role can execute private push delivery RPCs';
  end if;

  if not has_function_privilege(
       'service_role',
       'public.claim_community_push_deliveries(text,uuid,uuid[],integer)',
       'execute'
     )
     or not has_function_privilege(
       'service_role',
       'public.finalize_community_push_deliveries(jsonb)',
       'execute'
     ) then
    raise exception 'service role cannot execute push delivery RPCs';
  end if;
end $$;

insert into auth.users(id) values
  ('a1000000-0000-4000-8000-000000000001'),
  ('a1000000-0000-4000-8000-000000000002');

insert into public.community_push_devices(id, user_id, token, environment)
values
  (
    'a2000000-0000-4000-8000-000000000001',
    'a1000000-0000-4000-8000-000000000001',
    repeat('a', 64),
    'development'
  ),
  (
    'a2000000-0000-4000-8000-000000000002',
    'a1000000-0000-4000-8000-000000000002',
    repeat('b', 64),
    'production'
  );

do $$
declare
  claimed_count integer;
begin
  select count(*) into claimed_count
  from public.claim_community_push_deliveries(
    'community_message_signals',
    'a3000000-0000-4000-8000-000000000001',
    array[
      'a2000000-0000-4000-8000-000000000001'::uuid,
      'a2000000-0000-4000-8000-000000000002'::uuid
    ]
  )
  where claim_state = 'claimed';
  if claimed_count <> 2 then
    raise exception 'expected two initial push delivery claims, got %', claimed_count;
  end if;

  select count(*) into claimed_count
  from public.claim_community_push_deliveries(
    'community_message_signals',
    'a3000000-0000-4000-8000-000000000001',
    array[
      'a2000000-0000-4000-8000-000000000001'::uuid,
      'a2000000-0000-4000-8000-000000000002'::uuid
    ]
  )
  where claim_state = 'claimed';
  if claimed_count <> 0 then
    raise exception 'active delivery lease was claimed twice';
  end if;
end $$;

select public.finalize_community_push_deliveries(
  jsonb_build_array(
    jsonb_build_object(
      'event_id', 'a3000000-0000-4000-8000-000000000001',
      'device_id', 'a2000000-0000-4000-8000-000000000001',
      'outcome', 'delivered',
      'apns_status', 200
    ),
    jsonb_build_object(
      'event_id', 'a3000000-0000-4000-8000-000000000001',
      'device_id', 'a2000000-0000-4000-8000-000000000002',
      'outcome', 'invalid_device',
      'apns_status', 410,
      'error_code', 'Unregistered'
    )
  )
);

do $$
declare
  delivered_status text;
  invalid_status text;
  invalid_active boolean;
  reclaimed_count integer;
begin
  select status into delivered_status
  from public.community_push_delivery_ledger
  where event_id = 'a3000000-0000-4000-8000-000000000001'
    and device_id = 'a2000000-0000-4000-8000-000000000001';
  select status into invalid_status
  from public.community_push_delivery_ledger
  where event_id = 'a3000000-0000-4000-8000-000000000001'
    and device_id = 'a2000000-0000-4000-8000-000000000002';
  select is_active into invalid_active
  from public.community_push_devices
  where id = 'a2000000-0000-4000-8000-000000000002';

  if delivered_status <> 'delivered'
     or invalid_status <> 'invalid_device'
     or invalid_active then
    raise exception 'push delivery finalization did not persist terminal outcomes';
  end if;

  select count(*) into reclaimed_count
  from public.claim_community_push_deliveries(
    'community_message_signals',
    'a3000000-0000-4000-8000-000000000001',
    array[
      'a2000000-0000-4000-8000-000000000001'::uuid,
      'a2000000-0000-4000-8000-000000000002'::uuid
    ]
  )
  where claim_state = 'claimed';
  if reclaimed_count <> 0 then
    raise exception 'terminal push delivery was claimed again';
  end if;
end $$;

rollback;
