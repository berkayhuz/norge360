-- A pending request is not a membership and grants no access to member-only content.
create table if not exists public.community_group_join_requests (
  group_id uuid not null references public.community_groups(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  requested_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id) on delete set null,
  primary key (group_id, user_id)
);

create index if not exists community_group_join_requests_group_status_requested_idx
  on public.community_group_join_requests (group_id, status, requested_at);
create index if not exists community_group_join_requests_user_status_idx
  on public.community_group_join_requests (user_id, status);

alter table public.community_group_join_requests enable row level security;

drop policy if exists "Users can read their own group join requests" on public.community_group_join_requests;
create policy "Users can read their own group join requests"
on public.community_group_join_requests for select to authenticated
using (user_id = (select auth.uid()));

drop policy if exists "Group admins can read group join requests" on public.community_group_join_requests;
create policy "Group admins can read group join requests"
on public.community_group_join_requests for select to authenticated
using (exists (
  select 1 from public.community_group_memberships m
  where m.group_id = community_group_join_requests.group_id
    and m.user_id = (select auth.uid())
    and m.role in ('owner', 'admin')
));

create or replace function public.request_community_group_join(target_group_id uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare
  actor_id uuid := (select auth.uid());
  target_visibility text;
begin
  if actor_id is null then raise exception 'authentication required'; end if;
  if not exists (select 1 from public.community_profiles where user_id = actor_id) then raise exception 'profile required'; end if;
  select visibility into target_visibility from public.community_groups where id = target_group_id;
  if target_visibility is null then raise exception 'group not found'; end if;
  if exists (select 1 from public.community_group_memberships where group_id = target_group_id and user_id = actor_id) then return 'member'; end if;

  if target_visibility = 'public' then
    insert into public.community_group_memberships (group_id, user_id, role)
    values (target_group_id, actor_id, 'member') on conflict (group_id, user_id) do nothing;
    delete from public.community_group_join_requests where group_id = target_group_id and user_id = actor_id;
    return 'joined';
  end if;

  insert into public.community_group_join_requests (group_id, user_id, status, requested_at, reviewed_at, reviewed_by)
  values (target_group_id, actor_id, 'pending', now(), null, null)
  on conflict (group_id, user_id) do update
  set status = 'pending', requested_at = now(), reviewed_at = null, reviewed_by = null;
  return 'requested';
end;
$$;

create or replace function public.update_community_group_visibility(target_group_id uuid, next_visibility text)
returns void language plpgsql security definer set search_path = '' as $$
declare actor_role text;
begin
  select membership.role into actor_role
  from public.community_group_memberships as membership
  where membership.group_id = target_group_id
    and membership.user_id = (select auth.uid());
  if actor_role not in ('owner', 'admin') then raise exception 'insufficient group permission'; end if;
  if next_visibility not in ('public', 'approval_required') then raise exception 'invalid group visibility'; end if;
  update public.community_groups set visibility = next_visibility where id = target_group_id;
end;
$$;

-- Purpose-limited projection: managers need an applicant's name/username, not their full private profile.
create or replace function public.list_community_group_join_requests(target_group_id uuid)
returns table (user_id uuid, status text, requested_at timestamptz, display_name text, username text)
language plpgsql security definer set search_path = '' as $$
declare actor_role text;
begin
  select membership.role into actor_role
  from public.community_group_memberships as membership
  where membership.group_id = target_group_id
    and membership.user_id = (select auth.uid());
  if actor_role not in ('owner', 'admin') then raise exception 'insufficient group permission'; end if;
  return query
  select r.user_id, r.status, r.requested_at, p.display_name, p.username
  from public.community_group_join_requests r
  join public.community_profiles p on p.user_id = r.user_id
  where r.group_id = target_group_id and r.status = 'pending'
  order by r.requested_at asc;
end;
$$;

create or replace function public.review_community_group_join_request(target_group_id uuid, target_user_id uuid, decision text)
returns void language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := (select auth.uid()); actor_role text;
begin
  select membership.role into actor_role
  from public.community_group_memberships as membership
  where membership.group_id = target_group_id
    and membership.user_id = actor_id;
  if actor_role not in ('owner', 'admin') then raise exception 'insufficient group permission'; end if;
  if decision not in ('approved', 'rejected') then raise exception 'invalid request decision'; end if;
  if not exists (select 1 from public.community_group_join_requests where group_id = target_group_id and user_id = target_user_id and status = 'pending') then raise exception 'pending join request not found'; end if;
  if decision = 'approved' then
    insert into public.community_group_memberships (group_id, user_id, role)
    values (target_group_id, target_user_id, 'member') on conflict (group_id, user_id) do nothing;
  end if;
  update public.community_group_join_requests set status = decision, reviewed_at = now(), reviewed_by = actor_id
  where group_id = target_group_id and user_id = target_user_id;
end;
$$;

revoke all on function public.request_community_group_join(uuid) from public;
grant execute on function public.request_community_group_join(uuid) to authenticated;
revoke all on function public.update_community_group_visibility(uuid, text) from public;
grant execute on function public.update_community_group_visibility(uuid, text) to authenticated;
revoke all on function public.list_community_group_join_requests(uuid) from public;
grant execute on function public.list_community_group_join_requests(uuid) to authenticated;
revoke all on function public.review_community_group_join_request(uuid, uuid, text) from public;
grant execute on function public.review_community_group_join_request(uuid, uuid, text) to authenticated;
