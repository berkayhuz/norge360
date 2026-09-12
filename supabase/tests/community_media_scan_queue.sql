-- Run against a disposable, fully migrated database as its owner.
-- The Worker service role is the only caller of the scan state-machine RPCs;
-- this test intentionally checks ACLs without executing them as anon.
begin;

do $$
begin
  if to_regprocedure('public.queue_community_media_scan(text,uuid,uuid)') is null
     or to_regprocedure('public.claim_community_media_scan(text,uuid)') is null
     or to_regprocedure('public.get_community_media_scan_status(text,uuid,uuid)') is null
     or to_regprocedure('public.finish_community_media_scan(text,uuid,text,text,text)') is null then
    raise exception
      'Missing prerequisite migration: 20260912100000_async_community_media_safety_scan.sql. Apply migrations in filename order before running this test.';
  end if;
end $$;

do $$
begin
  if has_function_privilege(
       'anon',
       'public.queue_community_media_scan(text,uuid,uuid)',
       'execute'
     )
     or has_function_privilege(
       'authenticated',
       'public.queue_community_media_scan(text,uuid,uuid)',
       'execute'
     ) then
    raise exception 'client role can enqueue private media scans';
  end if;
  if has_function_privilege(
       'anon',
       'public.claim_community_media_scan(text,uuid)',
       'execute'
     )
     or has_function_privilege(
       'authenticated',
       'public.claim_community_media_scan(text,uuid)',
       'execute'
     ) then
    raise exception 'client role can claim private media scans';
  end if;
  if has_function_privilege(
       'anon',
       'public.get_community_media_scan_status(text,uuid,uuid)',
       'execute'
     )
     or has_function_privilege(
       'authenticated',
       'public.get_community_media_scan_status(text,uuid,uuid)',
       'execute'
     ) then
    raise exception 'client role can read private media scan status';
  end if;
  if has_function_privilege(
       'anon',
       'public.finish_community_media_scan(text,uuid,text,text,text)',
       'execute'
     )
     or has_function_privilege(
       'authenticated',
       'public.finish_community_media_scan(text,uuid,text,text,text)',
       'execute'
     ) then
    raise exception 'client role can finish private media scans';
  end if;
  if not has_function_privilege(
       'service_role',
       'public.queue_community_media_scan(text,uuid,uuid)',
       'execute'
     )
     or not has_function_privilege(
       'service_role',
       'public.claim_community_media_scan(text,uuid)',
       'execute'
     )
     or not has_function_privilege(
       'service_role',
       'public.get_community_media_scan_status(text,uuid,uuid)',
       'execute'
     )
     or not has_function_privilege(
       'service_role',
       'public.finish_community_media_scan(text,uuid,text,text,text)',
       'execute'
     ) then
    raise exception 'service role cannot execute private media scan RPCs';
  end if;
end $$;

insert into auth.users(id) values
  ('95000000-0000-4000-8000-000000000001'),
  ('95000000-0000-4000-8000-000000000002'),
  ('95000000-0000-4000-8000-000000000003');

insert into public.community_conversations(
  id,
  participant_one_id,
  participant_two_id,
  requested_by_id,
  status
)
values (
  '96000000-0000-4000-8000-000000000001',
  '95000000-0000-4000-8000-000000000001',
  '95000000-0000-4000-8000-000000000002',
  '95000000-0000-4000-8000-000000000001',
  'active'
);

insert into public.community_conversation_members(conversation_id, user_id, status)
values
  ('96000000-0000-4000-8000-000000000001', '95000000-0000-4000-8000-000000000001', 'active'),
  ('96000000-0000-4000-8000-000000000001', '95000000-0000-4000-8000-000000000002', 'active');

insert into public.community_groups(
  id,
  name,
  slug,
  description,
  scope,
  created_by
)
values (
  '98000000-0000-4000-8000-000000000001',
  'Async Scan Group',
  'async-scan-group',
  'Background media scan test group',
  'interest',
  '95000000-0000-4000-8000-000000000001'
);

insert into public.community_group_memberships(group_id, user_id)
values ('98000000-0000-4000-8000-000000000001', '95000000-0000-4000-8000-000000000001');

insert into public.community_group_chat_messages(id, group_id, sender_id, body)
values (
  '99000000-0000-4000-8000-000000000001',
  '98000000-0000-4000-8000-000000000001',
  '95000000-0000-4000-8000-000000000001',
  'group image'
);

insert into public.community_direct_message_attachments(
  id,
  conversation_id,
  uploader_id,
  storage_reference,
  mime_type,
  byte_size,
  provider_asset_id,
  status,
  scan_status
)
values
  (
    '97000000-0000-4000-8000-000000000001',
    '96000000-0000-4000-8000-000000000001',
    '95000000-0000-4000-8000-000000000001',
    '96000000-0000-4000-8000-000000000001/95000000-0000-4000-8000-000000000001/97000000-0000-4000-8000-000000000001',
    'image/jpeg',
    2048,
    'async-scan-image-one',
    'pending_upload',
    'not_started'
  ),
  (
    '97000000-0000-4000-8000-000000000002',
    '96000000-0000-4000-8000-000000000001',
    '95000000-0000-4000-8000-000000000001',
    '96000000-0000-4000-8000-000000000001/95000000-0000-4000-8000-000000000001/97000000-0000-4000-8000-000000000002',
    'image/jpeg',
    2048,
    'async-scan-image-two',
    'pending_upload',
    'not_started'
  );

insert into public.community_group_chat_attachments(
  id,
  group_id,
  uploader_id,
  storage_path,
  mime_type,
  byte_size,
  storage_provider,
  provider_asset_id,
  status,
  scan_status
)
values (
  '9a000000-0000-4000-8000-000000000001',
  '98000000-0000-4000-8000-000000000001',
  '95000000-0000-4000-8000-000000000001',
  '98000000-0000-4000-8000-000000000001/95000000-0000-4000-8000-000000000001/9a000000-0000-4000-8000-000000000001',
  'image/jpeg',
  2048,
  'cloudflare_images',
  'async-scan-group-image',
  'pending_upload',
  'not_started'
);

set local role service_role;

do $$
declare
  asset_id text;
  state text;
begin
  select result.provider_asset_id, result.queue_state
  into asset_id, state
  from public.queue_community_media_scan(
    'direct',
    '97000000-0000-4000-8000-000000000001',
    '95000000-0000-4000-8000-000000000001'
  ) as result;

  if asset_id <> 'async-scan-image-one' or state <> 'queued' then
    raise exception 'authorized media scan was not queued atomically';
  end if;
end $$;

do $$
declare
  asset_id text;
  attempts integer;
  terminal_state boolean;
begin
  select result.provider_asset_id, result.attempt_count, result.terminal
  into asset_id, attempts, terminal_state
  from public.claim_community_media_scan(
    'direct',
    '97000000-0000-4000-8000-000000000001'
  ) as result;

  if asset_id <> 'async-scan-image-one' or attempts <> 1 or terminal_state then
    raise exception 'queued media scan was not claimed';
  end if;
end $$;

select public.finish_community_media_scan(
  'direct',
  '97000000-0000-4000-8000-000000000001',
  'passed',
  'automated_safety_passed',
  null
);

do $$
declare
  state text;
begin
  select result.queue_state
  into state
  from public.queue_community_media_scan(
    'group',
    '9a000000-0000-4000-8000-000000000001',
    '95000000-0000-4000-8000-000000000001'
  ) as result;
  if state <> 'queued' then
    raise exception 'authorized group media scan was not queued';
  end if;
end $$;

do $$
declare
  asset_id text;
  attempts integer;
  terminal_state boolean;
begin
  select result.provider_asset_id, result.attempt_count, result.terminal
  into asset_id, attempts, terminal_state
  from public.claim_community_media_scan(
    'group',
    '9a000000-0000-4000-8000-000000000001'
  ) as result;
  if asset_id <> 'async-scan-group-image' or attempts <> 1 or terminal_state then
    raise exception 'queued group media scan was not claimed';
  end if;
end $$;

select public.finish_community_media_scan(
  'group',
  '9a000000-0000-4000-8000-000000000001',
  'needs_review',
  'automated_safety_review',
  null
);

do $$
declare
  current_outcome text;
begin
  select result.outcome
  into current_outcome
  from public.get_community_media_scan_status(
    'group',
    '9a000000-0000-4000-8000-000000000001',
    '95000000-0000-4000-8000-000000000001'
  ) as result;
  if current_outcome <> 'needs_review' then
    raise exception 'group scan status did not expose review outcome';
  end if;
end $$;

do $$
declare
  current_status text;
  current_scan_status text;
begin
  select status, scan_status
  into current_status, current_scan_status
  from public.community_direct_message_attachments
  where id = '97000000-0000-4000-8000-000000000001';
  if current_status <> 'ready' or current_scan_status <> 'passed' then
    raise exception 'passed media scan did not become ready';
  end if;
end $$;

do $$
declare
  current_outcome text;
begin
  select result.outcome
  into current_outcome
  from public.get_community_media_scan_status(
    'direct',
    '97000000-0000-4000-8000-000000000001',
    '95000000-0000-4000-8000-000000000001'
  ) as result;
  if current_outcome <> 'passed' then
    raise exception 'scan status did not expose the normalized passed outcome';
  end if;
end $$;

do $$
begin
  if exists (
    select 1
    from public.queue_community_media_scan(
      'direct',
      '97000000-0000-4000-8000-000000000001',
      '95000000-0000-4000-8000-000000000003'
    )
  ) then
    raise exception 'non-member queued a private media scan';
  end if;
end $$;

do $$
declare
  state text;
begin
  select result.queue_state
  into state
  from public.queue_community_media_scan(
    'direct',
    '97000000-0000-4000-8000-000000000002',
    '95000000-0000-4000-8000-000000000001'
  ) as result;
  if state <> 'queued' then
    raise exception 'second media scan was not queued';
  end if;
end $$;

do $$
declare
  asset_id text;
  attempts integer;
  terminal_state boolean;
begin
  select result.provider_asset_id, result.attempt_count, result.terminal
  into asset_id, attempts, terminal_state
  from public.claim_community_media_scan(
    'direct',
    '97000000-0000-4000-8000-000000000002'
  ) as result;
  if asset_id <> 'async-scan-image-two' or attempts <> 1 or terminal_state then
    raise exception 'second queued media scan was not claimed';
  end if;
end $$;

select public.finish_community_media_scan(
  'direct',
  '97000000-0000-4000-8000-000000000002',
  'retry',
  'safety_scan_unavailable',
  'provider_scan_unavailable'
);

reset role;
rollback;
