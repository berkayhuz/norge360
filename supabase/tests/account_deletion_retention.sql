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
      and confdeltype = 'r'
  ) then
    raise exception 'an auth.users foreign key still blocks account deletion';
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
    where report_id = '97000000-0000-4000-8000-000000000020' and moderator_id is not null
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

reset role;
rollback;
