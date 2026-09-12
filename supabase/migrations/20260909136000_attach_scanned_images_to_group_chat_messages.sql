-- A group-chat message may carry one automatically safety-approved image.
-- Clients cannot attach a staged, rejected, or review-pending asset.

create unique index if not exists community_group_chat_one_attachment_per_message_idx
  on public.community_group_chat_attachments (message_id)
  where message_id is not null;

drop function if exists public.list_community_group_chat_messages(uuid);

create function public.list_community_group_chat_messages(target_group_id uuid)
returns table (
  id uuid,
  sender_id uuid,
  display_name text,
  username text,
  body text,
  created_at timestamptz,
  attachment_id uuid,
  attachment_mime_type text
)
language plpgsql security definer set search_path = '' as $$
begin
  if not public.can_access_community_group_chat(target_group_id) then
    raise exception 'group chat unavailable';
  end if;

  return query
  select message.id, message.sender_id, profile.display_name, profile.username,
    message.body, message.created_at, attachment.id, attachment.mime_type
  from public.community_group_chat_messages message
  join public.community_profiles profile on profile.user_id = message.sender_id
  left join public.community_group_chat_attachments attachment
    on attachment.message_id = message.id
    and attachment.status = 'ready'
    and attachment.scan_status = 'passed'
  where message.group_id = target_group_id
    and message.deleted_at is null
    and message.moderation_state = 'active'
    and profile.moderation_state = 'active'
    and public.can_view_community_user(message.sender_id)
    and not exists (
      select 1 from public.community_group_chat_message_member_hides hidden
      where hidden.message_id = message.id and hidden.user_id = (select auth.uid())
    )
  order by message.created_at asc
  limit 200;
end;
$$;

create or replace function public.send_community_group_chat_message_with_attachment(
  target_group_id uuid,
  message_body text,
  target_attachment_id uuid
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  caller_id uuid := (select auth.uid());
  normalized_body text := btrim(regexp_replace(coalesce(message_body, ''), '[[:space:]]+', ' ', 'g'));
  attachment_row public.community_group_chat_attachments;
  new_message_id uuid;
begin
  if caller_id is null
     or char_length(normalized_body) > 2000
     or not public.can_access_community_group_chat(target_group_id)
     or public.is_community_member_posting_restricted(caller_id)
     or not exists (select 1 from public.community_profiles where user_id = caller_id and moderation_state = 'active') then
    raise exception 'group chat unavailable';
  end if;

  select * into attachment_row
  from public.community_group_chat_attachments
  where id = target_attachment_id
  for update;
  if attachment_row.id is null
     or attachment_row.group_id <> target_group_id
     or attachment_row.uploader_id <> caller_id
     or attachment_row.message_id is not null
     or attachment_row.status <> 'ready'
     or attachment_row.scan_status <> 'passed'
     or (attachment_row.expires_at is not null and attachment_row.expires_at <= now()) then
    raise exception 'group chat attachment unavailable';
  end if;

  if (select count(*) from public.community_group_chat_messages
      where sender_id = caller_id and created_at > now() - interval '1 minute') >= 20 then
    raise exception 'group chat rate limit reached';
  end if;

  insert into public.community_group_chat_messages (group_id, sender_id, body)
  values (target_group_id, caller_id, normalized_body)
  returning id into new_message_id;

  update public.community_group_chat_attachments
  set message_id = new_message_id
  where id = attachment_row.id;
  return new_message_id;
end;
$$;

revoke all on function public.list_community_group_chat_messages(uuid) from public;
revoke all on function public.send_community_group_chat_message_with_attachment(uuid, text, uuid) from public;
grant execute on function public.list_community_group_chat_messages(uuid) to authenticated;
grant execute on function public.send_community_group_chat_message_with_attachment(uuid, text, uuid) to authenticated;
