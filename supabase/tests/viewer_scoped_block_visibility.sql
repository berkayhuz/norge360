-- Run against a disposable migrated database as its owner. Everything rolls back.
begin;

do $$
declare
  feed_definition text;
  profile_view_definition text;
begin
  select pg_get_functiondef(
    'public.list_community_feed_page(text,integer)'::regprocedure
  )
    into feed_definition;

  if position('blocked_users as materialized' in lower(feed_definition)) = 0 then
    raise exception 'feed RPC does not materialize the viewer-scoped blocked set';
  end if;

  if position('can_view_community_user' in lower(feed_definition)) > 0 then
    raise exception 'feed RPC still performs per-row block helper calls';
  end if;

  select pg_get_viewdef(
    'public.community_public_profiles'::regclass,
    true
  )
    into profile_view_definition;

  if position('blocked_users as materialized' in lower(profile_view_definition)) = 0 then
    raise exception 'public profile projection does not materialize the viewer-scoped blocked set';
  end if;

  if position('can_view_community_user' in lower(profile_view_definition)) > 0 then
    raise exception 'public profile projection still performs per-row block helper calls';
  end if;

  if not exists (
    select 1
    from pg_indexes
    where schemaname = 'public'
      and indexname = 'user_blocks_blocked_blocker_index'
  ) then
    raise exception 'reverse block index is missing';
  end if;
end $$;

insert into auth.users(id) values
  ('81000000-0000-4000-8000-000000000001'),
  ('81000000-0000-4000-8000-000000000002'),
  ('81000000-0000-4000-8000-000000000003');

insert into public.community_profiles(user_id, display_name, username, preferred_locale, norway_status)
values
  ('81000000-0000-4000-8000-000000000001', 'Viewer', 'viewer_block_test', 'en', 'resident'),
  ('81000000-0000-4000-8000-000000000002', 'Visible Author', 'visible_block_test', 'en', 'resident'),
  ('81000000-0000-4000-8000-000000000003', 'Blocked Author', 'blocked_block_test', 'en', 'resident');

insert into public.community_posts(id, author_id, title, body, created_at)
values
  ('81000000-0000-4000-8000-000000000011', '81000000-0000-4000-8000-000000000002', 'Visible', 'Visible body', '2026-09-11 00:02:00+00'),
  ('81000000-0000-4000-8000-000000000012', '81000000-0000-4000-8000-000000000003', 'Blocked', 'Blocked body', '2026-09-11 00:01:00+00');

insert into public.user_blocks(blocker_id, blocked_user_id)
values ('81000000-0000-4000-8000-000000000001', '81000000-0000-4000-8000-000000000003');

set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-4000-8000-000000000001', true);

do $$
declare
  feed_count integer;
  profile_count integer;
begin
  select count(*) into feed_count
  from public.list_community_feed_page(null, 20);

  select count(*) into profile_count
  from public.community_public_profiles
  where username = 'blocked_block_test';

  if feed_count <> 1 or profile_count <> 0 then
    raise exception 'viewer-scoped block visibility leaked blocked content';
  end if;
end $$;

reset role;
rollback;
