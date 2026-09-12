-- Run against a disposable fully migrated database as its owner.
-- The RPC is intentionally executable only through the Worker service role.
begin;

do $$
begin
  if to_regprocedure('public.issue_community_media_view(text,uuid,uuid)') is null then
    raise exception
      'Missing prerequisite migration: 20260912090000_optimize_private_media_view_authorization.sql. Apply migrations in filename order before running this test.';
  end if;
end $$;

do $$
begin
  if has_function_privilege(
       'anon',
       'public.issue_community_media_view(text,uuid,uuid)',
       'execute'
     ) then
    raise exception 'anonymous role can execute private media view RPC';
  end if;
  if has_function_privilege(
       'authenticated',
       'public.issue_community_media_view(text,uuid,uuid)',
       'execute'
     ) then
    raise exception 'authenticated role can execute private media view RPC';
  end if;
  if not has_function_privilege(
       'service_role',
       'public.issue_community_media_view(text,uuid,uuid)',
       'execute'
     ) then
    raise exception 'service role cannot execute private media view RPC';
  end if;
end $$;

insert into auth.users(id) values
  ('91000000-0000-4000-8000-000000000001'),
  ('91000000-0000-4000-8000-000000000002'),
  ('91000000-0000-4000-8000-000000000003');

insert into public.community_conversations(
  id,
  participant_one_id,
  participant_two_id,
  requested_by_id,
  status
)
values (
  '92000000-0000-4000-8000-000000000001',
  '91000000-0000-4000-8000-000000000001',
  '91000000-0000-4000-8000-000000000002',
  '91000000-0000-4000-8000-000000000001',
  'active'
);

insert into public.community_conversation_members(conversation_id, user_id, status)
values
  ('92000000-0000-4000-8000-000000000001', '91000000-0000-4000-8000-000000000001', 'active'),
  ('92000000-0000-4000-8000-000000000001', '91000000-0000-4000-8000-000000000002', 'active');

insert into public.community_messages(id, conversation_id, sender_id, body)
values (
  '93000000-0000-4000-8000-000000000001',
  '92000000-0000-4000-8000-000000000001',
  '91000000-0000-4000-8000-000000000002',
  'private image'
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
  '94000000-0000-4000-8000-000000000001',
  '92000000-0000-4000-8000-000000000001',
  '93000000-0000-4000-8000-000000000001',
  '91000000-0000-4000-8000-000000000002',
  '92000000-0000-4000-8000-000000000001/91000000-0000-4000-8000-000000000002/94000000-0000-4000-8000-000000000001',
  'image/jpeg',
  2048,
  'private-image-rpc-test',
  'ready',
  'passed',
  now()
);

set local role service_role;

do $$
declare
  asset_id text;
  limited boolean;
begin
  select result.provider_asset_id, result.rate_limited
  into asset_id, limited
  from public.issue_community_media_view(
    'direct',
    '94000000-0000-4000-8000-000000000001',
    '91000000-0000-4000-8000-000000000001'
  ) as result;

  if asset_id <> 'private-image-rpc-test' or limited then
    raise exception 'authorized private media view was not issued';
  end if;
end $$;

reset role;

insert into public.user_blocks(blocker_id, blocked_user_id)
values (
  '91000000-0000-4000-8000-000000000001',
  '91000000-0000-4000-8000-000000000002'
);

set local role service_role;

do $$
begin
  if exists (
    select 1
    from public.issue_community_media_view(
      'direct',
      '94000000-0000-4000-8000-000000000001',
      '91000000-0000-4000-8000-000000000001'
    )
  ) then
    raise exception 'blocked member received a private media view authorization';
  end if;
end $$;

reset role;
rollback;
