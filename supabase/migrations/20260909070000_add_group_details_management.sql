-- Group identity is part of navigation and must be changed through a
-- server-authorized path. The same slug validation is used for creation and
-- later edits so a reserved route cannot be introduced by either route.

create or replace function public.is_valid_community_group_slug(candidate text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select lower(trim(candidate)) ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'
    and char_length(lower(trim(candidate))) between 3 and 50
    and lower(trim(candidate)) <> all (array[
      'about', 'admin', 'api', 'app', 'auth', 'community', 'create', 'discover',
      'edit', 'events', 'explore', 'feed', 'groups', 'help', 'home', 'login',
      'manage', 'members', 'messages', 'new', 'norge360', 'notifications',
      'plan', 'privacy', 'profile', 'search', 'settings', 'signup', 'support',
      'terms', 'user', 'users', 'www'
    ]);
$$;

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
  if not public.is_valid_community_group_slug(normalized_slug) then raise exception 'invalid group slug'; end if;
  if char_length(trim(group_name)) not between 3 and 100 then raise exception 'invalid group name'; end if;
  if char_length(trim(group_description)) not between 10 and 500 then raise exception 'invalid group description'; end if;
  if group_scope not in ('city', 'interest') then raise exception 'invalid group scope'; end if;
  if group_visibility not in ('public', 'approval_required') then raise exception 'invalid group visibility'; end if;
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

create or replace function public.update_community_group_details(
  target_group_id uuid,
  next_name text,
  next_slug text,
  next_description text
)
returns public.community_groups
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_role text;
  normalized_slug text := lower(trim(next_slug));
  updated_group public.community_groups;
begin
  select role into actor_role
  from public.community_group_memberships
  where group_id = target_group_id and user_id = (select auth.uid());

  if actor_role not in ('owner', 'admin') then raise exception 'insufficient group permission'; end if;
  if not public.is_valid_community_group_slug(normalized_slug) then raise exception 'invalid group slug'; end if;
  if char_length(trim(next_name)) not between 3 and 100 then raise exception 'invalid group name'; end if;
  if char_length(trim(next_description)) not between 10 and 500 then raise exception 'invalid group description'; end if;
  if exists (
    select 1 from public.community_groups
    where slug = normalized_slug and id <> target_group_id
  ) then raise exception 'group slug unavailable'; end if;

  update public.community_groups
  set name = trim(next_name), slug = normalized_slug, description = trim(next_description)
  where id = target_group_id
  returning * into updated_group;

  if updated_group.id is null then raise exception 'group not found'; end if;
  return updated_group;
end;
$$;

revoke all on function public.is_valid_community_group_slug(text) from public;
revoke all on function public.create_community_group(text, text, text, text, text, text) from public;
grant execute on function public.create_community_group(text, text, text, text, text, text) to authenticated;
revoke all on function public.update_community_group_details(uuid, text, text, text) from public;
grant execute on function public.update_community_group_details(uuid, text, text, text) to authenticated;
