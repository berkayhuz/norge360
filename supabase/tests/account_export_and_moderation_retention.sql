-- Run against a disposable fully migrated database as its owner.
begin;

do $$
begin
  if not has_function_privilege(
    'service_role',
    'public.export_community_account_data(uuid)',
    'EXECUTE'
  ) or not has_function_privilege(
    'service_role',
    'public.export_community_account_metadata(uuid)',
    'EXECUTE'
  ) or not has_function_privilege(
    'service_role',
    'public.export_community_account_section(uuid, text, integer, integer)',
    'EXECUTE'
  ) or not has_function_privilege(
    'service_role',
    'public.purge_community_moderation_retention(integer)',
    'EXECUTE'
  ) then
    raise exception 'service_role cannot execute account export or retention purge';
  end if;
  if has_function_privilege(
    'authenticated',
    'public.export_community_account_data(uuid)',
    'EXECUTE'
  ) or has_function_privilege(
    'anon',
    'public.export_community_account_data(uuid)',
    'EXECUTE'
  ) or has_function_privilege(
    'authenticated',
    'public.export_community_account_metadata(uuid)',
    'EXECUTE'
  ) or has_function_privilege(
    'anon',
    'public.export_community_account_metadata(uuid)',
    'EXECUTE'
  ) or has_function_privilege(
    'authenticated',
    'public.export_community_account_section(uuid, text, integer, integer)',
    'EXECUTE'
  ) or has_function_privilege(
    'anon',
    'public.export_community_account_section(uuid, text, integer, integer)',
    'EXECUTE'
  ) then
    raise exception 'client roles can execute account export';
  end if;
end $$;

insert into auth.users(id, email)
values
  ('98000000-0000-4000-8000-000000000001', 'export-owner@example.test'),
  ('98000000-0000-4000-8000-000000000002', 'export-target@example.test');

insert into public.community_profiles(user_id, display_name, preferred_locale, norway_status, username)
values
  ('98000000-0000-4000-8000-000000000001', 'Export Owner', 'en', 'resident', 'exportowner'),
  ('98000000-0000-4000-8000-000000000002', 'Export Target', 'en', 'resident', 'exporttarget');

insert into public.user_account_profiles(user_id, preferred_locale)
values ('98000000-0000-4000-8000-000000000001', 'en');

insert into public.user_relocation_plans(user_id, plan)
values ('98000000-0000-4000-8000-000000000001', '{"status":"active"}'::jsonb);

insert into public.community_posts(author_id, title, body, kind)
values ('98000000-0000-4000-8000-000000000001', 'Export fixture', 'Export fixture body', 'update');

insert into public.community_push_devices(user_id, token, environment)
values ('98000000-0000-4000-8000-000000000001', repeat('b', 64), 'development');

insert into public.user_blocks(blocker_id, blocked_user_id)
values
  (
    '98000000-0000-4000-8000-000000000001',
    '98000000-0000-4000-8000-000000000002'
  ),
  (
    '98000000-0000-4000-8000-000000000002',
    '98000000-0000-4000-8000-000000000001'
  );

select set_config(
  'request.jwt.claim.sub',
  '98000000-0000-4000-8000-000000000001',
  true
);

insert into public.community_reports(
  id, reporter_id, target_type, target_id, reason, review_status, reviewed_at
)
values
  (
    '98000000-0000-4000-8000-000000000010',
    '98000000-0000-4000-8000-000000000001',
    'profile',
    '98000000-0000-4000-8000-000000000002',
    'old report',
    'resolved',
    now() - interval '13 months'
  ),
  (
    '98000000-0000-4000-8000-000000000011',
    '98000000-0000-4000-8000-000000000001',
    'profile',
    '98000000-0000-4000-8000-000000000002',
    'open report',
    'open',
    null
  );

insert into public.community_moderation_action_audit(
  report_id, moderator_id, action, target_type, target_id, created_at
)
values (
  '98000000-0000-4000-8000-000000000010',
  '98000000-0000-4000-8000-000000000001',
  'content_removed',
  'profile',
  '98000000-0000-4000-8000-000000000002',
  now() - interval '13 months'
);

insert into public.community_moderation_review_audit(
  report_id, moderator_id, previous_status, next_status, action, created_at
)
values (
  '98000000-0000-4000-8000-000000000010',
  '98000000-0000-4000-8000-000000000001',
  'open',
  'resolved',
  'no_action',
  now() - interval '13 months'
);

insert into public.community_groups(id, name, slug, description, scope, visibility, created_by)
values (
  '98000000-0000-4000-8000-000000000020',
  'Retention fixture group',
  'retention-fixture-group',
  'A disposable group used for retention tests.',
  'interest',
  'public',
  '98000000-0000-4000-8000-000000000001'
);

insert into public.community_group_moderation_audit(
  group_id, actor_id, target_user_id, action, created_at
)
values (
  '98000000-0000-4000-8000-000000000020',
  '98000000-0000-4000-8000-000000000001',
  '98000000-0000-4000-8000-000000000002',
  'ban',
  now() - interval '13 months'
);

set local role service_role;
select set_config('request.jwt.claim.role', 'service_role', true);

do $$
declare
  export_document jsonb;
  export_metadata jsonb;
  export_page record;
begin
  export_document := public.export_community_account_data('98000000-0000-4000-8000-000000000001');
  export_metadata := public.export_community_account_metadata('98000000-0000-4000-8000-000000000001');
  select * into export_page
  from public.export_community_account_section(
    '98000000-0000-4000-8000-000000000001', 'posts', 0, 1
  );
  if export_document->>'schema_version' <> '1'
     or jsonb_array_length(export_document->'posts') <> 1
     or jsonb_array_length(export_document->'blocks') <> 1
     or export_document->'blocks'->0->>'blocker_id' <> '98000000-0000-4000-8000-000000000001'
     or export_document->'blocks'->0->>'blocked_user_id' <> '98000000-0000-4000-8000-000000000002'
     or export_document->'relocation_plan'->'plan'->>'status' <> 'active'
     or export_metadata->>'schema_version' <> '1'
     or jsonb_array_length(export_page.rows) <> 1
     or export_page.has_more then
    raise exception 'account export is missing expected member data';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(export_document->'blocks') as block
    where block->>'blocked_user_id' = '98000000-0000-4000-8000-000000000001'
  ) then
    raise exception 'account export leaked an incoming block relation';
  end if;
  if export_document::text like '%bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb%'
     or export_document::text like '%storage_reference%'
     or export_document::text like '%provider_asset_id%' then
    raise exception 'account export leaked operational media data';
  end if;
end $$;

select public.purge_community_moderation_retention(500);

do $$
begin
  if exists (select 1 from public.community_reports where id = '98000000-0000-4000-8000-000000000010')
     or exists (select 1 from public.community_moderation_action_audit where report_id = '98000000-0000-4000-8000-000000000010')
     or exists (select 1 from public.community_moderation_review_audit where report_id = '98000000-0000-4000-8000-000000000010')
     or exists (select 1 from public.community_group_moderation_audit where group_id = '98000000-0000-4000-8000-000000000020') then
    raise exception 'expired moderation retention was not purged';
  end if;
  if not exists (select 1 from public.community_reports where id = '98000000-0000-4000-8000-000000000011') then
    raise exception 'open moderation report was purged';
  end if;
end $$;

reset role;
rollback;
