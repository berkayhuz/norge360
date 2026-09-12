create or replace function public.manage_community_group_member(
  target_group_id uuid,
  target_user_id uuid,
  action text,
  next_role text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_role text;
  target_role text;
begin
  select role into actor_role from public.community_group_memberships
  where group_id = target_group_id and user_id = (select auth.uid());
  select role into target_role from public.community_group_memberships
  where group_id = target_group_id and user_id = target_user_id;

  if actor_role not in ('owner', 'admin') then raise exception 'insufficient group permission'; end if;
  if target_role = 'owner' then raise exception 'owner cannot be managed'; end if;
  if actor_role = 'admin' and target_role in ('admin', 'moderator') then raise exception 'admin cannot manage peer roles'; end if;

  if action = 'remove' then
    delete from public.community_group_memberships where group_id = target_group_id and user_id = target_user_id;
  elsif action = 'set_role' then
    if next_role not in ('admin', 'moderator', 'member') then raise exception 'invalid group role'; end if;
    if actor_role = 'admin' and next_role <> 'member' then raise exception 'admin cannot assign elevated roles'; end if;
    update public.community_group_memberships set role = next_role where group_id = target_group_id and user_id = target_user_id;
  else
    raise exception 'invalid group action';
  end if;
end;
$$;

revoke all on function public.manage_community_group_member(uuid, uuid, text, text) from public;
grant execute on function public.manage_community_group_member(uuid, uuid, text, text) to authenticated;

create or replace function public.can_manage_community_group(target_group_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.community_group_memberships
    where group_id = target_group_id and user_id = (select auth.uid()) and role in ('owner', 'admin', 'moderator')
  );
$$;
revoke all on function public.can_manage_community_group(uuid) from public;
grant execute on function public.can_manage_community_group(uuid) to authenticated;
