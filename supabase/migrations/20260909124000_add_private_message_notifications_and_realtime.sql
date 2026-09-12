-- Privacy-safe in-app delivery signals for direct conversations. Notification
-- rows never include message text, attachment metadata, or contact details.

alter table public.community_notifications
  drop constraint if exists community_notifications_type_check;
alter table public.community_notifications
  add constraint community_notifications_type_check
  check (type in (
    'follow', 'post_like', 'post_comment', 'group_join_approved', 'group_join_rejected',
    'moderation_content_removed', 'moderation_content_restored',
    'moderation_member_restricted', 'moderation_member_restriction_revoked',
    'message_request', 'direct_message'
  ));

alter table public.community_notifications
  add column if not exists conversation_id uuid
    references public.community_conversations(id) on delete cascade;

create index if not exists community_notifications_recipient_conversation_created_idx
  on public.community_notifications (recipient_id, conversation_id, created_at desc)
  where conversation_id is not null;

-- Private-message notification rows disappear when the recipient can no longer
-- access the conversation (for example after either participant blocks).
drop policy if exists "Users can view their visible notifications" on public.community_notifications;
create policy "Users can view their visible notifications"
on public.community_notifications for select to authenticated
using (
  recipient_id = (select auth.uid())
  and (
    type in (
      'group_join_approved', 'group_join_rejected',
      'moderation_content_removed', 'moderation_content_restored',
      'moderation_member_restricted', 'moderation_member_restriction_revoked'
    )
    or (
      type in ('message_request', 'direct_message')
      and conversation_id is not null
      and public.can_access_community_conversation(conversation_id)
      and public.can_view_community_user(actor_id)
    )
    or (
      type not in ('message_request', 'direct_message')
      and public.can_view_community_user(actor_id)
    )
  )
);

create or replace function public.create_community_message_request_notification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  recipient uuid;
begin
  recipient := case
    when new.participant_one_id = new.requested_by_id then new.participant_two_id
    else new.participant_one_id
  end;

  insert into public.community_notifications (
    recipient_id, actor_id, type, conversation_id, event_key
  ) values (
    recipient,
    new.requested_by_id,
    'message_request',
    new.id,
    'message-request:' || new.id::text
  ) on conflict (recipient_id, event_key) where event_key is not null do nothing;
  return new;
end;
$$;

create or replace function public.create_community_direct_message_notification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  conversation public.community_conversations;
  recipient uuid;
  minute_key text;
begin
  select * into conversation
  from public.community_conversations
  where id = new.conversation_id;

  if conversation.id is null or conversation.status <> 'active' then
    return new;
  end if;

  recipient := case
    when conversation.participant_one_id = new.sender_id then conversation.participant_two_id
    else conversation.participant_one_id
  end;
  minute_key := to_char(date_trunc('minute', new.created_at), 'YYYYMMDDHH24MI');

  -- Coalesce a burst into one recipient event per conversation per minute.
  insert into public.community_notifications (
    recipient_id, actor_id, type, conversation_id, event_key
  ) values (
    recipient,
    new.sender_id,
    'direct_message',
    new.conversation_id,
    'direct-message:' || new.conversation_id::text || ':' || recipient::text || ':' || minute_key
  ) on conflict (recipient_id, event_key) where event_key is not null do nothing;
  return new;
end;
$$;

drop trigger if exists community_message_request_notification_after_insert on public.community_conversations;
create trigger community_message_request_notification_after_insert
after insert on public.community_conversations
for each row execute procedure public.create_community_message_request_notification();

drop trigger if exists community_direct_message_notification_after_insert on public.community_messages;
create trigger community_direct_message_notification_after_insert
after insert on public.community_messages
for each row execute procedure public.create_community_direct_message_notification();

do $$
begin
  alter publication supabase_realtime add table public.community_messages;
exception
  when duplicate_object then null;
end $$;

revoke all on function public.create_community_message_request_notification() from public;
revoke all on function public.create_community_direct_message_notification() from public;
