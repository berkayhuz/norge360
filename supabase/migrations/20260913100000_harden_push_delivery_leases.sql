-- Make push retries observable and recover deliveries whose Worker lease
-- expired before finalization. The queue message is only a pointer; the
-- ledger remains the durable source of delivery state.

drop function if exists public.claim_community_push_deliveries(text, uuid, uuid[], integer);

create function public.claim_community_push_deliveries(
  target_source_table text,
  target_event_id uuid,
  target_device_ids uuid[],
  target_lease_seconds integer default 120
)
returns table(
  device_id uuid,
  claim_state text,
  lease_until timestamptz,
  attempts integer
)
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
     or cardinality(target_device_ids) > 50
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
  active_requested as (
    select requested.device_id
    from requested
    join public.community_push_devices as device
      on device.id = requested.device_id
     and device.is_active
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
    from active_requested as requested
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
  select
    requested.device_id,
    case
      when claimed.device_id is not null then 'claimed'
      when ledger.device_id is null then 'available'
      when ledger.status in ('delivered', 'invalid_device', 'failed')
        or ledger.attempts >= 5 then 'terminal'
      when ledger.status = 'processing'
        and ledger.lease_until > now() then 'leased'
      else 'available'
    end,
    ledger.lease_until,
    coalesce(ledger.attempts, 0)
  from active_requested as requested
  left join public.community_push_delivery_ledger as ledger
    on ledger.event_id = target_event_id
   and ledger.device_id = requested.device_id
  left join claimed
    on claimed.device_id = requested.device_id;
end;
$$;

-- Atomically move expired leases back to pending before publishing recovery
-- pointers. If publishing fails, the next scheduled pass can safely retry.
create or replace function public.requeue_expired_community_push_deliveries(
  target_batch_size integer default 100
)
returns table(source_table text, event_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if target_batch_size is null or target_batch_size < 1 or target_batch_size > 500 then
    raise exception 'invalid push delivery recovery batch';
  end if;

  return query
  with expired as (
    select ledger.event_id, ledger.device_id
    from public.community_push_delivery_ledger as ledger
    where ledger.status = 'processing'
      and ledger.lease_until is not null
      and ledger.lease_until <= now()
      and ledger.attempts < 5
    order by ledger.lease_until asc, ledger.updated_at asc
    limit target_batch_size
    for update skip locked
  ),
  requeued as (
    update public.community_push_delivery_ledger as ledger
    set status = 'pending',
        lease_until = null,
        updated_at = now()
    from expired
    where ledger.event_id = expired.event_id
      and ledger.device_id = expired.device_id
    returning ledger.event_id, ledger.source_table
  )
  select requeued.source_table, requeued.event_id
  from requeued;
end;
$$;

revoke all on function public.claim_community_push_deliveries(text, uuid, uuid[], integer) from public, anon, authenticated;
revoke all on function public.requeue_expired_community_push_deliveries(integer) from public, anon, authenticated;
grant execute on function public.claim_community_push_deliveries(text, uuid, uuid[], integer) to service_role;
grant execute on function public.requeue_expired_community_push_deliveries(integer) to service_role;
