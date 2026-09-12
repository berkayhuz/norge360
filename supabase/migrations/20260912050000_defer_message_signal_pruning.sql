-- Expired transport signals are maintenance data. Never prune them from a
-- conversation request or message insert transaction.
drop function if exists public.prune_community_message_signals();

create function public.prune_community_message_signals(batch_size integer default 500)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  removed bigint;
begin
  if batch_size is null or batch_size < 1 or batch_size > 5000 then
    raise exception 'invalid message signal prune batch size';
  end if;

  with expired_signals as (
    select signal.id
    from public.community_message_signals as signal
    where signal.expires_at <= now()
    order by signal.expires_at
    limit batch_size
    for update skip locked
  )
  delete from public.community_message_signals as signal
  using expired_signals
  where signal.id = expired_signals.id;

  get diagnostics removed = row_count;
  return removed;
end;
$$;

revoke all on function public.prune_community_message_signals(integer) from public;
grant execute on function public.prune_community_message_signals(integer) to service_role;

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

  insert into public.community_message_signals (recipient_id, conversation_id, type, event_key)
  values (recipient, new.id, 'message_request', 'message-request:' || new.id::text)
  on conflict (recipient_id, event_key) do nothing;
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

  -- Emit a signal for each new message so the inbox can reorder immediately.
  -- The Worker controls device delivery independently of activity storage.
  insert into public.community_message_signals (recipient_id, conversation_id, type, event_key)
  values (recipient, new.conversation_id, 'direct_message', 'direct-message:' || new.id::text)
  on conflict (recipient_id, event_key) do nothing;
  return new;
end;
$$;

revoke all on function public.create_community_message_request_notification() from public;
revoke all on function public.create_community_direct_message_notification() from public;

