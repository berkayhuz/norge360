-- Run against a disposable migrated database as its owner. Everything rolls back.
begin;

do $$
declare
  trigger_definition text;
  fanout_definition text;
begin
  select pg_get_functiondef(
    'public.create_community_group_chat_push_signals()'::regprocedure
  ) into trigger_definition;
  select pg_get_functiondef(
    'public.process_community_group_chat_push_fanout(uuid,integer)'::regprocedure
  ) into fanout_definition;

  if position('community_group_chat_push_fanout_jobs' in lower(trigger_definition)) = 0
     or position('community_group_chat_signals' in lower(trigger_definition)) > 0 then
    raise exception 'group-chat insert trigger still performs recipient fan-out';
  end if;

  if position('limit batch_size' in lower(fanout_definition)) = 0
     or position('cursor_user_id' in lower(fanout_definition)) = 0
     or position('skip locked' in lower(fanout_definition)) = 0 then
    raise exception 'group-chat fan-out RPC is not bounded, cursor-based and lock-aware';
  end if;
end $$;

insert into auth.users(id) values
  ('71000000-0000-4000-8000-000000000001'),
  ('71000000-0000-4000-8000-000000000002'),
  ('71000000-0000-4000-8000-000000000003'),
  ('71000000-0000-4000-8000-000000000004'),
  ('71000000-0000-4000-8000-000000000005');

insert into public.community_profiles(user_id, display_name, username, preferred_locale, norway_status)
values
  ('71000000-0000-4000-8000-000000000001', 'Fanout Sender', 'fanout_sender', 'en', 'resident'),
  ('71000000-0000-4000-8000-000000000002', 'Fanout One', 'fanout_one', 'en', 'resident'),
  ('71000000-0000-4000-8000-000000000003', 'Fanout Two', 'fanout_two', 'en', 'resident'),
  ('71000000-0000-4000-8000-000000000004', 'Fanout Three', 'fanout_three', 'en', 'resident'),
  ('71000000-0000-4000-8000-000000000005', 'Late Member', 'fanout_late', 'en', 'resident');

insert into public.community_groups(
  id, name, slug, description, scope, visibility, created_by
)
values (
  '71000000-0000-4000-8000-000000000011',
  'Fanout Group',
  'fanout-group',
  'A group used to verify asynchronous push fan-out.',
  'interest',
  'public',
  '71000000-0000-4000-8000-000000000001'
);

insert into public.community_group_memberships(group_id, user_id, role)
values
  ('71000000-0000-4000-8000-000000000011', '71000000-0000-4000-8000-000000000001', 'owner'),
  ('71000000-0000-4000-8000-000000000011', '71000000-0000-4000-8000-000000000002', 'member'),
  ('71000000-0000-4000-8000-000000000011', '71000000-0000-4000-8000-000000000003', 'member'),
  ('71000000-0000-4000-8000-000000000011', '71000000-0000-4000-8000-000000000004', 'member');

insert into public.community_group_chat_messages(
  id, group_id, sender_id, body
)
values (
  '71000000-0000-4000-8000-000000000021',
  '71000000-0000-4000-8000-000000000011',
  '71000000-0000-4000-8000-000000000001',
  'Bounded fan-out'
);

do $$
declare
  job_id uuid;
begin
  select id into job_id
  from public.community_group_chat_push_fanout_jobs
  where message_id = '71000000-0000-4000-8000-000000000021';

  if job_id is null then
    raise exception 'group-chat fan-out job was not enqueued';
  end if;

  if not public.process_community_group_chat_push_fanout(job_id, 2) then
    raise exception 'first fan-out batch did not report remaining recipients';
  end if;

  insert into public.community_group_memberships(group_id, user_id, role, created_at)
  values (
    '71000000-0000-4000-8000-000000000011',
    '71000000-0000-4000-8000-000000000005',
    'member',
    now() + interval '1 second'
  );

  if public.process_community_group_chat_push_fanout(job_id, 2) then
    raise exception 'second fan-out batch incorrectly reported remaining recipients';
  end if;
end $$;

do $$
begin
  if (select count(*) from public.community_group_chat_signals) <> 3 then
    raise exception 'bounded fan-out did not deliver exactly the original three recipients';
  end if;
  if exists (
    select 1
    from public.community_group_chat_signals
    where recipient_id = '71000000-0000-4000-8000-000000000005'
  ) then
    raise exception 'member who joined after the message received an old signal';
  end if;
end $$;

rollback;
