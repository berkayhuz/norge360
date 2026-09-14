-- Keep abuse-prone authenticated RPCs bounded at the database boundary.
-- The client debounce remains useful for UX, but it is not a security limit.

create table if not exists public.community_request_rate_limits (
  user_id uuid not null references auth.users(id) on delete cascade,
  bucket text not null check (
    bucket ~ '^[a-z0-9_]{1,64}$'
  ),
  window_started_at timestamptz not null,
  request_count integer not null check (request_count between 0 and 10001),
  updated_at timestamptz not null default now(),
  primary key (user_id, bucket)
);

alter table public.community_request_rate_limits enable row level security;
revoke all on public.community_request_rate_limits from public, anon, authenticated;

drop trigger if exists community_account_deletion_guard
  on public.community_request_rate_limits;
create trigger community_account_deletion_guard
before insert or update or delete on public.community_request_rate_limits
for each row execute function public.reject_community_account_deletion_write();

create or replace function public.consume_community_request_rate_limit(
  target_bucket text,
  target_limit integer,
  target_window_seconds integer,
  target_user_id uuid default null
)
returns table (allowed boolean)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  actor_role text := coalesce(current_setting('request.jwt.claim.role', true), '');
  account_user_id uuid := coalesce(target_user_id, (select auth.uid()));
  current_window timestamptz := clock_timestamp();
  current_count integer;
begin
  if actor_role not in ('authenticated', 'service_role') then
    raise exception 'authenticated or service role required';
  end if;
  if account_user_id is null
     or (actor_role <> 'service_role' and account_user_id <> (select auth.uid())) then
    raise exception 'rate limit identity mismatch';
  end if;
  if target_bucket is null
     or target_bucket !~ '^[a-z0-9_]{1,64}$'
     or target_limit is null
     or target_limit not between 1 and 10000
     or target_window_seconds is null
     or target_window_seconds not between 1 and 86400 then
    raise exception 'invalid rate limit configuration';
  end if;

  insert into public.community_request_rate_limits(
    user_id,
    bucket,
    window_started_at,
    request_count
  )
  values (
    account_user_id,
    target_bucket,
    current_window,
    1
  )
  on conflict (user_id, bucket) do update
  set window_started_at = case
        when public.community_request_rate_limits.window_started_at
          < excluded.window_started_at - make_interval(secs => target_window_seconds)
          then excluded.window_started_at
        else public.community_request_rate_limits.window_started_at
      end,
      request_count = case
        when public.community_request_rate_limits.window_started_at
          < excluded.window_started_at - make_interval(secs => target_window_seconds)
          then 1
        else least(public.community_request_rate_limits.request_count + 1, target_limit + 1)
      end,
      updated_at = now()
  returning community_request_rate_limits.request_count into current_count;

  return query select current_count <= target_limit;
end;
$$;

revoke all on function public.consume_community_request_rate_limit(text, integer, integer, uuid)
  from public, anon;
grant execute on function public.consume_community_request_rate_limit(text, integer, integer, uuid)
  to authenticated, service_role;

-- Search RPCs are intentionally bounded independently. Explore makes three
-- parallel calls, so separate buckets avoid charging one interaction three
-- times while still stopping automated hammering of each expensive query.
create or replace function public.search_community_profiles(search_query text)
returns setof public.community_public_profiles
language sql
volatile
security invoker
set search_path = ''
as $$
  with rate as materialized (
    select quota.allowed
    from public.consume_community_request_rate_limit('search_profiles', 60, 60) as quota
  ), normalized as (
    select lower(
      btrim(replace(replace(replace(search_query, E'\\', ''), '%', ''), '_', ''))
    ) as value
  )
  select profile.*
  from public.community_public_profiles as profile, normalized, rate
  where rate.allowed
    and char_length(normalized.value) between 3 and 80
    and (
      lower(profile.display_name) like '%' || normalized.value || '%'
      or lower(profile.username) like '%' || normalized.value || '%'
    )
  order by
    case when lower(profile.username) like normalized.value || '%' then 0 else 1 end,
    profile.username asc
  limit 12;
$$;

create or replace function public.search_community_groups(search_query text)
returns setof public.community_groups
language sql
volatile
security invoker
set search_path = ''
as $$
  with rate as materialized (
    select quota.allowed
    from public.consume_community_request_rate_limit('search_groups', 60, 60) as quota
  ), normalized as (
    select lower(
      btrim(replace(replace(replace(search_query, E'\\', ''), '%', ''), '_', ''))
    ) as value
  )
  select community_group.*
  from public.community_groups as community_group, normalized, rate
  where rate.allowed
    and char_length(normalized.value) between 3 and 80
    and (
      lower(community_group.name) like '%' || normalized.value || '%'
      or lower(community_group.slug) like '%' || normalized.value || '%'
    )
  order by community_group.name asc
  limit 12;
$$;

create or replace function public.search_community_posts(search_query text)
returns setof public.community_posts
language sql
volatile
security invoker
set search_path = ''
as $$
  with rate as materialized (
    select quota.allowed
    from public.consume_community_request_rate_limit('search_posts', 60, 60) as quota
  ), normalized as (
    select lower(
      btrim(replace(replace(replace(search_query, E'\\', ''), '%', ''), '_', ''))
    ) as value
  )
  select post.*
  from public.community_posts as post, normalized, rate
  where rate.allowed
    and char_length(normalized.value) between 3 and 80
    and lower(post.body) like '%' || normalized.value || '%'
  order by post.created_at desc
  limit 20;
$$;

create or replace function public.search_community_hashtags(prefix text)
returns table (tag text, usage_count integer)
language sql
volatile
security definer
set search_path = ''
as $$
  with rate as materialized (
    select quota.allowed
    from public.consume_community_request_rate_limit('search_hashtags', 120, 60) as quota
  ), normalized as (
    select lower(trim(prefix)) as value
  ), visible_tags as (
    select post_tag.tag
    from public.community_post_hashtags as post_tag
    join public.community_posts as post on post.id = post_tag.post_id
    join public.community_profiles as author on author.user_id = post.author_id
    where author.is_public and public.can_view_community_user(post.author_id)

    union all

    select comment_tag.tag
    from public.community_comment_hashtags as comment_tag
    join public.community_comments as comment on comment.id = comment_tag.comment_id
    join public.community_posts as post on post.id = comment.post_id
    join public.community_profiles as post_author on post_author.user_id = post.author_id
    join public.community_profiles as comment_author on comment_author.user_id = comment.author_id
    where post_author.is_public
      and comment_author.is_public
      and public.can_view_community_user(post.author_id)
      and public.can_view_community_user(comment.author_id)
  )
  select visible_tags.tag, count(*)::integer as usage_count
  from visible_tags, normalized, rate
  where rate.allowed
    and length(normalized.value) >= 1
    and visible_tags.tag like normalized.value || '%'
  group by visible_tags.tag
  order by usage_count desc, visible_tags.tag asc
  limit 8;
$$;

create or replace function public.search_community_hashtag_posts(tag_prefix text)
returns table (post_id uuid)
language sql
volatile
security definer
set search_path = ''
as $$
  with rate as materialized (
    select quota.allowed
    from public.consume_community_request_rate_limit('search_hashtag_posts', 60, 60) as quota
  )
  select post.id
  from public.community_post_hashtags as post_tag
  join public.community_posts as post on post.id = post_tag.post_id
  join public.community_profiles as author on author.user_id = post.author_id
  cross join rate
  where rate.allowed
    and post_tag.tag = lower(trim(tag_prefix))
    and author.is_public
    and public.can_view_community_user(post.author_id)
  order by post.created_at desc
  limit 50;
$$;

-- Availability feedback is deliberately tighter than read-only search because
-- it is a common username-enumeration and automation target. The unique index
-- remains authoritative for the actual profile update.
create or replace function public.is_community_username_available(candidate text)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  normalized text := lower(trim(candidate));
  reserved text[] := array[
    'about', 'admin', 'api', 'app', 'auth', 'community', 'discover',
    'explore', 'feed', 'groups', 'help', 'home', 'login', 'messages',
    'norge360', 'notifications', 'plan', 'privacy', 'profile', 'search',
    'settings', 'signup', 'support', 'terms', 'user', 'users', 'www'
  ];
  quota record;
begin
  select * into quota
  from public.consume_community_request_rate_limit('username_availability', 30, 60);

  if not quota.allowed then
    return false;
  end if;
  if normalized !~ '^[a-z0-9](?:[a-z0-9_]{1,28}[a-z0-9])?$'
     or normalized = any (reserved) then
    return false;
  end if;

  return not exists (
    select 1
    from public.community_profiles
    where lower(username) = normalized
      and user_id <> (select auth.uid())
  );
end;
$$;

revoke all on function public.search_community_profiles(text) from public;
grant execute on function public.search_community_profiles(text) to authenticated;
revoke all on function public.search_community_groups(text) from public;
grant execute on function public.search_community_groups(text) to authenticated;
revoke all on function public.search_community_posts(text) from public;
grant execute on function public.search_community_posts(text) to authenticated;
revoke all on function public.search_community_hashtags(text) from public;
grant execute on function public.search_community_hashtags(text) to authenticated;
revoke all on function public.search_community_hashtag_posts(text) from public;
grant execute on function public.search_community_hashtag_posts(text) to authenticated;
revoke all on function public.is_community_username_available(text) from public;
grant execute on function public.is_community_username_available(text) to authenticated;

comment on table public.community_request_rate_limits is
  'Server-owned per-member sliding-window counters for expensive or abuse-prone authenticated RPCs.';
comment on function public.consume_community_request_rate_limit(text, integer, integer, uuid) is
  'Atomically consumes a per-member request quota. Service role may target an explicit member for server-owned endpoints.';

-- Keep write quotas at the table boundary so every authorized RPC variant is
-- covered, including text-only and attachment-backed message sends. The
-- existing per-minute message checks remain as a defense-in-depth guard;
-- these atomic buckets close their concurrent-request gap.
create or replace function public.enforce_community_write_rate_limit()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  actor_role text := coalesce(current_setting('request.jwt.claim.role', true), '');
  bucket text;
  target_user_id uuid;
  target_limit integer;
  target_window_seconds integer;
  quota record;
begin
  if actor_role <> 'authenticated' then
    return new;
  end if;

  if tg_table_name = 'community_conversations' then
    bucket := 'conversation_request';
    target_user_id := (to_jsonb(new) ->> 'requested_by_id')::uuid;
    target_limit := 20;
    target_window_seconds := 3_600;
  elsif tg_table_name = 'community_messages' then
    bucket := 'direct_message_send';
    target_user_id := (to_jsonb(new) ->> 'sender_id')::uuid;
    target_limit := 20;
    target_window_seconds := 60;
  elsif tg_table_name = 'community_group_chat_messages' then
    bucket := 'group_message_send';
    target_user_id := (to_jsonb(new) ->> 'sender_id')::uuid;
    target_limit := 20;
    target_window_seconds := 60;
  elsif tg_table_name = 'community_reports' then
    bucket := 'report_create';
    target_user_id := (to_jsonb(new) ->> 'reporter_id')::uuid;
    target_limit := 20;
    target_window_seconds := 3_600;
  else
    raise exception 'unsupported community rate limit trigger table';
  end if;

  if target_user_id is null or target_user_id <> (select auth.uid()) then
    raise exception 'write identity mismatch';
  end if;

  select * into quota
  from public.consume_community_request_rate_limit(
    bucket,
    target_limit,
    target_window_seconds,
    target_user_id
  );
  if not quota.allowed then
    raise exception 'community write rate limit reached';
  end if;
  return new;
end;
$$;

revoke all on function public.enforce_community_write_rate_limit() from public, anon, authenticated;

drop trigger if exists community_conversation_request_rate_limit
  on public.community_conversations;
create trigger community_conversation_request_rate_limit
before insert on public.community_conversations
for each row execute function public.enforce_community_write_rate_limit();

drop trigger if exists community_direct_message_rate_limit
  on public.community_messages;
create trigger community_direct_message_rate_limit
before insert on public.community_messages
for each row execute function public.enforce_community_write_rate_limit();

drop trigger if exists community_group_message_rate_limit
  on public.community_group_chat_messages;
create trigger community_group_message_rate_limit
before insert on public.community_group_chat_messages
for each row execute function public.enforce_community_write_rate_limit();

drop trigger if exists community_report_rate_limit
  on public.community_reports;
create trigger community_report_rate_limit
before insert on public.community_reports
for each row execute function public.enforce_community_write_rate_limit();
