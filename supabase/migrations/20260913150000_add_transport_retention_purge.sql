-- Transport ledgers and cleanup outboxes are operational state, not permanent
-- member data. Keep a bounded replay/audit window, then purge terminal rows in
-- small service-owned batches so indexes and backups cannot grow forever.

create or replace function public.purge_community_transport_retention(
  target_batch_size integer default 500
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  removed bigint := 0;
  deleted_count bigint;
begin
  if coalesce(current_setting('request.jwt.claim.role', true), '') <> 'service_role' then
    raise exception 'service role required' using errcode = '42501';
  end if;
  if target_batch_size is null or target_batch_size < 1 or target_batch_size > 5000 then
    raise exception 'invalid transport retention batch size';
  end if;

  -- Keep one month of idempotency/replay evidence. A processing row with five
  -- attempts is no longer recoverable by the claim function and is terminal
  -- for retention purposes; active leases are newer than this cutoff.
  with eligible as (
    select ledger.event_id, ledger.device_id
    from public.community_push_delivery_ledger as ledger
    where ledger.updated_at <= now() - interval '30 days'
      and (
        ledger.status in ('pending', 'delivered', 'invalid_device', 'failed')
        or (ledger.status = 'processing' and ledger.attempts >= 5)
      )
    order by ledger.updated_at asc, ledger.event_id, ledger.device_id
    limit target_batch_size
    for update skip locked
  )
  delete from public.community_push_delivery_ledger as ledger
  using eligible
  where ledger.event_id = eligible.event_id
    and ledger.device_id = eligible.device_id;
  get diagnostics deleted_count = row_count;
  removed := removed + deleted_count;

  -- Successful object deletion has already been acknowledged by the Worker;
  -- retain only a short operational audit window.
  with eligible as (
    select outbox.id
    from public.community_profile_media_cleanup_outbox as outbox
    where outbox.processed_at <= now() - interval '7 days'
    order by outbox.processed_at asc, outbox.id
    limit target_batch_size
    for update skip locked
  )
  delete from public.community_profile_media_cleanup_outbox as outbox
  using eligible
  where outbox.id = eligible.id;
  get diagnostics deleted_count = row_count;
  removed := removed + deleted_count;

  with eligible as (
    select outbox.id
    from public.community_storage_cleanup_outbox as outbox
    where outbox.processed_at <= now() - interval '7 days'
    order by outbox.processed_at asc, outbox.id
    limit target_batch_size
    for update skip locked
  )
  delete from public.community_storage_cleanup_outbox as outbox
  using eligible
  where outbox.id = eligible.id;
  get diagnostics deleted_count = row_count;
  removed := removed + deleted_count;

  with eligible as (
    select job.id
    from public.community_group_chat_push_fanout_jobs as job
    where job.status = 'completed'
      and job.completed_at <= now() - interval '7 days'
    order by job.completed_at asc, job.id
    limit target_batch_size
    for update skip locked
  )
  delete from public.community_group_chat_push_fanout_jobs as job
  using eligible
  where job.id = eligible.id;
  get diagnostics deleted_count = row_count;
  removed := removed + deleted_count;

  return removed;
end;
$$;

revoke all on function public.purge_community_transport_retention(integer) from public, anon, authenticated;
grant execute on function public.purge_community_transport_retention(integer) to service_role;

comment on function public.purge_community_transport_retention(integer) is
  'Purges old terminal push ledger, processed media cleanup, and completed fan-out rows in bounded service-owned batches.';
