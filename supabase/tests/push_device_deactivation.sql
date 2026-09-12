-- Run against a disposable migrated database as its owner. Everything rolls back.
begin;

insert into auth.users(id) values
  ('60000000-0000-4000-8000-000000000001'),
  ('60000000-0000-4000-8000-000000000002');

set local role authenticated;
select set_config('request.jwt.claim.sub', '60000000-0000-4000-8000-000000000001', true);

select public.register_community_push_device(repeat('a', 64), 'development');
select public.deactivate_community_push_device(repeat('a', 64));

do $$ begin
  if exists (
    select 1
    from public.community_push_devices
    where token = repeat('a', 64) and is_active
  ) then
    raise exception 'device remained active after owner deactivation';
  end if;
end $$;

-- A different authenticated member cannot deactivate the first member's device.
select set_config('request.jwt.claim.sub', '60000000-0000-4000-8000-000000000001', true);
select public.register_community_push_device(repeat('a', 64), 'development');
select set_config('request.jwt.claim.sub', '60000000-0000-4000-8000-000000000002', true);
select public.deactivate_community_push_device(repeat('a', 64));

do $$ begin
  if not exists (
    select 1
    from public.community_push_devices
    where token = repeat('a', 64) and is_active
  ) then
    raise exception 'non-owner changed device state';
  end if;
end $$;

reset role;
rollback;
