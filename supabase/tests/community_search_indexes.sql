-- Run against a disposable, fully migrated database as its owner.
-- This verifies that DB-003 keeps search RPCs indexable without changing
-- their bounded result limits or security-invoker contract.
begin;

do $$
declare
  expected record;
  index_definition text;
  function_source text;
begin
  if not exists (select 1 from pg_extension where extname = 'pg_trgm') then
    raise exception 'pg_trgm extension is missing';
  end if;

  for expected in
    select * from (values
      ('community_profiles_display_name_trgm_index', 'lower(display_name)'),
      ('community_profiles_username_trgm_index', 'lower(username)'),
      ('community_profiles_username_prefix_index', 'lower(username)'),
      ('community_groups_name_trgm_index', 'lower(name)'),
      ('community_groups_slug_trgm_index', 'lower(slug)'),
      ('community_posts_body_trgm_index', 'lower(body)')
    ) as indexes(index_name, expected_expression)
  loop
    select pg_get_indexdef(to_regclass('public.' || expected.index_name))
      into index_definition;

    if index_definition is null
       or position(expected.expected_expression in lower(index_definition)) = 0 then
      raise exception 'DB-003 index % has unexpected definition: %',
        expected.index_name, coalesce(index_definition, '<missing>');
    end if;
  end loop;

  for expected in
    select * from (values
      ('public.search_community_profiles(text)'::regprocedure, 'lower(profile.display_name) like'),
      ('public.search_community_groups(text)'::regprocedure, 'lower(community_group.name) like'),
      ('public.search_community_posts(text)'::regprocedure, 'lower(post.body) like'),
      ('public.search_community_post_results(text)'::regprocedure, 'lower(community_post.body) like')
    ) as functions(function_name, expected_predicate)
  loop
    select lower(pg_get_functiondef(expected.function_name))
      into function_source;

    if position(expected.expected_predicate in function_source) = 0 then
      raise exception 'DB-003 function % is not using the indexed predicate %',
        expected.function_name, expected.expected_predicate;
    end if;
  end loop;
end $$;

rollback;
