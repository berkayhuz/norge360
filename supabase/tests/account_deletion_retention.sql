-- Run against a disposable fully migrated database as its owner.
-- The account-deletion Worker owns the Auth/storage/provider boundary; this
-- test covers the database retention boundary and cascade prerequisites.
begin;

do $$
begin
  if not has_function_privilege(
    'service_role',
    'public.prepare_community_account_deletion(uuid)',
    'EXECUTE'
  ) then
    raise exception 'service_role cannot execute account deletion preparation';
  end if;
  if has_function_privilege(
    'authenticated',
    'public.prepare_community_account_deletion(uuid)',
    'EXECUTE'
  ) or has_function_privilege(
    'anon',
    'public.prepare_community_account_deletion(uuid)',
    'EXECUTE'
  ) then
    raise exception 'client roles can execute account deletion preparation';
  end if;

  if exists (
    select 1
    from pg_constraint
    where contype = 'f'
      and confrelid = 'auth.users'::regclass
      and confdeltype in ('r', 'a')
  ) then
    raise exception 'an auth.users foreign key still blocks account deletion';
  end if;
  if not has_function_privilege(
    'service_role',
    'public.begin_community_account_deletion(uuid)',
    'EXECUTE'
  ) or not has_function_privilege(
    'service_role',
    'public.claim_community_account_deletion_jobs(integer, uuid)',
    'EXECUTE'
  ) or not has_function_privilege(
    'service_role',
    'public.record_community_account_deletion_inventory(uuid, jsonb, text[])',
    'EXECUTE'
  ) or not has_function_privilege(
    'service_role',
    'public.claim_community_account_deletion_media(uuid, integer)',
    'EXECUTE'
  ) then
    raise exception 'service_role cannot execute resumable account deletion functions';
  end if;
  if has_function_privilege(
    'authenticated',
    'public.begin_community_account_deletion(uuid)',
    'EXECUTE'
  ) or has_function_privilege(
    'anon',
    'public.begin_community_account_deletion(uuid)',
    'EXECUTE'
  ) then
    raise exception 'client roles can start account deletion jobs';
  end if;
end $$;

insert into auth.users(id)
values
  ('97000000-0000-4000-8000-000000000001'),
  ('97000000-0000-4000-8000-000000000002');

select set_config(
  'request.jwt.claim.sub',
  '97000000-0000-4000-8000-000000000002',
  true
);

insert into public.community_profiles(user_id, display_name, preferred_locale, norway_status, username)
values (
  '97000000-0000-4000-8000-000000000002',
  'Retention Fixture',
  'en',
  'resident',
  'retentionfixture'
);

insert into public.community_profiles(user_id, display_name, preferred_locale, norway_status, username)
values (
  '97000000-0000-4000-8000-000000000001',
  'Account to delete',
  'en',
  'planning_move',
  'accounttodelete'
);

insert into public.user_account_profiles(user_id, preferred_locale)
values ('97000000-0000-4000-8000-000000000001', 'en');

insert into public.user_relocation_plans(user_id, plan)
values ('97000000-0000-4000-8000-000000000001', '{"status":"active"}'::jsonb);

insert into public.community_push_devices(user_id, token, environment)
values ('97000000-0000-4000-8000-000000000001', repeat('a', 64), 'development');

insert into public.community_posts(author_id, title, body, kind)
values ('97000000-0000-4000-8000-000000000001', 'Disposable post', 'Disposable public content', 'update');

insert into public.community_conversations(
  id, participant_one_id, participant_two_id, requested_by_id, status
)
values (
  '97000000-0000-4000-8000-000000000030',
  '97000000-0000-4000-8000-000000000001',
  '97000000-0000-4000-8000-000000000002',
  '97000000-0000-4000-8000-000000000001',
  'active'
);

insert into public.community_conversation_members(conversation_id, user_id, status)
values
  ('97000000-0000-4000-8000-000000000030', '97000000-0000-4000-8000-000000000001', 'active'),
  ('97000000-0000-4000-8000-000000000030', '97000000-0000-4000-8000-000000000002', 'active');

insert into public.community_messages(id, conversation_id, sender_id, body)
values
  (
    '97000000-0000-4000-8000-000000000031',
    '97000000-0000-4000-8000-000000000030',
    '97000000-0000-4000-8000-000000000001',
    'Reported message evidence'
  ),
  (
    '97000000-0000-4000-8000-000000000032',
    '97000000-0000-4000-8000-000000000030',
    '97000000-0000-4000-8000-000000000002',
    'Other participant history'
  );

insert into public.community_direct_message_attachments(
  id,
  conversation_id,
  message_id,
  uploader_id,
  storage_reference,
  mime_type,
  byte_size,
  provider_asset_id,
  status,
  scan_status,
  reviewed_at
)
values (
  '97000000-0000-4000-8000-000000000040',
  '97000000-0000-4000-8000-000000000030',
  '97000000-0000-4000-8000-000000000031',
  '97000000-0000-4000-8000-000000000001',
  '97000000-0000-4000-8000-000000000030/97000000-0000-4000-8000-000000000001/97000000-0000-4000-8000-000000000040',
  'image/jpeg',
  2048,
  'retained-direct-message-asset',
  'ready',
  'passed',
  now()
);

insert into public.community_groups(id, name, slug, description, scope, visibility, created_by)
values (
  '97000000-0000-4000-8000-000000000010',
  'Retention test group',
  'retention-test-group',
  'A disposable group used for retention boundary tests.',
  'interest',
  'public',
  '97000000-0000-4000-8000-000000000002'
);

insert into public.community_reports(id, reporter_id, target_type, target_id, reason)
values (
  '97000000-0000-4000-8000-000000000020',
  '97000000-0000-4000-8000-000000000001',
  'profile',
  '97000000-0000-4000-8000-000000000001',
  'other'
);

insert into public.community_reports(id, reporter_id, target_type, target_id, reason)
values (
  '97000000-0000-4000-8000-000000000021',
  '97000000-0000-4000-8000-000000000002',
  'message',
  '97000000-0000-4000-8000-000000000031',
  'message evidence'
);

insert into public.community_group_bans(group_id, user_id, created_by, previous_role)
values (
  '97000000-0000-4000-8000-000000000010',
  '97000000-0000-4000-8000-000000000002',
  '97000000-0000-4000-8000-000000000001',
  'member'
);

insert into public.community_group_moderation_audit(group_id, actor_id, target_user_id, action)
values (
  '97000000-0000-4000-8000-000000000010',
  '97000000-0000-4000-8000-000000000001',
  '97000000-0000-4000-8000-000000000001',
  'ban'
);

insert into public.community_moderation_action_audit(
  report_id, moderator_id, action, target_type, target_id
)
values (
  '97000000-0000-4000-8000-000000000020',
  '97000000-0000-4000-8000-000000000001',
  'content_removed',
  'profile',
  '97000000-0000-4000-8000-000000000001'
);

insert into public.community_moderation_review_audit(
  report_id, moderator_id, previous_status, next_status, action
)
values (
  '97000000-0000-4000-8000-000000000020',
  '97000000-0000-4000-8000-000000000001',
  'open',
  'resolved',
  'no_action'
);

set local role service_role;
select set_config('request.jwt.claim.role', 'service_role', true);
select public.begin_community_account_deletion('97000000-0000-4000-8000-000000000001');

do $$
begin
  if not exists (
    select 1
    from public.community_account_deletion_jobs
    where user_id = '97000000-0000-4000-8000-000000000001'
      and status = 'pending'
      and not inventory_ready
  ) then
    raise exception 'account deletion job was not persisted before cleanup';
  end if;
  if not exists (
    select 1
    from public.community_reports
    where id = '97000000-0000-4000-8000-000000000020'
      and reporter_id is not null
      and target_id is not null
  ) then
    raise exception 'account deletion job detached evidence before cleanup';
  end if;
end $$;

select public.record_community_account_deletion_inventory(
  '97000000-0000-4000-8000-000000000001',
  '[{"bucket":"avatars","path":"97000000-0000-4000-8000-000000000001/avatar.png"}]'::jsonb,
  array['deletable-provider-asset']
);

do $$
declare
  claimed_count integer;
begin
  select count(*) into claimed_count
  from public.claim_community_account_deletion_media(
    '97000000-0000-4000-8000-000000000001',
    50
  );
  if claimed_count <> 2 then
    raise exception 'account deletion media inventory was not claimed in bounded work';
  end if;
end $$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '97000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
begin
  begin
    perform public.upsert_own_community_profile(
      'Deletion Pending',
      'deletionpending',
      'en',
      'planning_move',
      null,
      array[]::text[],
      array[]::text[],
      false
    );
    raise exception 'account writes were not blocked while deletion was pending';
  exception
    when sqlstate '55000' then
      null;
  end;
end $$;

reset role;
set local role service_role;
select set_config('request.jwt.claim.role', 'service_role', true);
select public.prepare_community_account_deletion('97000000-0000-4000-8000-000000000001');

do $$
begin
  if exists (
    select 1 from public.community_reports
    where id = '97000000-0000-4000-8000-000000000020' and reporter_id is not null
  ) then
    raise exception 'report reporter identity was not detached';
  end if;
  if exists (
    select 1 from public.community_reports
    where id = '97000000-0000-4000-8000-000000000020' and target_id is not null
  ) then
    raise exception 'profile report target identity was not detached';
  end if;
  if exists (
    select 1 from public.community_group_bans
    where group_id = '97000000-0000-4000-8000-000000000010' and created_by is not null
  ) then
    raise exception 'group-ban creator identity was not detached';
  end if;
  if exists (
    select 1 from public.community_group_moderation_audit
    where group_id = '97000000-0000-4000-8000-000000000010'
      and (actor_id is not null or target_user_id is not null)
  ) then
    raise exception 'group moderation identities were not detached';
  end if;
  if exists (
    select 1 from public.community_moderation_action_audit
    where report_id = '97000000-0000-4000-8000-000000000020'
      and (moderator_id is not null or target_id is not null)
  ) or exists (
    select 1 from public.community_moderation_review_audit
    where report_id = '97000000-0000-4000-8000-000000000020' and moderator_id is not null
  ) then
    raise exception 'moderation audit identity was not detached';
  end if;
end $$;

do $$
begin
  insert into public.community_group_memberships(group_id, user_id, role)
  values (
    '97000000-0000-4000-8000-000000000010',
    '97000000-0000-4000-8000-000000000001',
    'owner'
  );

  begin
    perform public.prepare_community_account_deletion('97000000-0000-4000-8000-000000000001');
    raise exception 'group owner deletion was not blocked';
  exception
    when others then
      if position('owned groups require ownership transfer' in sqlerrm) = 0 then
        raise;
      end if;
  end;
end $$;

delete from public.community_group_memberships
where group_id = '97000000-0000-4000-8000-000000000010'
  and user_id = '97000000-0000-4000-8000-000000000001';

reset role;
delete from auth.users
where id = '97000000-0000-4000-8000-000000000001';

do $$
begin
  if exists (select 1 from public.community_profiles where user_id = '97000000-0000-4000-8000-000000000001')
     or exists (select 1 from public.user_account_profiles where user_id = '97000000-0000-4000-8000-000000000001')
     or exists (select 1 from public.user_relocation_plans where user_id = '97000000-0000-4000-8000-000000000001')
     or exists (select 1 from public.community_push_devices where user_id = '97000000-0000-4000-8000-000000000001')
     or exists (select 1 from public.community_posts where author_id = '97000000-0000-4000-8000-000000000001') then
    raise exception 'account-owned records did not cascade on account deletion';
  end if;
  if not exists (select 1 from public.community_reports where id = '97000000-0000-4000-8000-000000000020') then
    raise exception 'retained report was deleted with the account';
  end if;
  if not exists (select 1 from public.community_group_moderation_audit where group_id = '97000000-0000-4000-8000-000000000010') then
    raise exception 'retained group moderation audit was deleted with the account';
  end if;
  if not exists (
    select 1
    from public.community_conversations
    where id = '97000000-0000-4000-8000-000000000030'
  ) or not exists (
    select 1
    from public.community_messages
    where id = '97000000-0000-4000-8000-000000000031'
      and sender_id = '97000000-0000-4000-8000-000000000001'
      and body = 'Reported message evidence'
  ) or not exists (
    select 1
    from public.community_messages
    where id = '97000000-0000-4000-8000-000000000032'
      and sender_id = '97000000-0000-4000-8000-000000000002'
  ) then
    raise exception 'direct conversation history was deleted with the account';
  end if;
  if not exists (
    select 1
    from public.community_direct_message_attachments
    where id = '97000000-0000-4000-8000-000000000040'
      and uploader_id = '97000000-0000-4000-8000-000000000001'
      and provider_asset_id = 'retained-direct-message-asset'
  ) then
    raise exception 'direct message media evidence was deleted with the account';
  end if;
  if exists (
    select 1
    from public.community_conversation_members
    where conversation_id = '97000000-0000-4000-8000-000000000030'
      and user_id = '97000000-0000-4000-8000-000000000001'
  ) or not exists (
    select 1
    from public.community_conversation_members
    where conversation_id = '97000000-0000-4000-8000-000000000030'
      and user_id = '97000000-0000-4000-8000-000000000002'
  ) then
    raise exception 'remaining conversation membership is inconsistent';
  end if;
  if not exists (
    select 1
    from public.community_reports
    where id = '97000000-0000-4000-8000-000000000021'
      and reporter_id = '97000000-0000-4000-8000-000000000002'
      and target_id = '97000000-0000-4000-8000-000000000031'
  ) then
    raise exception 'open message report lost its message evidence reference';
  end if;
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '97000000-0000-4000-8000-000000000002', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
begin
  if not exists (
    select 1
    from public.list_community_direct_conversations_page(50, null, null, null)
    where conversation_id = '97000000-0000-4000-8000-000000000030'
      and display_name = 'Deleted member'
  ) then
    raise exception 'remaining member cannot see retained deleted-member conversation';
  end if;
  if not exists (
    select 1
    from public.list_community_conversation_messages_page(
      '97000000-0000-4000-8000-000000000030', 50, null, null
    )
    where id = '97000000-0000-4000-8000-000000000031'
      and body = 'Reported message evidence'
  ) then
    raise exception 'remaining member cannot read retained direct-message history';
  end if;
end $$;

reset role;
set local role service_role;
select set_config('request.jwt.claim.role', 'service_role', true);

do $$
declare
  asset_id text;
  limited boolean;
begin
  select result.provider_asset_id, result.rate_limited
  into asset_id, limited
  from public.issue_community_media_view(
    'direct',
    '97000000-0000-4000-8000-000000000040',
    '97000000-0000-4000-8000-000000000002'
  ) as result;
  if asset_id <> 'retained-direct-message-asset' or limited then
    raise exception 'remaining member cannot access retained direct-message media';
  end if;
end $$;

reset role;
rollback;
