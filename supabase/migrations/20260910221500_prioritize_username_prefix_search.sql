-- Blocking/search surfaces should show exact username prefixes first, while
-- retaining safe substring matching when a prefix has no result.
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
  order by
    case when profile.username ilike normalized.value || '%' then 0 else 1 end,
    profile.username asc
  limit 12;
$$;
