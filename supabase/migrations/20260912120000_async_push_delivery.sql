-- Push delivery is an asynchronous transport concern. The webhook only
-- enqueues a pointer; the Worker owns eligibility, APNs delivery and retries.

create table if not exists public.community_push_delivery_ledger (
  event_id uuid not null,
  device_id uuid not null references public.community_push_devices(id) on delete cascade,
  source_table text not null check (source_table in (
    'community_notifications',
    'community_message_signals',
    'community_group_chat_signals'
  )),
  status text not null default 'pending' check (
    status in ('pending', 'processing', 'delivered', 'invalid_device', 'failed')
  ),
  attempts integer not null default 0 check (attempts >= 0),
  lease_until timestamptz,
  delivered_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (event_id, device_id)
);

create index if not exists community_push_delivery_ledger_retry_idx
  on public.community_push_delivery_ledger (status, lease_until, updated_at)
  where status in ('pending', 'processing');

alter table public.community_push_delivery_ledger enable row level security;
revoke all on public.community_push_delivery_ledger from anon, authenticated;
revoke all on public.community_push_delivery_ledger from public;
grant all on public.community_push_delivery_ledger to service_role;

create or replace function public.claim_community_push_deliveries(
  target_source_table text,
  target_event_id uuid,
  target_device_ids uuid[],
  target_lease_seconds integer default 120
)
returns table(device_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if target_source_table not in (
       'community_notifications',
       'community_message_signals',
       'community_group_chat_signals'
     )
     or target_event_id is null
     or coalesce(cardinality(target_device_ids), 0) = 0
     or target_lease_seconds is null
     or target_lease_seconds < 30
     or target_lease_seconds > 600 then
    raise exception 'invalid push delivery claim';
  end if;

  return query
  with requested as (
    select distinct requested_device_id as device_id
    from unnest(target_device_ids) as requested(requested_device_id)
  ),
  claimed as (
    insert into public.community_push_delivery_ledger as ledger (
      event_id,
      device_id,
      source_table,
      status,
      attempts,
      lease_until,
      delivered_at,
      last_error,
      updated_at
    )
    select
      target_event_id,
      requested.device_id,
      target_source_table,
      'processing',
      1,
      now() + make_interval(secs => target_lease_seconds),
      null,
      null,
      now()
    from requested
    where exists (
      select 1
      from public.community_push_devices as device
      where device.id = requested.device_id
        and device.is_active
    )
    on conflict on constraint community_push_delivery_ledger_pkey do update
    set source_table = excluded.source_table,
        status = 'processing',
        attempts = ledger.attempts + 1,
        lease_until = now() + make_interval(secs => target_lease_seconds),
        delivered_at = null,
        last_error = null,
        updated_at = now()
    where ledger.status not in ('delivered', 'invalid_device', 'failed')
      and (ledger.lease_until is null or ledger.lease_until <= now())
      and ledger.attempts < 5
    returning ledger.device_id
  )
  select claimed.device_id
  from claimed;
end;
$$;

create or replace function public.finalize_community_push_deliveries(
  target_deliveries jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  delivery record;
  changed boolean;
begin
  if jsonb_typeof(target_deliveries) <> 'array'
     or jsonb_array_length(target_deliveries) = 0
     or jsonb_array_length(target_deliveries) > 50 then
    raise exception 'invalid push delivery finalization';
  end if;

  for delivery in
    select *
    from jsonb_to_recordset(target_deliveries) as item(
      event_id uuid,
      device_id uuid,
      outcome text,
      apns_status integer,
      error_code text
    )
  loop
    if delivery.event_id is null
       or delivery.device_id is null
       or delivery.outcome not in ('delivered', 'invalid_device', 'retry', 'failed') then
      raise exception 'invalid push delivery result';
    end if;

    update public.community_push_delivery_ledger
    set status = case delivery.outcome
          when 'delivered' then 'delivered'
          when 'invalid_device' then 'invalid_device'
          when 'retry' then 'pending'
          else 'failed'
        end,
        lease_until = null,
        delivered_at = case when delivery.outcome = 'delivered' then now() else null end,
        last_error = case
          when delivery.outcome in ('delivered', 'invalid_device') then null
          else left(coalesce(delivery.error_code, 'push_delivery_failed'), 100)
        end,
        updated_at = now()
    where event_id = delivery.event_id
      and device_id = delivery.device_id
      and status = 'processing';
    changed := found;

    if changed and delivery.outcome = 'delivered' then
      update public.community_push_devices
      set last_delivery_at = now(),
          updated_at = now()
      where id = delivery.device_id;
    elsif changed and delivery.outcome = 'invalid_device' then
      update public.community_push_devices
      set is_active = false,
          deactivated_at = now(),
          updated_at = now()
      where id = delivery.device_id;
    end if;
  end loop;
end;
$$;

revoke all on function public.claim_community_push_deliveries(text, uuid, uuid[], integer) from public;
revoke all on function public.finalize_community_push_deliveries(jsonb) from public;
revoke all on function public.claim_community_push_deliveries(text, uuid, uuid[], integer) from anon, authenticated;
revoke all on function public.finalize_community_push_deliveries(jsonb) from anon, authenticated;
grant execute on function public.claim_community_push_deliveries(text, uuid, uuid[], integer) to service_role;
grant execute on function public.finalize_community_push_deliveries(jsonb) to service_role;
