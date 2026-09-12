-- Run against a disposable migrated database. Everything rolls back.
begin;

do $$
declare
  direct_page_definition text;
  group_page_definition text;
  inbox_page_definition text;
begin
  select pg_get_functiondef(
    'public.list_community_conversation_messages_page(uuid,integer,timestamptz,uuid)'::regprocedure
  ) into direct_page_definition;
  select pg_get_functiondef(
    'public.list_community_group_chat_messages_page(uuid,integer,timestamptz,uuid)'::regprocedure
  ) into group_page_definition;
  select pg_get_functiondef(
    'public.list_community_direct_conversations_page(integer,boolean,timestamptz,uuid)'::regprocedure
  ) into inbox_page_definition;

  if position('order by message.created_at desc, message.id desc' in lower(direct_page_definition)) = 0
     or position('before_message_id' in lower(direct_page_definition)) = 0
     or position('limit page_size' in lower(direct_page_definition)) = 0 then
    raise exception 'direct message page is not bounded and cursor-based';
  end if;
  if position('order by message.created_at desc, message.id desc' in lower(group_page_definition)) = 0
     or position('before_message_id' in lower(group_page_definition)) = 0
     or position('limit page_size' in lower(group_page_definition)) = 0 then
    raise exception 'group message page is not bounded and cursor-based';
  end if;
  if position('is_restricted' in lower(inbox_page_definition)) = 0
     or position('unread_count' in lower(inbox_page_definition)) = 0
     or position('after_conversation_id' in lower(inbox_page_definition)) = 0
     or position('limit page_size' in lower(inbox_page_definition)) = 0 then
    raise exception 'inbox page does not include preferences, unread count and cursor';
  end if;
end $$;

insert into auth.users(id) values
  ('73000000-0000-4000-8000-000000000001'),
  ('73000000-0000-4000-8000-000000000002'),
  ('73000000-0000-4000-8000-000000000003');

insert into public.community_profiles(user_id, display_name, username, preferred_locale, norway_status)
values
  ('73000000-0000-4000-8000-000000000001', 'Window One', 'window_one', 'en', 'resident'),
  ('73000000-0000-4000-8000-000000000002', 'Window Two', 'window_two', 'en', 'resident'),
  ('73000000-0000-4000-8000-000000000003', 'Window Three', 'window_three', 'en', 'resident');

insert into public.community_conversations(
  id, participant_one_id, participant_two_id, requested_by_id, status, updated_at
)
values (
  '73000000-0000-4000-8000-000000000011',
  '73000000-0000-4000-8000-000000000001',
  '73000000-0000-4000-8000-000000000002',
  '73000000-0000-4000-8000-000000000001',
  'active',
  '2026-01-01 00:05:00+00'
);
insert into public.community_conversation_members(conversation_id, user_id, status, last_read_at)
values
  ('73000000-0000-4000-8000-000000000011', '73000000-0000-4000-8000-000000000001', 'active', '2026-01-01 00:00:00+00'),
  ('73000000-0000-4000-8000-000000000011', '73000000-0000-4000-8000-000000000002', 'active', null);
insert into public.community_conversation_preferences(
  conversation_id, user_id, is_muted, is_pinned, is_hidden, is_restricted, background_style, bubble_color
)
values (
  '73000000-0000-4000-8000-000000000011',
  '73000000-0000-4000-8000-000000000001',
  true, true, false, true, 'grid', 'purple'
);
insert into public.community_messages(id, conversation_id, sender_id, body, created_at)
values
  ('73000000-0000-4000-8000-000000000021', '73000000-0000-4000-8000-000000000011', '73000000-0000-4000-8000-000000000002', 'older', '2026-01-01 00:01:00+00'),
  ('73000000-0000-4000-8000-000000000022', '73000000-0000-4000-8000-000000000011', '73000000-0000-4000-8000-000000000002', 'newer', '2026-01-01 00:02:00+00'),
  ('73000000-0000-4000-8000-000000000023', '73000000-0000-4000-8000-000000000011', '73000000-0000-4000-8000-000000000001', 'outgoing', '2026-01-01 00:03:00+00');

set local role authenticated;
select set_config('request.jwt.claim.sub', '73000000-0000-4000-8000-000000000001', true);

do $$
begin
  if (select array_agg(id order by created_at, id)::text
      from public.list_community_conversation_messages_page(
        '73000000-0000-4000-8000-000000000011', 2, null, null
      )) <> '{73000000-0000-4000-8000-000000000022,73000000-0000-4000-8000-000000000023}' then
    raise exception 'direct page did not return the newest messages in ascending order';
  end if;

  if (select count(*)
      from public.list_community_conversation_messages_page(
        '73000000-0000-4000-8000-000000000011', 2,
        '2026-01-01 00:02:00+00', '73000000-0000-4000-8000-000000000022'
      )) <> 1 then
    raise exception 'direct older cursor did not return the remaining message';
  end if;

  if not exists (
    select 1
    from public.list_community_direct_conversations_page(50, null, null, null)
    where conversation_id = '73000000-0000-4000-8000-000000000011'
      and is_muted
      and is_pinned
      and is_restricted
      and background_style = 'grid'
      and bubble_color = 'purple'
      and unread_count = 2
  ) then
    raise exception 'inbox page did not return preferences and unread count';
  end if;
end $$;

rollback;
