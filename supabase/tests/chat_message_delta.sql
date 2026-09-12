-- Run against a disposable database after all migrations. Everything rolls back.
begin;

insert into auth.users(id) values
  ('60000000-0000-4000-8000-000000000001'),
  ('60000000-0000-4000-8000-000000000002'),
  ('60000000-0000-4000-8000-000000000003');

insert into public.community_profiles(user_id, display_name, preferred_locale, norway_status, username) values
  ('60000000-0000-4000-8000-000000000001', 'Delta One', 'en', 'resident', 'delta_one'),
  ('60000000-0000-4000-8000-000000000002', 'Delta Two', 'en', 'resident', 'delta_two'),
  ('60000000-0000-4000-8000-000000000003', 'Delta Outside', 'en', 'resident', 'delta_outside');

insert into public.community_conversations(
  id, participant_one_id, participant_two_id, requested_by_id, status
) values (
  '61000000-0000-4000-8000-000000000001',
  '60000000-0000-4000-8000-000000000001',
  '60000000-0000-4000-8000-000000000002',
  '60000000-0000-4000-8000-000000000001',
  'active'
);
insert into public.community_conversation_members(conversation_id, user_id, status) values
  ('61000000-0000-4000-8000-000000000001', '60000000-0000-4000-8000-000000000001', 'active'),
  ('61000000-0000-4000-8000-000000000001', '60000000-0000-4000-8000-000000000002', 'active');
insert into public.community_messages(id, conversation_id, sender_id, body, created_at) values
  ('62000000-0000-4000-8000-000000000001', '61000000-0000-4000-8000-000000000001', '60000000-0000-4000-8000-000000000002', 'first', '2026-01-01 00:00:00+00'),
  ('62000000-0000-4000-8000-000000000002', '61000000-0000-4000-8000-000000000001', '60000000-0000-4000-8000-000000000002', 'second', '2026-01-01 00:00:00+00'),
  ('62000000-0000-4000-8000-000000000003', '61000000-0000-4000-8000-000000000001', '60000000-0000-4000-8000-000000000002', 'third', '2026-01-01 00:01:00+00');

set local role authenticated;
select set_config('request.jwt.claim.sub', '60000000-0000-4000-8000-000000000001', true);
do $$ begin
  if (select count(*) from public.list_community_conversation_messages_after(
    '61000000-0000-4000-8000-000000000001',
    '2026-01-01 00:00:00+00',
    '62000000-0000-4000-8000-000000000001'
  )) <> 2 then
    raise exception 'direct message delta did not use the composite cursor';
  end if;
  if exists (
    select 1 from public.list_community_conversation_messages_after(
      '61000000-0000-4000-8000-000000000001',
      '2026-01-01 00:00:00+00',
      '62000000-0000-4000-8000-000000000001'
    ) where id = '62000000-0000-4000-8000-000000000001'
  ) then
    raise exception 'direct message delta repeated the cursor row';
  end if;
end $$;

select set_config('request.jwt.claim.sub', '60000000-0000-4000-8000-000000000003', true);
do $$ begin
  perform * from public.list_community_conversation_messages_after(
    '61000000-0000-4000-8000-000000000001',
    '2026-01-01 00:00:00+00',
    '62000000-0000-4000-8000-000000000001'
  );
  raise exception 'unauthorized direct message delta read succeeded';
exception when others then
  if sqlerrm = 'unauthorized direct message delta read succeeded' then raise; end if;
end $$;

insert into public.community_groups(id, name, slug, description, scope, visibility, created_by) values
  ('63000000-0000-4000-8000-000000000001', 'Delta Group', 'delta-group', 'A group used for message delta assertions.', 'interest', 'public', '60000000-0000-4000-8000-000000000001');
insert into public.community_group_memberships(group_id, user_id, role) values
  ('63000000-0000-4000-8000-000000000001', '60000000-0000-4000-8000-000000000001', 'owner'),
  ('63000000-0000-4000-8000-000000000001', '60000000-0000-4000-8000-000000000002', 'member');
insert into public.community_group_chat_messages(id, group_id, sender_id, body, created_at) values
  ('64000000-0000-4000-8000-000000000001', '63000000-0000-4000-8000-000000000001', '60000000-0000-4000-8000-000000000002', 'group first', '2026-01-01 00:00:00+00'),
  ('64000000-0000-4000-8000-000000000002', '63000000-0000-4000-8000-000000000001', '60000000-0000-4000-8000-000000000002', 'group second', '2026-01-01 00:01:00+00');

select set_config('request.jwt.claim.sub', '60000000-0000-4000-8000-000000000001', true);
do $$ begin
  if (select count(*) from public.list_community_group_chat_messages_after(
    '63000000-0000-4000-8000-000000000001',
    '2026-01-01 00:00:00+00',
    '64000000-0000-4000-8000-000000000001'
  )) <> 1 then
    raise exception 'group message delta did not return only newer rows';
  end if;
end $$;

rollback;
