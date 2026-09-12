-- Move provider deletion for unattached private media out of the scheduled
-- request. The attachment row is the durable cleanup state; Queue delivery is
-- at-least-once and finalization is intentionally idempotent.

create index if not exists community_group_chat_attachments_cleanup_candidates_idx
  on public.community_group_chat_attachments (status, created_at)
  where message_id is null
    and storage_provider = 'cloudflare_images'
    and status in ('pending_upload', 'pending_scan', 'ready', 'rejected', 'deleted');

create index if not exists community_direct_message_attachments_cleanup_candidates_idx
  on public.community_direct_message_attachments (status, created_at)
  where message_id is null
    and storage_provider = 'cloudflare_images'
    and status in ('pending_upload', 'pending_scan', 'ready', 'rejected', 'deleted');

create or replace function public.claim_expired_community_media_attachments(
  target_media_type text,
  target_batch_size integer default 50
)
returns table (
  attachment_id uuid,
  provider_asset_id text
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if target_media_type not in ('group', 'direct') then
    return;
  end if;
  if target_batch_size is null or target_batch_size < 1 or target_batch_size > 50 then
    raise exception 'invalid cleanup batch size';
  end if;

  if target_media_type = 'group' then
    return query
    with candidate_rows as (
      select attachment.id
      from public.community_group_chat_attachments as attachment
      where attachment.message_id is null
        and attachment.storage_provider = 'cloudflare_images'
        and (
          (
            attachment.status in ('pending_upload', 'pending_scan')
            and attachment.created_at < now() - interval '1 hour'
          )
          or (
            attachment.status in ('ready', 'rejected')
            and attachment.created_at < now() - interval '1 day'
          )
          or (
            attachment.status = 'deleted'
            and coalesce(attachment.deleted_at, attachment.created_at) < now() - interval '5 minutes'
          )
      )
      order by attachment.created_at asc
      limit target_batch_size
      for update skip locked
    ), claimed_rows as (
      update public.community_group_chat_attachments as attachment
      set status = 'deleted',
        deleted_at = now()
      from candidate_rows
      where attachment.id = candidate_rows.id
      returning attachment.id, attachment.provider_asset_id
    )
    select claimed_rows.id, claimed_rows.provider_asset_id
    from claimed_rows;
  else
    return query
    with candidate_rows as (
      select attachment.id
      from public.community_direct_message_attachments as attachment
      where attachment.message_id is null
        and attachment.storage_provider = 'cloudflare_images'
        and (
          (
            attachment.status in ('pending_upload', 'pending_scan')
            and attachment.created_at < now() - interval '1 hour'
          )
          or (
            attachment.status in ('ready', 'rejected')
            and attachment.created_at < now() - interval '1 day'
          )
          or (
            attachment.status = 'deleted'
            and coalesce(attachment.deleted_at, attachment.created_at) < now() - interval '5 minutes'
          )
      )
      order by attachment.created_at asc
      limit target_batch_size
      for update skip locked
    ), claimed_rows as (
      update public.community_direct_message_attachments as attachment
      set status = 'deleted',
        deleted_at = now()
      from candidate_rows
      where attachment.id = candidate_rows.id
      returning attachment.id, attachment.provider_asset_id
    )
    select claimed_rows.id, claimed_rows.provider_asset_id
    from claimed_rows;
  end if;
end;
$$;

revoke all on function public.claim_expired_community_media_attachments(text, integer) from public, anon, authenticated;
grant execute on function public.claim_expired_community_media_attachments(text, integer) to service_role;

create or replace function public.finalize_community_media_cleanup(
  target_media_type text,
  target_attachment_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  deleted_id uuid;
begin
  if target_media_type not in ('group', 'direct') or target_attachment_id is null then
    return false;
  end if;

  if target_media_type = 'group' then
    delete from public.community_group_chat_attachments
    where id = target_attachment_id
      and message_id is null
      and storage_provider = 'cloudflare_images'
      and status = 'deleted'
    returning id into deleted_id;
  else
    delete from public.community_direct_message_attachments
    where id = target_attachment_id
      and message_id is null
      and storage_provider = 'cloudflare_images'
      and status = 'deleted'
    returning id into deleted_id;
  end if;

  return deleted_id is not null;
end;
$$;

revoke all on function public.finalize_community_media_cleanup(text, uuid) from public, anon, authenticated;
grant execute on function public.finalize_community_media_cleanup(text, uuid) to service_role;

comment on function public.claim_expired_community_media_attachments(text, integer) is
  'Atomically claims only unattached Cloudflare media eligible for cleanup; pending-review and attached media are retained.';
comment on function public.finalize_community_media_cleanup(text, uuid) is
  'Idempotently removes metadata after provider deletion has succeeded or returned 404.';
