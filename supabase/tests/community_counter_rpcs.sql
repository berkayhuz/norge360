-- Run against a disposable migrated database as its owner. Everything rolls back.
begin;

do $$
declare
  post_function_definition text;
  event_function_definition text;
begin
  select pg_get_functiondef(function_row.oid)
    into post_function_definition
  from pg_proc as function_row
  join pg_namespace as namespace_row on namespace_row.oid = function_row.pronamespace
  where namespace_row.nspname = 'public'
    and function_row.proname = 'list_community_post_counters'
    and function_row.pronargs = 1
    and function_row.proargtypes[0] = 'uuid[]'::regtype;

  select pg_get_functiondef(function_row.oid)
    into event_function_definition
  from pg_proc as function_row
  join pg_namespace as namespace_row on namespace_row.oid = function_row.pronamespace
  where namespace_row.nspname = 'public'
    and function_row.proname = 'list_community_event_counters'
    and function_row.pronargs = 1
    and function_row.proargtypes[0] = 'uuid[]'::regtype;

  if post_function_definition is null
    or event_function_definition is null then
    raise exception 'community counter RPC definition is missing';
  end if;

  if position('requested_posts' in lower(post_function_definition)) = 0
    or position('like_counts' in lower(post_function_definition)) = 0
    or position('comment_counts' in lower(post_function_definition)) = 0
    or position('history_counts' in lower(post_function_definition)) = 0
    or position('[1:100]' in lower(post_function_definition)) = 0
    or position('exists (' in lower(post_function_definition)) = 0
    or position('auth.uid()' in lower(post_function_definition)) = 0 then
    raise exception 'post counter RPC must aggregate counts and current-user state in PostgreSQL';
  end if;

  if position('requested_events' in lower(event_function_definition)) = 0
    or position('like_counts' in lower(event_function_definition)) = 0
    or position('[1:100]' in lower(event_function_definition)) = 0
    or position('exists (' in lower(event_function_definition)) = 0
    or position('auth.uid()' in lower(event_function_definition)) = 0 then
    raise exception 'event counter RPC must aggregate counts and current-user state in PostgreSQL';
  end if;

  if position('security definer' in lower(post_function_definition)) > 0
    or position('security definer' in lower(event_function_definition)) > 0 then
    raise exception 'counter RPCs must remain security invoker so RLS applies to the caller';
  end if;
end $$;

rollback;
