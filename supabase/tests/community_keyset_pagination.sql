-- Run against a disposable migrated database as its owner. Everything rolls back.
begin;

insert into auth.users(id) values
  ('80000000-0000-4000-8000-000000000001'),
  ('80000000-0000-4000-8000-000000000002');

insert into public.community_profiles(user_id, display_name, username, preferred_locale, norway_status)
values
  ('80000000-0000-4000-8000-000000000001', 'Cursor viewer', 'cursor_viewer', 'en', 'resident'),
  ('80000000-0000-4000-8000-000000000002', 'Cursor author', 'cursor_author', 'en', 'resident');

insert into public.community_posts(id, author_id, title, body, created_at)
values
  ('80000000-0000-4000-8000-000000000011', '80000000-0000-4000-8000-000000000002', 'Newest', 'Newest body', '2026-09-11 00:02:00+00'),
  ('80000000-0000-4000-8000-000000000012', '80000000-0000-4000-8000-000000000002', 'Middle', 'Middle body', '2026-09-11 00:01:00+00'),
  ('80000000-0000-4000-8000-000000000013', '80000000-0000-4000-8000-000000000002', 'Oldest', 'Oldest body', '2026-09-11 00:00:00+00');

set local role authenticated;
select set_config('request.jwt.claim.sub', '80000000-0000-4000-8000-000000000001', true);

do $$
declare
  first_id uuid;
  next_cursor text;
  second_id uuid;
begin
  select (page.post->>'id')::uuid, page.next_cursor
    into first_id, next_cursor
  from public.list_community_feed_page(null, 1) as page;

  if first_id <> '80000000-0000-4000-8000-000000000011' or next_cursor is null then
    raise exception 'first keyset page did not return the newest row and cursor';
  end if;

  select (page.post->>'id')::uuid
    into second_id
  from public.list_community_feed_page(next_cursor, 1) as page;

  if second_id <> '80000000-0000-4000-8000-000000000012' then
    raise exception 'keyset cursor repeated or skipped the next feed row';
  end if;
end $$;

reset role;
rollback;
