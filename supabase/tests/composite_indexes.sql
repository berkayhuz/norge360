-- Run against a disposable, fully migrated database as its owner.
-- This verifies that every index added for DB-002 exists with the intended
-- column order. It changes no data and rolls back the surrounding transaction.
begin;

do $$
declare
  expected record;
  index_definition text;
begin
  for expected in
    select * from (values
      ('community_posts_author_created_id_index',
       'author_id, created_at DESC, id DESC'),
      ('community_comments_author_created_id_index',
       'author_id, created_at DESC, id DESC'),
      ('community_events_group_starts_id_index',
       'group_id, starts_at, id'),
      ('community_event_rsvps_user_event_index',
       'user_id, event_id'),
      ('community_group_memberships_user_group_index',
       'user_id, group_id'),
      ('user_blocks_blocked_blocker_index',
       'blocked_user_id, blocker_id'),
      ('community_post_likes_user_created_post_index',
       'user_id, created_at DESC, post_id')
    ) as indexes(index_name, expected_columns)
  loop
    select pg_get_indexdef(to_regclass(expected.index_name))
      into index_definition;

    if index_definition is null
       or position(expected.expected_columns in index_definition) = 0 then
      raise exception 'DB-002 index % has unexpected definition: %',
        expected.index_name, coalesce(index_definition, '<missing>');
    end if;
  end loop;
end $$;

rollback;
