-- Run against a disposable migrated database as its owner. Everything rolls back.
begin;

do $$
declare
  request_definition text;
  message_definition text;
  prune_definition text;
begin
  select pg_get_functiondef(
    'public.create_community_message_request_notification()'::regprocedure
  ) into request_definition;
  select pg_get_functiondef(
    'public.create_community_direct_message_notification()'::regprocedure
  ) into message_definition;
  select pg_get_functiondef(
    'public.prune_community_message_signals(integer)'::regprocedure
  ) into prune_definition;

  if position('prune_community_message_signals' in lower(request_definition)) > 0
     or position('prune_community_message_signals' in lower(message_definition)) > 0 then
    raise exception 'message signal pruning remains on the write path';
  end if;

  if position('limit batch_size' in lower(prune_definition)) = 0
     or position('skip locked' in lower(prune_definition)) = 0 then
    raise exception 'message signal pruning is not bounded and lock-aware';
  end if;
end $$;

insert into auth.users(id) values
  ('82000000-0000-4000-8000-000000000001'),
  ('82000000-0000-4000-8000-000000000002');

insert into public.community_profiles(user_id, display_name, username, preferred_locale, norway_status)
values
  ('82000000-0000-4000-8000-000000000001', 'Signal Sender', 'signal_sender', 'en', 'resident'),
  ('82000000-0000-4000-8000-000000000002', 'Signal Recipient', 'signal_recipient', 'en', 'resident');

insert into public.community_conversations(
  id, participant_one_id, participant_two_id, requested_by_id, status
)
values (
  '82000000-0000-4000-8000-000000000011',
  '82000000-0000-4000-8000-000000000001',
  '82000000-0000-4000-8000-000000000002',
  '82000000-0000-4000-8000-000000000001',
  'active'
);

insert into public.community_conversation_members(conversation_id, user_id, status)
values
  ('82000000-0000-4000-8000-000000000011', '82000000-0000-4000-8000-000000000001', 'active'),
  ('82000000-0000-4000-8000-000000000011', '82000000-0000-4000-8000-000000000002', 'active');

insert into public.community_message_signals(
  id, recipient_id, conversation_id, type, event_key, expires_at
)
values (
  '82000000-0000-4000-8000-000000000021',
  '82000000-0000-4000-8000-000000000002',
  '82000000-0000-4000-8000-000000000011',
  'direct_message',
  'expired-before-write',
  now() - interval '1 minute'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '82000000-0000-4000-8000-000000000001', true);
select public.send_community_message('82000000-0000-4000-8000-000000000011', 'Write path signal');
reset role;

do $$
begin
  if not exists (
    select 1
    from public.community_message_signals
    where id = '82000000-0000-4000-8000-000000000021'
  ) then
    raise exception 'expired signal was pruned during message write';
  end if;
end $$;

select public.prune_community_message_signals(1);

do $$
begin
  if exists (
    select 1
    from public.community_message_signals
    where id = '82000000-0000-4000-8000-000000000021'
  ) then
    raise exception 'bounded maintenance prune did not remove expired signal';
  end if;
end $$;

rollback;
