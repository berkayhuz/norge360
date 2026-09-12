alter table public.community_group_memberships
  drop constraint if exists community_group_memberships_role_check;
alter table public.community_group_memberships
  add constraint community_group_memberships_role_check
  check (role in ('owner', 'admin', 'moderator', 'member'));

create or replace function public.create_community_group(
  group_name text,
  group_slug text,
  group_description text,
  group_scope text,
  group_city_or_region text default null,
  group_visibility text default 'public'
)
returns public.community_groups
language plpgsql
security definer
set search_path = ''
as $$
declare
  created_group public.community_groups;
  normalized_slug text := lower(trim(group_slug));
begin
  if (select auth.uid()) is null then raise exception 'authentication required'; end if;
  if normalized_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' then raise exception 'invalid group slug'; end if;
  if exists (select 1 from public.community_groups where slug = normalized_slug) then raise exception 'group slug unavailable'; end if;
  if not exists (select 1 from public.community_profiles where user_id = (select auth.uid())) then raise exception 'profile required'; end if;

  insert into public.community_groups (name, slug, description, scope, city_or_region, visibility, created_by)
  values (trim(group_name), normalized_slug, trim(group_description), group_scope, nullif(trim(group_city_or_region), ''), group_visibility, (select auth.uid()))
  returning * into created_group;

  insert into public.community_group_memberships (group_id, user_id, role)
  values (created_group.id, (select auth.uid()), 'owner');
  return created_group;
end;
$$;

revoke all on function public.create_community_group(text, text, text, text, text, text) from public;
grant execute on function public.create_community_group(text, text, text, text, text, text) to authenticated;
