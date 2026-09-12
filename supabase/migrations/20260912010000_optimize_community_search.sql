-- Keep the current substring-search semantics while making leading-wildcard
-- lookups indexable. Full-text search is intentionally not introduced here:
-- post content is multilingual and FTS would change matching semantics.
create extension if not exists pg_trgm with schema extensions;

create index if not exists community_profiles_display_name_trgm_index
  on public.community_profiles using gin (lower(display_name) extensions.gin_trgm_ops);
create index if not exists community_profiles_username_trgm_index
  on public.community_profiles using gin (lower(username) extensions.gin_trgm_ops);
create index if not exists community_profiles_username_prefix_index
  on public.community_profiles (lower(username) pg_catalog.text_pattern_ops);
create index if not exists community_groups_name_trgm_index
  on public.community_groups using gin (lower(name) extensions.gin_trgm_ops);
create index if not exists community_groups_slug_trgm_index
  on public.community_groups using gin (lower(slug) extensions.gin_trgm_ops);
create index if not exists community_posts_body_trgm_index
  on public.community_posts using gin (lower(body) extensions.gin_trgm_ops);

-- Keep these functions security-invoker so table RLS remains the visibility
-- boundary. The normalized value is lower-cased once and used with LIKE so
-- the functional indexes above match the predicates.
-- The original search RPCs were created with a composite return type. Drop
-- and recreate them so this migration remains valid on PostgreSQL versions
-- that reject replacing that return type, while preserving the public
-- function signatures and authenticated-only execute grants below.
drop function if exists public.search_community_profiles(text);
drop function if exists public.search_community_groups(text);
drop function if exists public.search_community_posts(text);

create or replace function public.search_community_profiles(search_query text)
returns setof public.community_profiles
language sql
stable
security invoker
set search_path = ''
as $$
  with normalized as (
    select lower(btrim(replace(replace(replace(search_query, E'\\', ''), '%', ''), '_', ''))) as value
  )
  select profile.*
  from public.community_profiles as profile, normalized
  where char_length(normalized.value) between 3 and 80
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
stable
security invoker
set search_path = ''
as $$
  with normalized as (
    select lower(btrim(replace(replace(replace(search_query, E'\\', ''), '%', ''), '_', ''))) as value
  )
  select community_group.*
  from public.community_groups as community_group, normalized
  where char_length(normalized.value) between 3 and 80
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
stable
security invoker
set search_path = ''
as $$
  with normalized as (
    select lower(btrim(replace(replace(replace(search_query, E'\\', ''), '%', ''), '_', ''))) as value
  )
  select post.*
  from public.community_posts as post, normalized
  where char_length(normalized.value) between 3 and 80
    and lower(post.body) like '%' || normalized.value || '%'
  order by post.created_at desc
  limit 20;
$$;

revoke all on function public.search_community_profiles(text) from public;
grant execute on function public.search_community_profiles(text) to authenticated;
revoke all on function public.search_community_groups(text) from public;
grant execute on function public.search_community_groups(text) to authenticated;
revoke all on function public.search_community_posts(text) from public;
grant execute on function public.search_community_posts(text) to authenticated;
