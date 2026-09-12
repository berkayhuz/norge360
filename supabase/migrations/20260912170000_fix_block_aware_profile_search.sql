-- Keep profile search on the public projection. Returning the private source
-- row from an invoker RPC requires every source-table column privilege and
-- makes the search path fail for authenticated clients after column grants
-- are tightened. The projection keeps the same block-aware visibility
-- boundary and exposes only intentionally public fields.
drop function if exists public.search_community_profiles(text);

create function public.search_community_profiles(search_query text)
returns setof public.community_public_profiles
language sql
stable
security invoker
set search_path = ''
as $$
  with normalized as (
    select lower(
      btrim(replace(replace(replace(search_query, E'\\', ''), '%', ''), '_', ''))
    ) as value
  )
  select profile.*
  from public.community_public_profiles as profile, normalized
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

revoke all on function public.search_community_profiles(text) from public;
grant execute on function public.search_community_profiles(text) to authenticated;
