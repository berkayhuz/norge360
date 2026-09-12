-- Run against a disposable migrated database as its owner. Everything rolls back.
begin;

insert into auth.users(id) values
  ('70000000-0000-4000-8000-000000000001'),
  ('70000000-0000-4000-8000-000000000002'),
  ('70000000-0000-4000-8000-000000000003'),
  ('70000000-0000-4000-8000-000000000004');

insert into public.community_profiles(
  user_id, display_name, username, preferred_locale, norway_status
) values
  ('70000000-0000-4000-8000-000000000001', 'Viewer', 'comments_viewer', 'en', 'resident'),
  ('70000000-0000-4000-8000-000000000002', 'Post author', 'comments_post_author', 'en', 'resident'),
  ('70000000-0000-4000-8000-000000000003', 'Comment author', 'comments_author', 'en', 'resident'),
  ('70000000-0000-4000-8000-000000000004', 'Blocked author', 'comments_blocked', 'en', 'resident');

insert into public.community_posts(id, author_id, title, body)
values (
  '70000000-0000-4000-8000-000000000010',
  '70000000-0000-4000-8000-000000000002',
  'A visible post',
  'A visible post body'
);

insert into public.community_comments(id, post_id, author_id, body)
values
  (
    '70000000-0000-4000-8000-000000000011',
    '70000000-0000-4000-8000-000000000010',
    '70000000-0000-4000-8000-000000000003',
    'A visible comment'
  ),
  (
    '70000000-0000-4000-8000-000000000012',
    '70000000-0000-4000-8000-000000000010',
    '70000000-0000-4000-8000-000000000004',
    'A blocked comment'
  );

insert into public.user_blocks(blocker_id, blocked_user_id)
values (
  '70000000-0000-4000-8000-000000000001',
  '70000000-0000-4000-8000-000000000004'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '70000000-0000-4000-8000-000000000001', true);

do $$
declare
  returned_count integer;
  returned_body text;
  returned_username text;
begin
  select count(*)::integer, max(comment->>'body'), max(author->>'username')
    into returned_count, returned_body, returned_username
  from public.list_community_post_comments(
    '70000000-0000-4000-8000-000000000010'
  );

  if returned_count <> 1
    or returned_body <> 'A visible comment'
    or returned_username <> 'comments_author' then
    raise exception 'comment RPC returned hidden, unrelated, or incomplete rows';
  end if;
end $$;

reset role;
rollback;
