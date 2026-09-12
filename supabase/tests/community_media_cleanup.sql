-- Run against a disposable, fully migrated database as its owner.
-- Cleanup claim/finalize RPCs are service-role-only; provider deletion is
-- intentionally represented by the test's successful finalize transition.
begin;

do $$
begin
  if to_regprocedure('public.claim_expired_community_media_attachments(text,integer)') is null
     or to_regprocedure('public.finalize_community_media_cleanup(text,uuid)') is null then
    raise exception
      'Missing prerequisite migration: 20260912110000_async_community_media_cleanup.sql. Apply migrations in filename order before running this test.';
  end if;
end $$;

do $$
begin
  if has_function_privilege(
       'anon',
       'public.claim_expired_community_media_attachments(text,integer)',
       'execute'
     )
     or has_function_privilege(
       'authenticated',
       'public.claim_expired_community_media_attachments(text,integer)',
       'execute'
     )
     or has_function_privilege(
       'anon',
       'public.finalize_community_media_cleanup(text,uuid)',
       'execute'
     )
     or has_function_privilege(
       'authenticated',
       'public.finalize_community_media_cleanup(text,uuid)',
       'execute'
     ) then
    raise exception 'client role can execute private media cleanup RPCs';
  end if;
  if not has_function_privilege(
       'service_role',
       'public.claim_expired_community_media_attachments(text,integer)',
       'execute'
     )
     or not has_function_privilege(
       'service_role',
       'public.finalize_community_media_cleanup(text,uuid)',
       'execute'
     ) then
    raise exception 'service role cannot execute private media cleanup RPCs';
  end if;
end $$;

insert into auth.users(id) values
  ('9b000000-0000-4000-8000-000000000001'),
  ('9b000000-0000-4000-8000-000000000002');

insert into public.community_conversations(
  id,
  participant_one_id,
  participant_two_id,
  requested_by_id,
  status
)
values (
  '9c000000-0000-4000-8000-000000000001',
  '9b000000-0000-4000-8000-000000000001',
  '9b000000-0000-4000-8000-000000000002',
  '9b000000-0000-4000-8000-000000000001',
  'active'
);

insert into public.community_conversation_members(conversation_id, user_id, status)
values
  ('9c000000-0000-4000-8000-000000000001', '9b000000-0000-4000-8000-000000000001', 'active'),
  ('9c000000-0000-4000-8000-000000000001', '9b000000-0000-4000-8000-000000000002', 'active');

insert into public.community_groups(
  id,
  name,
  slug,
  description,
  scope,
  created_by
)
values (
  '9d000000-0000-4000-8000-000000000001',
  'Cleanup Test Group',
  'cleanup-test-group',
  'Background cleanup test group',
  'interest',
  '9b000000-0000-4000-8000-000000000001'
);

insert into public.community_group_memberships(group_id, user_id)
values ('9d000000-0000-4000-8000-000000000001', '9b000000-0000-4000-8000-000000000001');

insert into public.community_messages(id, conversation_id, sender_id, body)
values (
  '9e000000-0000-4000-8000-000000000001',
  '9c000000-0000-4000-8000-000000000001',
  '9b000000-0000-4000-8000-000000000001',
  'retained message'
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
  reviewed_at,
  created_at
)
values
  (
    '9f000000-0000-4000-8000-000000000001',
    '9c000000-0000-4000-8000-000000000001',
    null,
    '9b000000-0000-4000-8000-000000000001',
    '9c000000-0000-4000-8000-000000000001/9b000000-0000-4000-8000-000000000001/9f000000-0000-4000-8000-000000000001',
    'image/jpeg',
    2048,
    'cleanup-direct-image',
    'pending_upload',
    'not_started',
    null,
    now() - interval '2 hours'
  ),
  (
    '9f000000-0000-4000-8000-000000000002',
    '9c000000-0000-4000-8000-000000000001',
    '9e000000-0000-4000-8000-000000000001',
    '9b000000-0000-4000-8000-000000000001',
    '9c000000-0000-4000-8000-000000000001/9b000000-0000-4000-8000-000000000001/9f000000-0000-4000-8000-000000000002',
    'image/jpeg',
    2048,
    'cleanup-attached-image',
    'ready',
    'passed',
    now() - interval '2 days',
    now() - interval '2 days'
  ),
  (
    '9f000000-0000-4000-8000-000000000003',
    '9c000000-0000-4000-8000-000000000001',
    null,
    '9b000000-0000-4000-8000-000000000001',
    '9c000000-0000-4000-8000-000000000001/9b000000-0000-4000-8000-000000000001/9f000000-0000-4000-8000-000000000003',
    'image/jpeg',
    2048,
    'cleanup-review-image',
    'pending_review',
    'needs_review',
    null,
    now() - interval '2 days'
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
  scan_status,
  reviewed_at,
  created_at
)
values (
  'a0000000-0000-4000-8000-000000000001',
  '9d000000-0000-4000-8000-000000000001',
  '9b000000-0000-4000-8000-000000000001',
  '9d000000-0000-4000-8000-000000000001/9b000000-0000-4000-8000-000000000001/a0000000-0000-4000-8000-000000000001',
  'image/jpeg',
  2048,
  'cloudflare_images',
  'cleanup-group-image',
  'ready',
  'passed',
  now() - interval '2 days',
  now() - interval '2 days'
);

set local role service_role;

do $$
declare
  claimed_id uuid;
  asset_id text;
begin
  select result.attachment_id, result.provider_asset_id
  into claimed_id, asset_id
  from public.claim_expired_community_media_attachments('direct', 10) as result;

  if claimed_id <> '9f000000-0000-4000-8000-000000000001'
     or asset_id <> 'cleanup-direct-image' then
    raise exception 'expired unattached direct media was not claimed';
  end if;
end $$;

do $$
declare
  current_status text;
begin
  select status into current_status
  from public.community_direct_message_attachments
  where id = '9f000000-0000-4000-8000-000000000001';
  if current_status <> 'deleted' then
    raise exception 'claimed direct media was not marked for deletion';
  end if;
end $$;

do $$
begin
  if not public.finalize_community_media_cleanup(
    'direct',
    '9f000000-0000-4000-8000-000000000001'
  ) then
    raise exception 'direct media cleanup was not finalized';
  end if;
end $$;

do $$
declare
  claimed_id uuid;
  asset_id text;
begin
  select result.attachment_id, result.provider_asset_id
  into claimed_id, asset_id
  from public.claim_expired_community_media_attachments('group', 10) as result;

  if claimed_id <> 'a0000000-0000-4000-8000-000000000001'
     or asset_id <> 'cleanup-group-image' then
    raise exception 'expired unattached group media was not claimed';
  end if;
end $$;

do $$
begin
  if not public.finalize_community_media_cleanup(
    'group',
    'a0000000-0000-4000-8000-000000000001'
  ) then
    raise exception 'group media cleanup was not finalized';
  end if;
end $$;

do $$
declare
  attached_status text;
  review_status text;
begin
  select status into attached_status
  from public.community_direct_message_attachments
  where id = '9f000000-0000-4000-8000-000000000002';
  select status into review_status
  from public.community_direct_message_attachments
  where id = '9f000000-0000-4000-8000-000000000003';
  if attached_status <> 'ready' then
    raise exception 'cleanup changed attached media';
  end if;
  if review_status <> 'pending_review' then
    raise exception 'cleanup changed review-pending media';
  end if;
end $$;

reset role;
rollback;
