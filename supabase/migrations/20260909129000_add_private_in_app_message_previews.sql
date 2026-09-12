-- A notification preview is intentionally stored only for the recipient's
-- authorized in-app UI. It is never copied into the APNs payload.
-- Keep it bounded and normalized so a single notification cannot become a
-- storage or layout abuse vector.

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
  preview text;
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
  preview := left(
    regexp_replace(btrim(new.body), '[[:space:]]+', ' ', 'g'),
    280
  );

  -- Coalesce a burst into one recipient event per conversation per minute.
  -- The recipient-only RLS policy already protects this row. The preview is
  -- deliberately not read by the worker and is never sent to APNs.
  insert into public.community_notifications (
    recipient_id, actor_id, type, conversation_id, body, event_key
  ) values (
    recipient,
    new.sender_id,
    'direct_message',
    new.conversation_id,
    nullif(preview, ''),
    'direct-message:' || new.conversation_id::text || ':' || recipient::text || ':' || minute_key
  ) on conflict (recipient_id, event_key) where event_key is not null do nothing;
  return new;
end;
$$;

revoke all on function public.create_community_direct_message_notification() from public;
