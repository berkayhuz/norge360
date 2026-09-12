-- Run against a disposable database after the group-chat migrations. Every
-- assertion rolls back. This test contains no user-generated message content.
begin;

insert into auth.users(id) values
  ('30000000-0000-4000-8000-000000000001'),
  ('30000000-0000-4000-8000-000000000002'),
  ('30000000-0000-4000-8000-000000000003');

insert into public.community_profiles(user_id, display_name, preferred_locale, norway_status, username) values
  ('30000000-0000-4000-8000-000000000001', 'Group Sender', 'en', 'resident', 'group_push_sender'),
  ('30000000-0000-4000-8000-000000000002', 'Group Recipient', 'en', 'resident', 'group_push_recipient'),
  ('30000000-0000-4000-8000-000000000003', 'Outside Member', 'en', 'resident', 'group_push_outside');

insert into public.community_groups(id, name, slug, description, scope, visibility, created_by) values
  ('40000000-0000-4000-8000-000000000001', 'Push test group', 'push-test-group', 'A private test group used only for transport-signal assertions.', 'interest', 'public', '30000000-0000-4000-8000-000000000001');
insert into public.community_group_memberships(group_id, user_id, role) values
  ('40000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', 'owner'),
  ('40000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000002', 'member');

insert into public.community_group_chat_messages(id, group_id, sender_id, body) values
  ('50000000-0000-4000-8000-000000000001', '40000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', 'Transport signal test');

select public.process_community_group_chat_push_fanout(
  (select id from public.community_group_chat_push_fanout_jobs where message_id = '50000000-0000-4000-8000-000000000001'),
  100
);

do $$ begin
  if (select count(*) from public.community_group_chat_signals) <> 1 then
    raise exception 'expected exactly one group recipient signal';
  end if;
  if exists (
    select 1 from public.community_group_chat_signals
    where recipient_id = '30000000-0000-4000-8000-000000000001'
  ) then
    raise exception 'sender received its own group signal';
  end if;
  if not public.can_deliver_community_group_chat_signal(
    (select id from public.community_group_chat_signals limit 1)
  ) then
    raise exception 'normal group push was suppressed';
  end if;
end $$;

-- A non-member has no RLS visibility of the recipient signal.
set local role authenticated;
select set_config('request.jwt.claim.sub', '30000000-0000-4000-8000-000000000003', true);
do $$ begin
  if exists (select 1 from public.community_group_chat_signals) then
    raise exception 'non-member read a group signal';
  end if;
end $$;

-- Muting is member-controlled and immediately suppresses Worker eligibility.
select set_config('request.jwt.claim.sub', '30000000-0000-4000-8000-000000000002', true);
select public.update_community_group_chat_notification_preference(
  '40000000-0000-4000-8000-000000000001', true
);
reset role;
do $$ begin
  if public.can_deliver_community_group_chat_signal(
    (select id from public.community_group_chat_signals limit 1)
  ) then
    raise exception 'muted group push remained eligible';
  end if;
end $$;

-- Losing membership invalidates both foreground visibility and push delivery.
delete from public.community_group_memberships
where group_id = '40000000-0000-4000-8000-000000000001'
  and user_id = '30000000-0000-4000-8000-000000000002';
do $$ begin
  if public.can_deliver_community_group_chat_signal(
    (select id from public.community_group_chat_signals limit 1)
  ) then
    raise exception 'former member group push remained eligible';
  end if;
end $$;

rollback;
