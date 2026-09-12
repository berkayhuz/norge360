-- Group-scoped bans are separate from a personal block. They are immutable from
-- the iOS client and every change receives an append-only audit record.
create table if not exists public.community_group_bans (
  group_id uuid not null references public.community_groups(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_by uuid not null references auth.users(id) on delete restrict,
  previous_role text not null default 'member' check (previous_role in ('owner', 'admin', 'moderator', 'member')),
  created_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

create table if not exists public.community_group_moderation_audit (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.community_groups(id) on delete cascade,
  actor_id uuid not null references auth.users(id) on delete restrict,
  target_user_id uuid not null references auth.users(id) on delete restrict,
  action text not null check (action in ('ban', 'unban')),
  created_at timestamptz not null default now()
);

create index if not exists community_group_moderation_audit_group_created_idx
  on public.community_group_moderation_audit (group_id, created_at desc);

alter table public.community_group_bans enable row level security;
alter table public.community_group_moderation_audit enable row level security;

drop policy if exists "Group owners and admins can view group bans" on public.community_group_bans;
create policy "Group owners and admins can view group bans"
on public.community_group_bans for select to authenticated
using (exists (
  select 1 from public.community_group_memberships m
  where m.group_id = community_group_bans.group_id
    and m.user_id = (select auth.uid()) and m.role in ('owner', 'admin')
));

drop policy if exists "Group owners and admins can view moderation audit" on public.community_group_moderation_audit;
create policy "Group owners and admins can view moderation audit"
on public.community_group_moderation_audit for select to authenticated
using (exists (
  select 1 from public.community_group_memberships m
  where m.group_id = community_group_moderation_audit.group_id
    and m.user_id = (select auth.uid()) and m.role in ('owner', 'admin')
));

-- Close the old direct-client join route as well as the RPC route.
drop policy if exists "Users can join public groups as members" on public.community_group_memberships;
create policy "Users can join public groups as members"
on public.community_group_memberships for insert to authenticated
with check (
  (select auth.uid()) = user_id and role = 'member'
  and exists (select 1 from public.community_profiles p where p.user_id = (select auth.uid()))
  and exists (select 1 from public.community_groups g where g.id = group_id and g.visibility = 'public')
  and not exists (select 1 from public.community_group_bans b where b.group_id = community_group_memberships.group_id and b.user_id = (select auth.uid()))
);

create or replace function public.request_community_group_join(target_group_id uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := (select auth.uid()); target_visibility text;
begin
  if actor_id is null then raise exception 'authentication required'; end if;
  if not exists (select 1 from public.community_profiles where user_id = actor_id) then raise exception 'profile required'; end if;
  if exists (select 1 from public.community_group_bans where group_id = target_group_id and user_id = actor_id) then raise exception 'you cannot join this group'; end if;
  select visibility into target_visibility from public.community_groups where id = target_group_id;
  if target_visibility is null then raise exception 'group not found'; end if;
  if exists (select 1 from public.community_group_memberships where group_id = target_group_id and user_id = actor_id) then return 'member'; end if;
  if target_visibility = 'public' then
    insert into public.community_group_memberships (group_id, user_id, role) values (target_group_id, actor_id, 'member') on conflict (group_id, user_id) do nothing;
    delete from public.community_group_join_requests where group_id = target_group_id and user_id = actor_id;
    return 'joined';
  end if;
  insert into public.community_group_join_requests (group_id, user_id, status, requested_at, reviewed_at, reviewed_by)
  values (target_group_id, actor_id, 'pending', now(), null, null)
  on conflict (group_id, user_id) do update set status = 'pending', requested_at = now(), reviewed_at = null, reviewed_by = null;
  return 'requested';
end;
$$;

create or replace function public.ban_community_group_member(target_group_id uuid, target_user_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := (select auth.uid()); actor_role text; target_role text;
begin
  select role into actor_role from public.community_group_memberships where group_id = target_group_id and user_id = actor_id;
  select role into target_role from public.community_group_memberships where group_id = target_group_id and user_id = target_user_id;
  if actor_role not in ('owner', 'admin') then raise exception 'insufficient group permission'; end if;
  if target_user_id = actor_id or target_role = 'owner' then raise exception 'target cannot be banned'; end if;
  if actor_role = 'admin' and coalesce(target_role, 'member') <> 'member' then raise exception 'admin cannot ban elevated roles'; end if;
  insert into public.community_group_bans (group_id, user_id, created_by, previous_role)
  values (target_group_id, target_user_id, actor_id, coalesce(target_role, 'member')) on conflict (group_id, user_id) do nothing;
  delete from public.community_group_memberships where group_id = target_group_id and user_id = target_user_id;
  update public.community_group_join_requests set status = 'rejected', reviewed_at = now(), reviewed_by = actor_id
  where group_id = target_group_id and user_id = target_user_id and status = 'pending';
  insert into public.community_group_moderation_audit (group_id, actor_id, target_user_id, action)
  values (target_group_id, actor_id, target_user_id, 'ban');
end;
$$;

create or replace function public.unban_community_group_member(target_group_id uuid, target_user_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := (select auth.uid()); actor_role text; banned_role text;
begin
  select role into actor_role from public.community_group_memberships where group_id = target_group_id and user_id = actor_id;
  select previous_role into banned_role from public.community_group_bans where group_id = target_group_id and user_id = target_user_id;
  if actor_role not in ('owner', 'admin') then raise exception 'insufficient group permission'; end if;
  if banned_role is null then raise exception 'ban not found'; end if;
  if actor_role = 'admin' and banned_role <> 'member' then raise exception 'admin cannot unban elevated roles'; end if;
  delete from public.community_group_bans where group_id = target_group_id and user_id = target_user_id;
  insert into public.community_group_moderation_audit (group_id, actor_id, target_user_id, action)
  values (target_group_id, actor_id, target_user_id, 'unban');
end;
$$;

create or replace function public.list_community_group_bans(target_group_id uuid)
returns table (user_id uuid, display_name text, username text, created_at timestamptz)
language plpgsql security definer set search_path = '' as $$
declare actor_role text;
begin
  select membership.role into actor_role
  from public.community_group_memberships as membership
  where membership.group_id = target_group_id
    and membership.user_id = (select auth.uid());
  if actor_role not in ('owner', 'admin') then raise exception 'insufficient group permission'; end if;
  return query select b.user_id, p.display_name, p.username, b.created_at
  from public.community_group_bans b join public.community_profiles p on p.user_id = b.user_id
  where b.group_id = target_group_id order by b.created_at desc;
end;
$$;

revoke all on function public.request_community_group_join(uuid) from public;
grant execute on function public.request_community_group_join(uuid) to authenticated;
revoke all on function public.ban_community_group_member(uuid, uuid) from public;
grant execute on function public.ban_community_group_member(uuid, uuid) to authenticated;
revoke all on function public.unban_community_group_member(uuid, uuid) from public;
grant execute on function public.unban_community_group_member(uuid, uuid) to authenticated;
revoke all on function public.list_community_group_bans(uuid) from public;
grant execute on function public.list_community_group_bans(uuid) to authenticated;
