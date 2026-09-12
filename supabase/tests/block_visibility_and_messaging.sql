-- Run against a disposable fully migrated database as its owner.
-- Everything rolls back. The same assertions are repeated for both block
-- directions because the blocked actor must not become the visibility oracle.
begin;

insert into auth.users(id)
values
  ('95000000-0000-4000-8000-000000000001'),
  ('95000000-0000-4000-8000-000000000002');

insert into public.community_profiles(
  user_id,
  display_name,
  username,
  preferred_locale,
  norway_status,
  is_public,
  moderation_state
)
values
  (
    '95000000-0000-4000-8000-000000000001',
    'Block Viewer',
    'block_visibility_viewer',
    'en',
    'resident',
    true,
    'active'
  ),
  (
    '95000000-0000-4000-8000-000000000002',
    'Block Target',
    'block_visibility_target',
    'en',
    'resident',
    true,
    'active'
  );

insert into public.community_posts(id, author_id, title, body, kind)
values
  (
    '95000000-0000-4000-8000-000000000011',
    '95000000-0000-4000-8000-000000000002',
    'Blocked post',
    'blocked visibility body',
    'question'
  );

insert into public.community_conversations(
  id,
  participant_one_id,
  participant_two_id,
  requested_by_id,
  status
)
values (
  '95000000-0000-4000-8000-000000000021',
  '95000000-0000-4000-8000-000000000001',
  '95000000-0000-4000-8000-000000000002',
  '95000000-0000-4000-8000-000000000001',
  'active'
);

insert into public.community_conversation_members(conversation_id, user_id, status)
values
  (
    '95000000-0000-4000-8000-000000000021',
    '95000000-0000-4000-8000-000000000001',
    'active'
  ),
  (
    '95000000-0000-4000-8000-000000000021',
    '95000000-0000-4000-8000-000000000002',
    'active'
  );

insert into public.community_messages(
  id,
  conversation_id,
  sender_id,
  body
)
values (
  '95000000-0000-4000-8000-000000000031',
  '95000000-0000-4000-8000-000000000021',
  '95000000-0000-4000-8000-000000000002',
  'private message'
);

-- Direction 1: the viewer blocks the target.
insert into public.user_blocks(blocker_id, blocked_user_id)
values (
  '95000000-0000-4000-8000-000000000001',
  '95000000-0000-4000-8000-000000000002'
);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '95000000-0000-4000-8000-000000000001',
  true
);

do $$
declare
  profile_count integer;
  post_count integer;
begin
  if public.can_view_community_user('95000000-0000-4000-8000-000000000002') then
    raise exception 'viewer-to-target block did not deny user visibility';
  end if;

  select count(*) into profile_count
  from public.community_public_profiles
  where user_id = '95000000-0000-4000-8000-000000000002';

  select count(*) into post_count
  from public.search_community_posts('blocked visibility')
  where author_id = '95000000-0000-4000-8000-000000000002';

  if profile_count <> 0 or post_count <> 0 then
    raise exception 'viewer-to-target block leaked discovery results';
  end if;

  if exists (
    select 1
    from public.search_community_profiles('block_visibility_target')
    where user_id = '95000000-0000-4000-8000-000000000002'
  ) then
    raise exception 'viewer-to-target block leaked profile search';
  end if;

  begin
    perform public.list_community_conversation_messages_page(
      '95000000-0000-4000-8000-000000000021',
      50,
      null,
      null
    );
    raise exception 'viewer-to-target block allowed message read';
  exception when others then
    if sqlerrm = 'viewer-to-target block allowed message read' then
      raise;
    end if;
  end;

  begin
    perform public.send_community_message(
      '95000000-0000-4000-8000-000000000021',
      'blocked send'
    );
    raise exception 'viewer-to-target block allowed message send';
  exception when others then
    if sqlerrm = 'viewer-to-target block allowed message send' then
      raise;
    end if;
  end;

  begin
    perform public.create_direct_conversation(
      '95000000-0000-4000-8000-000000000002'
    );
    raise exception 'viewer-to-target block allowed conversation discovery';
  exception when others then
    if sqlerrm = 'viewer-to-target block allowed conversation discovery' then
      raise;
    end if;
  end;

end $$;

reset role;
delete from public.user_blocks
where blocker_id = '95000000-0000-4000-8000-000000000001'
  and blocked_user_id = '95000000-0000-4000-8000-000000000002';

-- Direction 2: the target blocks the viewer. The viewer must receive the
-- same boundary behavior even though it did not create the block row.
insert into public.user_blocks(blocker_id, blocked_user_id)
values (
  '95000000-0000-4000-8000-000000000002',
  '95000000-0000-4000-8000-000000000001'
);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '95000000-0000-4000-8000-000000000001',
  true
);

do $$
declare
  profile_count integer;
  post_count integer;
begin
  if public.can_view_community_user('95000000-0000-4000-8000-000000000002') then
    raise exception 'target-to-viewer block did not deny user visibility';
  end if;

  select count(*) into profile_count
  from public.community_public_profiles
  where user_id = '95000000-0000-4000-8000-000000000002';

  select count(*) into post_count
  from public.search_community_posts('blocked visibility')
  where author_id = '95000000-0000-4000-8000-000000000002';

  if profile_count <> 0 or post_count <> 0 then
    raise exception 'target-to-viewer block leaked discovery results';
  end if;

  if exists (
    select 1
    from public.search_community_profiles('block_visibility_target')
    where user_id = '95000000-0000-4000-8000-000000000002'
  ) then
    raise exception 'target-to-viewer block leaked profile search';
  end if;

  begin
    perform public.list_community_conversation_messages_page(
      '95000000-0000-4000-8000-000000000021',
      50,
      null,
      null
    );
    raise exception 'target-to-viewer block allowed message read';
  exception when others then
    if sqlerrm = 'target-to-viewer block allowed message read' then
      raise;
    end if;
  end;

  begin
    perform public.send_community_message(
      '95000000-0000-4000-8000-000000000021',
      'blocked send'
    );
    raise exception 'target-to-viewer block allowed message send';
  exception when others then
    if sqlerrm = 'target-to-viewer block allowed message send' then
      raise;
    end if;
  end;

  begin
    perform public.create_direct_conversation(
      '95000000-0000-4000-8000-000000000002'
    );
    raise exception 'target-to-viewer block allowed conversation discovery';
  exception when others then
    if sqlerrm = 'target-to-viewer block allowed conversation discovery' then
      raise;
    end if;
  end;

end $$;

reset role;
rollback;
