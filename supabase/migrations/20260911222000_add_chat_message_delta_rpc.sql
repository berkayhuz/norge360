-- Realtime is intentionally only a wake-up signal. These RPCs re-apply the
-- existing server-side membership, block, hide and moderation checks before a
-- message delta reaches the untrusted iOS client.

create or replace function public.list_community_conversation_messages_after(
  target_conversation_id uuid,
  after_created_at timestamptz,
  after_message_id uuid
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
  if after_created_at is null or after_message_id is null
     or not public.can_access_community_conversation(target_conversation_id)
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
    and (message.created_at, message.id) > (after_created_at, after_message_id)
  order by message.created_at asc, message.id asc
  limit 100;
end;
$$;

create or replace function public.list_community_group_chat_messages_after(
  target_group_id uuid,
  after_created_at timestamptz,
  after_message_id uuid
)
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
language plpgsql
security definer
set search_path = ''
as $$
begin
  if after_created_at is null or after_message_id is null
     or not public.can_access_community_group_chat(target_group_id) then
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
    and (message.created_at, message.id) > (after_created_at, after_message_id)
  order by message.created_at asc, message.id asc
  limit 100;
end;
$$;

revoke all on function public.list_community_conversation_messages_after(uuid, timestamptz, uuid) from public;
revoke all on function public.list_community_group_chat_messages_after(uuid, timestamptz, uuid) from public;
grant execute on function public.list_community_conversation_messages_after(uuid, timestamptz, uuid) to authenticated;
grant execute on function public.list_community_group_chat_messages_after(uuid, timestamptz, uuid) to authenticated;
