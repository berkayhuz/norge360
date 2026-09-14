-- Run against a disposable, fully migrated database as its owner.
-- This verifies the atomic boundary used by search, username availability,
-- and server-owned account export requests.
begin;

insert into auth.users(id)
values ('a4000000-0000-4000-8000-000000000001');

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claim.sub',
  'a4000000-0000-4000-8000-000000000001',
  true
);

do $$
declare
  attempt integer;
  quota record;
begin
  for attempt in 1..60 loop
    select * into quota
    from public.consume_community_request_rate_limit('search_profiles', 60, 60);
    if not quota.allowed then
      raise exception 'search quota was exhausted too early at attempt %', attempt;
    end if;
  end loop;

  select * into quota
  from public.consume_community_request_rate_limit('search_profiles', 60, 60);
  if quota.allowed then
    raise exception 'search quota allowed a request after the configured limit';
  end if;

  begin
    perform public.consume_community_request_rate_limit(
      'account_export', 3, 3600, 'a4000000-0000-4000-8000-000000000002'
    );
    raise exception 'authenticated member could consume another member quota';
  exception when others then
    if sqlerrm <> 'rate limit identity mismatch' then
      raise;
    end if;
  end;
end;
$$;

reset role;
set local role service_role;
select set_config('request.jwt.claim.role', 'service_role', true);

do $$
declare
  quota record;
begin
  select * into quota
  from public.consume_community_request_rate_limit(
    'account_export', 3, 3600, 'a4000000-0000-4000-8000-000000000001'
  );
  if not quota.allowed then
    raise exception 'service role could not consume an explicit member quota';
  end if;
end;
$$;

rollback;
