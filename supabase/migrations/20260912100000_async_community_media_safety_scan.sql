-- Move provider download and Google Vision work out of the upload-completion
-- request. The attachment row is the durable, idempotent scan outbox; the
-- Cloudflare Queue message only carries its opaque type and attachment ID.

alter table public.community_group_chat_attachments
  drop constraint if exists community_group_chat_attachments_status_check;

alter table public.community_group_chat_attachments
  add constraint community_group_chat_attachments_status_check
    check (status in ('pending_upload', 'pending_scan', 'pending_review', 'ready', 'rejected', 'deleted')),
  add column if not exists scan_attempts integer not null default 0
    check (scan_attempts between 0 and 5),
  add column if not exists scan_started_at timestamptz,
  add column if not exists scan_last_error text;

alter table public.community_direct_message_attachments
  drop constraint if exists community_direct_message_attachments_status_check;

alter table public.community_direct_message_attachments
  add constraint community_direct_message_attachments_status_check
    check (status in ('pending_upload', 'pending_scan', 'pending_review', 'ready', 'rejected', 'deleted')),
  add column if not exists scan_attempts integer not null default 0
    check (scan_attempts between 0 and 5),
  add column if not exists scan_started_at timestamptz,
  add column if not exists scan_last_error text;

create index if not exists community_group_chat_attachments_scan_queue_idx
  on public.community_group_chat_attachments (created_at)
  where status = 'pending_scan';

create index if not exists community_direct_message_attachments_scan_queue_idx
  on public.community_direct_message_attachments (created_at)
  where status = 'pending_scan';

comment on column public.community_group_chat_attachments.scan_attempts is
  'Bounded background safety-scan attempts; the fifth failure is quarantined for review.';
comment on column public.community_group_chat_attachments.scan_last_error is
  'Normalized operational scan failure only; never store provider payloads or image content.';
comment on column public.community_direct_message_attachments.scan_attempts is
  'Bounded background safety-scan attempts; the fifth failure is quarantined for review.';
comment on column public.community_direct_message_attachments.scan_last_error is
  'Normalized operational scan failure only; never store provider payloads or image content.';

create or replace function public.queue_community_media_scan(
  target_media_type text,
  target_attachment_id uuid,
  target_uploader_id uuid
)
returns table (
  provider_asset_id text,
  queue_state text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  attachment_asset_id text;
  attachment_status text;
  attachment_message_id uuid;
  attachment_group_id uuid;
  attachment_conversation_id uuid;
  participant_one_id uuid;
  participant_two_id uuid;
begin
  if target_media_type not in ('group', 'direct')
     or target_attachment_id is null
     or target_uploader_id is null
     or not exists (select 1 from auth.users where id = target_uploader_id) then
    return;
  end if;

  if target_media_type = 'group' then
    select attachment.provider_asset_id, attachment.status, attachment.message_id, attachment.group_id
    into attachment_asset_id, attachment_status, attachment_message_id, attachment_group_id
    from public.community_group_chat_attachments as attachment
    where attachment.id = target_attachment_id
      and attachment.uploader_id = target_uploader_id
      and attachment.storage_provider = 'cloudflare_images';

    if not found
       or not exists (
         select 1
         from public.community_group_memberships as membership
         where membership.group_id = attachment_group_id
           and membership.user_id = target_uploader_id
       )
       or exists (
         select 1
         from public.community_group_bans as ban
         where ban.group_id = attachment_group_id
           and ban.user_id = target_uploader_id
       ) then
      return;
    end if;
  else
    select attachment.provider_asset_id,
      attachment.status,
      attachment.message_id,
      attachment.conversation_id,
      conversation.participant_one_id,
      conversation.participant_two_id
    into attachment_asset_id, attachment_status, attachment_message_id,
      attachment_conversation_id, participant_one_id, participant_two_id
    from public.community_direct_message_attachments as attachment
    join public.community_conversations as conversation
      on conversation.id = attachment.conversation_id
    where attachment.id = target_attachment_id
      and attachment.uploader_id = target_uploader_id
      and attachment.storage_provider = 'cloudflare_images'
      and conversation.status = 'active'
      and (
        conversation.participant_one_id = target_uploader_id
        or conversation.participant_two_id = target_uploader_id
      );

    if not found
       or not exists (
         select 1
         from public.community_conversation_members as member
         where member.conversation_id = attachment_conversation_id
           and member.user_id = target_uploader_id
           and member.status = 'active'
       )
       or not exists (
         select 1
         from public.community_conversation_members as member
         where member.conversation_id = attachment_conversation_id
           and member.user_id = case
             when participant_one_id = target_uploader_id then participant_two_id
             else participant_one_id
           end
           and member.status = 'active'
       )
       or exists (
         select 1
         from public.user_blocks as block
         where (block.blocker_id = target_uploader_id and block.blocked_user_id = case
           when participant_one_id = target_uploader_id then participant_two_id
           else participant_one_id
         end)
            or (block.blocked_user_id = target_uploader_id and block.blocker_id = case
              when participant_one_id = target_uploader_id then participant_two_id
              else participant_one_id
            end)
       ) then
      return;
    end if;
  end if;

  if attachment_asset_id is null or attachment_message_id is not null then
    return;
  end if;

  if attachment_status = 'pending_upload' then
    if target_media_type = 'group' then
      update public.community_group_chat_attachments
      set status = 'pending_scan',
        scan_status = 'not_started',
        scan_attempts = 0,
        scan_started_at = null,
        scan_last_error = null,
        scanned_at = null,
        reviewed_at = null
      where id = target_attachment_id
        and status = 'pending_upload'
        and message_id is null;
    else
      update public.community_direct_message_attachments
      set status = 'pending_scan',
        scan_status = 'not_started',
        scan_attempts = 0,
        scan_started_at = null,
        scan_last_error = null,
        scanned_at = null,
        reviewed_at = null
      where id = target_attachment_id
        and status = 'pending_upload'
        and message_id is null;
    end if;

    if found then
      return query select attachment_asset_id, 'queued'::text;
      return;
    end if;
  end if;

  if attachment_status = 'pending_scan' then
    return query select attachment_asset_id, 'already_queued'::text;
    return;
  end if;

  if attachment_status in ('pending_review', 'ready', 'rejected', 'deleted') then
    return query select attachment_asset_id, 'already_processed'::text;
  end if;
end;
$$;

revoke all on function public.queue_community_media_scan(text, uuid, uuid) from public, anon, authenticated;
grant execute on function public.queue_community_media_scan(text, uuid, uuid) to service_role;

create or replace function public.get_community_media_scan_status(
  target_media_type text,
  target_attachment_id uuid,
  target_viewer_id uuid
)
returns table (outcome text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  attachment_status text;
  attachment_scan_status text;
  attachment_group_id uuid;
  attachment_conversation_id uuid;
  participant_one_id uuid;
  participant_two_id uuid;
begin
  if target_media_type not in ('group', 'direct')
     or target_attachment_id is null
     or target_viewer_id is null
     or not exists (select 1 from auth.users where id = target_viewer_id) then
    return;
  end if;

  if target_media_type = 'group' then
    select attachment.status, attachment.scan_status, attachment.group_id
    into attachment_status, attachment_scan_status, attachment_group_id
    from public.community_group_chat_attachments as attachment
    where attachment.id = target_attachment_id
      and attachment.uploader_id = target_viewer_id
      and attachment.storage_provider = 'cloudflare_images';

    if not found
       or not exists (
         select 1
         from public.community_group_memberships as membership
         where membership.group_id = attachment_group_id
           and membership.user_id = target_viewer_id
       )
       or exists (
         select 1
         from public.community_group_bans as ban
         where ban.group_id = attachment_group_id
           and ban.user_id = target_viewer_id
       ) then
      return;
    end if;
  else
    select attachment.status,
      attachment.scan_status,
      attachment.conversation_id,
      conversation.participant_one_id,
      conversation.participant_two_id
    into attachment_status, attachment_scan_status, attachment_conversation_id,
      participant_one_id, participant_two_id
    from public.community_direct_message_attachments as attachment
    join public.community_conversations as conversation
      on conversation.id = attachment.conversation_id
    where attachment.id = target_attachment_id
      and attachment.uploader_id = target_viewer_id
      and attachment.storage_provider = 'cloudflare_images'
      and conversation.status = 'active'
      and (
        conversation.participant_one_id = target_viewer_id
        or conversation.participant_two_id = target_viewer_id
      );

    if not found
       or not exists (
         select 1
         from public.community_conversation_members as member
         where member.conversation_id = attachment_conversation_id
           and member.user_id = target_viewer_id
           and member.status = 'active'
       )
       or not exists (
         select 1
         from public.community_conversation_members as member
         where member.conversation_id = attachment_conversation_id
           and member.user_id = case
             when participant_one_id = target_viewer_id then participant_two_id
             else participant_one_id
           end
           and member.status = 'active'
       )
       or exists (
         select 1
         from public.user_blocks as block
         where (block.blocker_id = target_viewer_id and block.blocked_user_id = case
           when participant_one_id = target_viewer_id then participant_two_id
           else participant_one_id
         end)
            or (block.blocked_user_id = target_viewer_id and block.blocker_id = case
              when participant_one_id = target_viewer_id then participant_two_id
              else participant_one_id
            end)
       ) then
      return;
    end if;
  end if;

  if attachment_status in ('pending_upload', 'pending_scan') then
    return query select 'pending_scan'::text;
  elsif attachment_status = 'ready' and attachment_scan_status = 'passed' then
    return query select 'passed'::text;
  elsif attachment_status = 'rejected' or attachment_scan_status = 'rejected' then
    return query select 'rejected'::text;
  elsif attachment_status = 'pending_review' and attachment_scan_status = 'needs_review' then
    return query select 'needs_review'::text;
  elsif attachment_status = 'pending_review' and attachment_scan_status = 'unavailable' then
    return query select 'unavailable'::text;
  end if;
end;
$$;

revoke all on function public.get_community_media_scan_status(text, uuid, uuid) from public, anon, authenticated;
grant execute on function public.get_community_media_scan_status(text, uuid, uuid) to service_role;

create or replace function public.claim_community_media_scan(
  target_media_type text,
  target_attachment_id uuid
)
returns table (
  provider_asset_id text,
  attempt_count integer,
  terminal boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  claimed_asset_id text;
  claimed_attempt_count integer;
  current_asset_id text;
  current_attempt_count integer;
  current_status text;
  current_started_at timestamptz;
begin
  if target_media_type not in ('group', 'direct') or target_attachment_id is null then
    return;
  end if;

  if target_media_type = 'group' then
    update public.community_group_chat_attachments as attachment
    set scan_attempts = attachment.scan_attempts + 1,
      scan_started_at = now(),
      scan_last_error = null
    where attachment.id = target_attachment_id
      and attachment.status = 'pending_scan'
      and attachment.provider_asset_id is not null
      and attachment.scan_attempts < 5
      and (attachment.scan_started_at is null or attachment.scan_started_at < now() - interval '2 minutes')
    returning attachment.provider_asset_id, attachment.scan_attempts
    into claimed_asset_id, claimed_attempt_count;
  else
    update public.community_direct_message_attachments as attachment
    set scan_attempts = attachment.scan_attempts + 1,
      scan_started_at = now(),
      scan_last_error = null
    where attachment.id = target_attachment_id
      and attachment.status = 'pending_scan'
      and attachment.provider_asset_id is not null
      and attachment.scan_attempts < 5
      and (attachment.scan_started_at is null or attachment.scan_started_at < now() - interval '2 minutes')
    returning attachment.provider_asset_id, attachment.scan_attempts
    into claimed_asset_id, claimed_attempt_count;
  end if;

  if found then
    return query select claimed_asset_id, claimed_attempt_count, false;
    return;
  end if;

  if target_media_type = 'group' then
    select attachment.provider_asset_id, attachment.scan_attempts, attachment.status, attachment.scan_started_at
    into current_asset_id, current_attempt_count, current_status, current_started_at
    from public.community_group_chat_attachments as attachment
    where attachment.id = target_attachment_id;
  else
    select attachment.provider_asset_id, attachment.scan_attempts, attachment.status, attachment.scan_started_at
    into current_asset_id, current_attempt_count, current_status, current_started_at
    from public.community_direct_message_attachments as attachment
    where attachment.id = target_attachment_id;
  end if;

  if current_status = 'pending_scan'
     and current_asset_id is not null
     and current_attempt_count >= 5
     and (current_started_at is null or current_started_at < now() - interval '2 minutes') then
    return query select current_asset_id, current_attempt_count, true;
  end if;
end;
$$;

revoke all on function public.claim_community_media_scan(text, uuid) from public, anon, authenticated;
grant execute on function public.claim_community_media_scan(text, uuid) to service_role;

create or replace function public.finish_community_media_scan(
  target_media_type text,
  target_attachment_id uuid,
  target_outcome text,
  target_summary text,
  target_error text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_summary text := left(btrim(coalesce(target_summary, '')), 200);
  normalized_error text := left(btrim(coalesce(target_error, '')), 200);
  updated_id uuid;
begin
  if target_media_type not in ('group', 'direct')
     or target_attachment_id is null
     or target_outcome not in ('retry', 'passed', 'needs_review', 'rejected', 'unavailable') then
    return false;
  end if;

  if target_outcome = 'retry' then
    if target_media_type = 'group' then
      update public.community_group_chat_attachments
      set scan_status = 'not_started',
        scan_started_at = null,
        scan_last_error = nullif(normalized_error, '')
      where id = target_attachment_id
        and status = 'pending_scan'
        and scan_started_at is not null
      returning id into updated_id;
    else
      update public.community_direct_message_attachments
      set scan_status = 'not_started',
        scan_started_at = null,
        scan_last_error = nullif(normalized_error, '')
      where id = target_attachment_id
        and status = 'pending_scan'
        and scan_started_at is not null
      returning id into updated_id;
    end if;
    return updated_id is not null;
  end if;

  if target_media_type = 'group' then
    update public.community_group_chat_attachments
    set status = case target_outcome
        when 'passed' then 'ready'
        when 'rejected' then 'rejected'
        else 'pending_review'
      end,
      scan_provider = 'google_vision_safe_search',
      scan_status = target_outcome,
      scan_summary = nullif(normalized_summary, ''),
      scanned_at = now(),
      reviewed_at = case when target_outcome = 'passed' then now() else null end,
      scan_started_at = null,
      scan_last_error = nullif(normalized_error, '')
    where id = target_attachment_id
      and status = 'pending_scan'
      and scan_started_at is not null
    returning id into updated_id;
  else
    update public.community_direct_message_attachments
    set status = case target_outcome
        when 'passed' then 'ready'
        when 'rejected' then 'rejected'
        else 'pending_review'
      end,
      scan_provider = 'google_vision_safe_search',
      scan_status = target_outcome,
      scan_summary = nullif(normalized_summary, ''),
      scanned_at = now(),
      reviewed_at = case when target_outcome = 'passed' then now() else null end,
      scan_started_at = null,
      scan_last_error = nullif(normalized_error, '')
    where id = target_attachment_id
      and status = 'pending_scan'
      and scan_started_at is not null
    returning id into updated_id;
  end if;

  return updated_id is not null;
end;
$$;

revoke all on function public.finish_community_media_scan(text, uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.finish_community_media_scan(text, uuid, text, text, text) to service_role;

comment on function public.queue_community_media_scan(text, uuid, uuid) is
  'Atomically moves an authorized, uploaded private image into the background safety-scan outbox.';
comment on function public.get_community_media_scan_status(text, uuid, uuid) is
  'Returns a privacy-scoped normalized media scan outcome for the uploading member.';
comment on function public.claim_community_media_scan(text, uuid) is
  'Claims one private media safety scan with a bounded retry count and crash lease.';
comment on function public.finish_community_media_scan(text, uuid, text, text, text) is
  'Idempotently records a normalized background media-scan result without storing provider payloads.';
