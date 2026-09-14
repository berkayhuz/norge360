-- Group-scoped content must follow group visibility, including read-only RPCs
-- and storage-adjacent media projections. Run against a disposable migrated DB.
begin;

insert into auth.users(id)
values
  ('82000000-0000-4000-8000-000000000001'),
  ('82000000-0000-4000-8000-000000000002'),
  ('82000000-0000-4000-8000-000000000003')
on conflict (id) do nothing;

insert into public.community_profiles(user_id, display_name, username, preferred_locale, norway_status)
values
  ('82000000-0000-4000-8000-000000000001', 'Group owner', 'group_visibility_owner', 'en', 'resident'),
  ('82000000-0000-4000-8000-000000000002', 'Group member', 'group_visibility_member', 'en', 'resident'),
  ('82000000-0000-4000-8000-000000000003', 'Group stranger', 'group_visibility_stranger', 'en', 'resident')
on conflict (user_id) do nothing;

insert into public.community_groups(
  id, name, slug, description, scope, visibility, created_by, moderation_state
)
values
  (
    '82000000-0000-4000-8000-000000000011', 'Approval visibility fixture',
    'approval-visibility-fixture', 'Approval visibility fixture group.', 'interest',
    'approval_required', '82000000-0000-4000-8000-000000000001', 'active'
  ),
  (
    '82000000-0000-4000-8000-000000000012', 'Private visibility fixture',
    'private-visibility-fixture', 'Private visibility fixture group.', 'interest',
    '82000000-0000-4000-8000-000000000001', 'active'
  )
on conflict (id) do nothing;

insert into public.community_group_memberships(group_id, user_id, role)
values
  ('82000000-0000-4000-8000-000000000011', '82000000-0000-4000-8000-000000000001', 'owner'),
  ('82000000-0000-4000-8000-000000000011', '82000000-0000-4000-8000-000000000002', 'member'),
  ('82000000-0000-4000-8000-000000000012', '82000000-0000-4000-8000-000000000001', 'owner'),
  ('82000000-0000-4000-8000-000000000012', '82000000-0000-4000-8000-000000000002', 'member')
on conflict (group_id, user_id) do nothing;

insert into public.community_posts(id, author_id, group_id, title, body, kind)
values
  ('82000000-0000-4000-8000-000000000021', '82000000-0000-4000-8000-000000000001', '82000000-0000-4000-8000-000000000011', 'Approval post', 'Approval post body', 'update'),
  ('82000000-0000-4000-8000-000000000022', '82000000-0000-4000-8000-000000000001', '82000000-0000-4000-8000-000000000012', 'Private post', 'Private post body', 'update');

set local role authenticated;
select set_config('request.jwt.claim.sub', '82000000-0000-4000-8000-000000000003', true);

do $$
declare
  visible_count integer;
begin
  select count(*) into visible_count
  from public.community_posts
  where id in (
    '82000000-0000-4000-8000-000000000021',
    '82000000-0000-4000-8000-000000000022'
  );

  if visible_count <> 0 then
    raise exception 'non-member can read approval/private group content';
  end if;

  if public.can_view_community_group('82000000-0000-4000-8000-000000000011')
     or public.can_view_community_group('82000000-0000-4000-8000-000000000012') then
    raise exception 'non-member group visibility helper granted content access';
  end if;

  if exists (
    select 1
    from public.list_community_feed_page(null, 20) as page
    where (page.post ->> 'id') in (
      '82000000-0000-4000-8000-000000000021',
      '82000000-0000-4000-8000-000000000022'
    )
  ) then
    raise exception 'feed RPC leaked approval/private group content';
  end if;
end $$;

select set_config('request.jwt.claim.sub', '82000000-0000-4000-8000-000000000002', true);

do $$
declare
  visible_count integer;
begin
  select count(*) into visible_count
  from public.community_posts
  where id in (
    '82000000-0000-4000-8000-000000000021',
    '82000000-0000-4000-8000-000000000022'
  );

  if visible_count <> 2 then
    raise exception 'member cannot read accepted approval/private group content';
  end if;

  if not public.can_view_community_group('82000000-0000-4000-8000-000000000011')
     or not public.can_view_community_group('82000000-0000-4000-8000-000000000012') then
    raise exception 'member group visibility helper denied accepted content';
  end if;
end $$;

reset role;
rollback;
