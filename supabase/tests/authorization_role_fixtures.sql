-- Deterministic authorization fixtures for the community role matrix.
-- Run against a disposable migrated database as its owner. Everything rolls back.
begin;

-- Fixture identities:
-- owner, admin, group moderator, member, managed member, follower, stranger,
-- blocked user, and platform moderator.
insert into auth.users(id)
values
  ('91000000-0000-4000-8000-000000000001'),
  ('91000000-0000-4000-8000-000000000002'),
  ('91000000-0000-4000-8000-000000000003'),
  ('91000000-0000-4000-8000-000000000004'),
  ('91000000-0000-4000-8000-000000000005'),
  ('91000000-0000-4000-8000-000000000006'),
  ('91000000-0000-4000-8000-000000000007'),
  ('91000000-0000-4000-8000-000000000008'),
  ('91000000-0000-4000-8000-000000000009');

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
  ('91000000-0000-4000-8000-000000000001', 'Fixture Owner', 'fixture_owner', 'en', 'resident', true, 'active'),
  ('91000000-0000-4000-8000-000000000002', 'Fixture Admin', 'fixture_admin', 'en', 'resident', true, 'active'),
  ('91000000-0000-4000-8000-000000000003', 'Fixture Group Moderator', 'fixture_group_moderator', 'en', 'resident', true, 'active'),
  ('91000000-0000-4000-8000-000000000004', 'Fixture Member', 'fixture_member', 'en', 'resident', true, 'active'),
  ('91000000-0000-4000-8000-000000000005', 'Fixture Managed Member', 'fixture_managed_member', 'en', 'resident', true, 'active'),
  ('91000000-0000-4000-8000-000000000006', 'Fixture Follower', 'fixture_follower', 'en', 'resident', true, 'active'),
  ('91000000-0000-4000-8000-000000000007', 'Fixture Stranger', 'fixture_stranger', 'en', 'resident', true, 'active'),
  ('91000000-0000-4000-8000-000000000008', 'Fixture Blocked User', 'fixture_blocked', 'en', 'resident', true, 'active'),
  ('91000000-0000-4000-8000-000000000009', 'Fixture Platform Moderator', 'fixture_platform_moderator', 'en', 'resident', true, 'active');

select set_config('request.jwt.claim.sub', '91000000-0000-4000-8000-000000000001', true);

insert into public.community_groups(
  id,
  name,
  slug,
  description,
  scope,
  visibility,
  created_by,
  moderation_state
)
values
  (
    '92000000-0000-4000-8000-000000000001',
    'Fixture Public Group',
    'fixture-public-group',
    'A public authorization fixture group.',
    'interest',
    'public',
    '91000000-0000-4000-8000-000000000001',
    'active'
  ),
  (
    '92000000-0000-4000-8000-000000000002',
    'Fixture Approval Group',
    'fixture-approval-group',
    'An approval-required authorization fixture group.',
    'interest',
    'approval_required',
    '91000000-0000-4000-8000-000000000001',
    'active'
  );

insert into public.community_group_memberships(group_id, user_id, role)
values
  ('92000000-0000-4000-8000-000000000001', '91000000-0000-4000-8000-000000000001', 'owner'),
  ('92000000-0000-4000-8000-000000000001', '91000000-0000-4000-8000-000000000002', 'admin'),
  ('92000000-0000-4000-8000-000000000001', '91000000-0000-4000-8000-000000000003', 'moderator'),
  ('92000000-0000-4000-8000-000000000001', '91000000-0000-4000-8000-000000000004', 'member'),
  ('92000000-0000-4000-8000-000000000001', '91000000-0000-4000-8000-000000000005', 'member'),
  ('92000000-0000-4000-8000-000000000002', '91000000-0000-4000-8000-000000000001', 'owner'),
  ('92000000-0000-4000-8000-000000000002', '91000000-0000-4000-8000-000000000002', 'admin');

insert into public.community_follows(follower_id, following_id)
values ('91000000-0000-4000-8000-000000000006', '91000000-0000-4000-8000-000000000001');

insert into public.user_blocks(blocker_id, blocked_user_id)
values ('91000000-0000-4000-8000-000000000001', '91000000-0000-4000-8000-000000000008');

insert into public.community_group_join_requests(group_id, user_id, status)
values ('92000000-0000-4000-8000-000000000002', '91000000-0000-4000-8000-000000000007', 'pending');

insert into public.community_posts(id, author_id, title, body, kind)
values (
  '93000000-0000-4000-8000-000000000001',
  '91000000-0000-4000-8000-000000000001',
  'Fixture post',
  'Fixture post body.',
  'update'
);

insert into public.community_reports(id, reporter_id, target_type, target_id, reason)
values (
  '94000000-0000-4000-8000-000000000001',
  '91000000-0000-4000-8000-000000000007',
  'post',
  '93000000-0000-4000-8000-000000000001',
  'Fixture report'
);

insert into public.community_moderator_roles(user_id, role)
values ('91000000-0000-4000-8000-000000000009', 'moderator');

insert into public.community_member_restrictions(user_id, scope)
values ('91000000-0000-4000-8000-000000000005', 'posting');

set local role authenticated;

-- Owner: sees own public projection, belongs to the group, and can manage it.
select set_config('request.jwt.claim.sub', '91000000-0000-4000-8000-000000000001', true);
do $$
begin
  if not exists (
    select 1 from public.community_public_profiles
    where user_id = '91000000-0000-4000-8000-000000000001'
  ) then
    raise exception 'owner fixture cannot see own public profile';
  end if;
  if not public.is_community_group_member('92000000-0000-4000-8000-000000000001') then
    raise exception 'owner fixture is not a group member';
  end if;
  if not public.can_manage_community_group('92000000-0000-4000-8000-000000000001') then
    raise exception 'owner fixture cannot manage group';
  end if;

  perform public.manage_community_group_member(
    '92000000-0000-4000-8000-000000000001',
    '91000000-0000-4000-8000-000000000005',
    'set_role',
    'moderator'
  );

  if not exists (
    select 1 from public.community_group_memberships
    where group_id = '92000000-0000-4000-8000-000000000001'
      and user_id = '91000000-0000-4000-8000-000000000005'
      and role = 'moderator'
  ) then
    raise exception 'owner fixture could not manage a member role';
  end if;

  if public.is_community_member_posting_restricted(
    '91000000-0000-4000-8000-000000000005'
  ) then
    raise exception 'posting restriction helper exposed another member state';
  end if;
end $$;

select set_config('request.jwt.claim.sub', '91000000-0000-4000-8000-000000000005', true);
do $$
begin
  if not public.is_community_member_posting_restricted(
    '91000000-0000-4000-8000-000000000005'
  ) then
    raise exception 'posting restriction helper missed current member state';
  end if;
  if public.is_community_member_posting_restricted(
    '91000000-0000-4000-8000-000000000001'
  ) then
    raise exception 'posting restriction helper accepted a non-actor target';
  end if;
end $$;

-- Stranger: can see public profile data, but not a private group roster.
select set_config('request.jwt.claim.sub', '91000000-0000-4000-8000-000000000007', true);
do $$
begin
  if not exists (
    select 1 from public.community_public_profiles
    where user_id = '91000000-0000-4000-8000-000000000001'
  ) then
    raise exception 'stranger fixture cannot see public profile';
  end if;
  if exists (
    select 1 from public.community_group_memberships
    where group_id = '92000000-0000-4000-8000-000000000001'
  ) then
    raise exception 'stranger fixture can see group roster';
  end if;
end $$;

-- Follower: can read the target's visible follower list under the default policy.
select set_config('request.jwt.claim.sub', '91000000-0000-4000-8000-000000000006', true);
do $$
begin
  if not exists (
    select 1
    from public.list_community_follow_profiles(
      '91000000-0000-4000-8000-000000000001',
      'followers'
    )
    where user_id = '91000000-0000-4000-8000-000000000006'
  ) then
    raise exception 'follower fixture cannot read visible follower list';
  end if;
end $$;

-- Blocked user: the owner's public profile and posts are hidden in both paths.
select set_config('request.jwt.claim.sub', '91000000-0000-4000-8000-000000000008', true);
do $$
begin
  if exists (
    select 1 from public.community_public_profiles
    where user_id = '91000000-0000-4000-8000-000000000001'
  ) then
    raise exception 'blocked fixture can see owner public profile';
  end if;
  if exists (
    select 1 from public.community_posts
    where id = '93000000-0000-4000-8000-000000000001'
  ) then
    raise exception 'blocked fixture can see owner post';
  end if;
end $$;

-- Group member: can see the group roster but cannot manage roles.
select set_config('request.jwt.claim.sub', '91000000-0000-4000-8000-000000000004', true);
do $$
begin
  if not public.is_community_group_member('92000000-0000-4000-8000-000000000001') then
    raise exception 'member fixture is not recognized as group member';
  end if;
  if (select count(*) from public.community_group_memberships where group_id = '92000000-0000-4000-8000-000000000001') <> 5 then
    raise exception 'member fixture cannot read group roster';
  end if;

  begin
    perform public.manage_community_group_member(
      '92000000-0000-4000-8000-000000000001',
      '91000000-0000-4000-8000-000000000005',
      'remove',
      null
    );
    raise exception 'member fixture managed a group member';
  exception when others then
    if position('insufficient group permission' in sqlerrm) = 0 then
      raise;
    end if;
  end;
end $$;

-- Group admin: can review pending join requests.
select set_config('request.jwt.claim.sub', '91000000-0000-4000-8000-000000000002', true);
do $$
begin
  if not public.can_manage_community_group('92000000-0000-4000-8000-000000000001') then
    raise exception 'admin fixture cannot manage group';
  end if;
  if not exists (
    select 1
    from public.list_community_group_join_requests('92000000-0000-4000-8000-000000000002')
    where user_id = '91000000-0000-4000-8000-000000000007'
  ) then
    raise exception 'admin fixture cannot read pending join request';
  end if;
end $$;

-- Group moderator: can be recognized as staff, but cannot change membership roles.
select set_config('request.jwt.claim.sub', '91000000-0000-4000-8000-000000000003', true);
do $$
begin
  if not public.can_manage_community_group('92000000-0000-4000-8000-000000000001') then
    raise exception 'group moderator fixture is not recognized as staff';
  end if;

  begin
    perform public.manage_community_group_member(
      '92000000-0000-4000-8000-000000000001',
      '91000000-0000-4000-8000-000000000004',
      'remove',
      null
    );
    raise exception 'group moderator fixture managed a member';
  exception when others then
    if position('insufficient group permission' in sqlerrm) = 0 then
      raise;
    end if;
  end;
end $$;

-- Platform moderator: the fixture is consumed by the server-only review RPC.
-- Its execute boundary is asserted by security_definer_grants.sql.
select set_config('request.jwt.claim.sub', '91000000-0000-4000-8000-000000000009', true);

set local role service_role;
select set_config('request.jwt.claim.role', 'service_role', true);
select public.resolve_community_report(
  '94000000-0000-4000-8000-000000000001',
  '91000000-0000-4000-8000-000000000009',
  'resolved',
  'no_action',
  'Fixture review'
);

reset role;
do $$
begin
  if not exists (
    select 1 from public.community_reports
    where id = '94000000-0000-4000-8000-000000000001'
      and review_status = 'resolved'
      and reviewed_by = '91000000-0000-4000-8000-000000000009'
  ) then
    raise exception 'platform moderator fixture did not resolve report';
  end if;
  if not exists (
    select 1 from public.community_moderation_review_audit
    where report_id = '94000000-0000-4000-8000-000000000001'
      and moderator_id = '91000000-0000-4000-8000-000000000009'
  ) then
    raise exception 'platform moderator audit fixture is missing';
  end if;
end $$;

rollback;
