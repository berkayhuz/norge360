-- Keep untrusted search text out of PostgREST filter expressions. These
-- security-invoker functions still apply each table's existing RLS policies.

create or replace function public.search_community_profiles(search_query text)
returns setof public.community_profiles
language sql
stable
security invoker
set search_path = ''
as $$
  with normalized as (
    select btrim(replace(replace(replace(search_query, E'\\', ''), '%', ''), '_', '')) as value
  )
  select profile.*
  from public.community_profiles as profile, normalized
  where char_length(normalized.value) between 3 and 80
    and (
      profile.display_name ilike '%' || normalized.value || '%'
      or profile.username ilike '%' || normalized.value || '%'
    )
  order by profile.username asc
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
    select btrim(replace(replace(replace(search_query, E'\\', ''), '%', ''), '_', '')) as value
  )
  select community_group.*
  from public.community_groups as community_group, normalized
  where char_length(normalized.value) between 3 and 80
    and (
      community_group.name ilike '%' || normalized.value || '%'
      or community_group.slug ilike '%' || normalized.value || '%'
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
    select btrim(replace(replace(replace(search_query, E'\\', ''), '%', ''), '_', '')) as value
  )
  select post.*
  from public.community_posts as post, normalized
  where char_length(normalized.value) between 3 and 80
    and post.body ilike '%' || normalized.value || '%'
  order by post.created_at desc
  limit 20;
$$;

revoke all on function public.search_community_profiles(text) from public;
grant execute on function public.search_community_profiles(text) to authenticated;
revoke all on function public.search_community_groups(text) from public;
grant execute on function public.search_community_groups(text) to authenticated;
revoke all on function public.search_community_posts(text) from public;
grant execute on function public.search_community_posts(text) to authenticated;
