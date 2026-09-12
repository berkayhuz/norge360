-- Direct-message media phase 1: one private, safety-scanned image per active
-- direct message. Clients never read attachment rows or object paths directly.
-- Video and disappearing media intentionally require later retention and abuse
-- review work, so they are not accepted by this schema.

create table if not exists public.community_direct_message_attachments (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.community_conversations(id) on delete cascade,
  message_id uuid references public.community_messages(id) on delete cascade,
  uploader_id uuid not null references auth.users(id) on delete cascade,
  storage_reference text not null unique check (char_length(btrim(storage_reference)) between 1 and 500),
  mime_type text not null check (mime_type in ('image/jpeg', 'image/png', 'image/heic', 'image/webp')),
  byte_size integer not null check (byte_size between 1 and 10485760),
  storage_provider text not null default 'cloudflare_images'
    check (storage_provider = 'cloudflare_images'),
  provider_asset_id text unique,
  status text not null default 'pending_upload'
    check (status in ('pending_upload', 'pending_review', 'ready', 'rejected', 'deleted')),
  scan_provider text,
  scan_status text not null default 'not_started'
    check (scan_status in ('not_started', 'passed', 'needs_review', 'rejected', 'unavailable')),
  scan_summary text,
  scanned_at timestamptz,
  reviewed_at timestamptz,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  check (split_part(storage_reference, '/', 1) = conversation_id::text),
  check ((status = 'ready') = (reviewed_at is not null))
);

create unique index if not exists community_direct_message_one_attachment_per_message_idx
  on public.community_direct_message_attachments (message_id)
  where message_id is not null;
create index if not exists community_direct_message_attachments_cleanup_idx
  on public.community_direct_message_attachments (status, created_at)
  where status in ('pending_upload', 'pending_review', 'rejected', 'deleted');

alter table public.community_direct_message_attachments enable row level security;
revoke all on public.community_direct_message_attachments from anon, authenticated;

-- Text-only messages retain their existing validation. Image messages may have
-- an empty caption, but the attachment RPC below requires a ready image.
alter table public.community_messages
  drop constraint if exists community_messages_body_check;
alter table public.community_messages
  add constraint community_messages_body_check
  check (char_length(trim(body)) <= 2000);

create or replace function public.list_community_conversation_messages(
  target_conversation_id uuid
)
returns table (
  id uuid,
  conversation_id uuid,
  sender_id uuid,
  body text,
  created_at timestamptz,
  deleted_at timestamptz,
  attachment_id uuid,
  attachment_mime_type text
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.can_access_community_conversation(target_conversation_id)
     or not exists (
       select 1
       from public.community_conversations conversation
       join public.community_conversation_members member on member.conversation_id = conversation.id
       where conversation.id = target_conversation_id
         and conversation.status = 'active'
         and member.user_id = (select auth.uid())
         and member.status = 'active'
     ) then
    raise exception 'conversation unavailable';
  end if;

  return query
  select message.id, message.conversation_id, message.sender_id, message.body,
    message.created_at, message.deleted_at, attachment.id, attachment.mime_type
  from public.community_messages message
  left join public.community_direct_message_attachments attachment
    on attachment.message_id = message.id
    and attachment.status = 'ready'
    and attachment.scan_status = 'passed'
  where message.conversation_id = target_conversation_id
    and message.deleted_at is null
    and not exists (
      select 1 from public.community_message_member_hides hidden
      where hidden.message_id = message.id and hidden.user_id = (select auth.uid())
    )
  order by message.created_at asc
  limit 200;
end;
$$;

create or replace function public.send_community_message_with_attachment(
  target_conversation_id uuid,
  message_body text,
  target_attachment_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  normalized_body text := btrim(regexp_replace(coalesce(message_body, ''), '[[:space:]]+', ' ', 'g'));
  conversation public.community_conversations;
  attachment public.community_direct_message_attachments;
  other_participant uuid;
  new_message_id uuid;
begin
  if caller_id is null or char_length(normalized_body) > 2000 then
    raise exception 'invalid message';
  end if;

  select * into conversation
  from public.community_conversations
  where id = target_conversation_id
  for update;
  if not found or conversation.status <> 'active'
     or (caller_id <> conversation.participant_one_id and caller_id <> conversation.participant_two_id)
     or not exists (
       select 1 from public.community_conversation_members
       where conversation_id = target_conversation_id and user_id = caller_id and status = 'active'
     ) then
    raise exception 'conversation unavailable';
  end if;

  other_participant := case
    when conversation.participant_one_id = caller_id then conversation.participant_two_id
    else conversation.participant_one_id
  end;
  if not public.can_view_community_user(other_participant) then
    raise exception 'conversation unavailable';
  end if;

  select * into attachment
  from public.community_direct_message_attachments
  where id = target_attachment_id
  for update;
  if attachment.id is null
     or attachment.conversation_id <> target_conversation_id
     or attachment.uploader_id <> caller_id
     or attachment.message_id is not null
     or attachment.status <> 'ready'
     or attachment.scan_status <> 'passed' then
    raise exception 'message attachment unavailable';
  end if;

  if (select count(*) from public.community_messages
      where sender_id = caller_id and created_at > now() - interval '1 minute') >= 20 then
    raise exception 'message rate limit reached';
  end if;

  insert into public.community_messages (conversation_id, sender_id, body)
  values (target_conversation_id, caller_id, normalized_body)
  returning id into new_message_id;

  update public.community_direct_message_attachments
  set message_id = new_message_id
  where id = attachment.id;
  update public.community_conversation_members
  set last_read_at = now(), updated_at = now()
  where conversation_id = target_conversation_id and user_id = caller_id;
  update public.community_conversations set updated_at = now() where id = target_conversation_id;
  return new_message_id;
end;
$$;

revoke all on function public.send_community_message_with_attachment(uuid, text, uuid) from public;
revoke all on function public.list_community_conversation_messages(uuid) from public;
grant execute on function public.send_community_message_with_attachment(uuid, text, uuid) to authenticated;
grant execute on function public.list_community_conversation_messages(uuid) to authenticated;

comment on table public.community_direct_message_attachments is
  'Private direct-message image staging metadata. Provider IDs and opaque references are never delivered to clients.';
comment on column public.community_direct_message_attachments.scan_summary is
  'Normalized automated safety result only; never store image bytes or provider response payloads.';
