-- A member who has explicitly followed the sender has opted into direct
-- messages from that sender. This avoids a redundant request prompt while
-- preserving the request boundary for every other relationship.

create or replace function public.create_direct_conversation(target_user_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  first_participant uuid;
  second_participant uuid;
  existing_conversation public.community_conversations;
  new_conversation_id uuid;
  initial_status text;
begin
  if caller_id is null or target_user_id is null or caller_id = target_user_id then
    raise exception 'invalid conversation target';
  end if;
  if not public.can_view_community_user(target_user_id)
     or not exists (select 1 from public.community_profiles where user_id = target_user_id) then
    raise exception 'conversation unavailable';
  end if;

  -- The target member following the caller is the consent signal. Merely
  -- following somebody does not grant the caller permission to bypass their
  -- message-request inbox.
  initial_status := case when exists (
    select 1
    from public.community_follows
    where follower_id = target_user_id
      and following_id = caller_id
  ) then 'active' else 'pending' end;

  first_participant := least(caller_id, target_user_id);
  second_participant := greatest(caller_id, target_user_id);
  select * into existing_conversation
  from public.community_conversations
  where participant_one_id = first_participant
    and participant_two_id = second_participant
  for update;

  if found then
    if existing_conversation.status = 'declined' then
      raise exception 'message request unavailable';
    end if;

    -- A request sent before the follow remains safe until the recipient
    -- explicitly follows the requester; at that point it becomes active.
    if existing_conversation.status = 'pending' and initial_status = 'active' then
      update public.community_conversations
      set status = 'active', updated_at = now()
      where id = existing_conversation.id;
      update public.community_conversation_members
      set status = 'active', updated_at = now()
      where conversation_id = existing_conversation.id;
      -- The prior request notification must not remain actionable after the
      -- recipient's follow has promoted the conversation to direct messaging.
      delete from public.community_notifications
      where conversation_id = existing_conversation.id
        and type = 'message_request';
    end if;
    return existing_conversation.id;
  end if;

  insert into public.community_conversations (
    participant_one_id,
    participant_two_id,
    requested_by_id,
    status
  ) values (
    first_participant,
    second_participant,
    caller_id,
    initial_status
  ) returning id into new_conversation_id;

  insert into public.community_conversation_members (conversation_id, user_id, status)
  values
    (new_conversation_id, caller_id, initial_status),
    (new_conversation_id, target_user_id, initial_status);
  return new_conversation_id;
end;
$$;

create or replace function public.create_community_message_request_notification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  recipient uuid;
begin
  if new.status <> 'pending' then
    return new;
  end if;

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
