-- A group must never become ownerless. Repair any legacy orphaned groups
-- first, then prevent an owner from using the ordinary leave route. Ownership
-- moves only through the audited, atomic transfer RPC below.

with groups_without_owner as (
  select community_group.id, community_group.created_by
  from public.community_groups as community_group
  where not exists (
    select 1 from public.community_group_memberships as membership
    where membership.group_id = community_group.id and membership.role = 'owner'
  )
), ranked_candidates as (
  select
    membership.group_id,
    membership.user_id,
    row_number() over (
      partition by membership.group_id
      order by (membership.user_id = groups_without_owner.created_by) desc, membership.created_at asc
    ) as position
  from public.community_group_memberships as membership
  join groups_without_owner on groups_without_owner.id = membership.group_id
)
update public.community_group_memberships as membership
set role = 'owner'
from ranked_candidates
where membership.group_id = ranked_candidates.group_id
  and membership.user_id = ranked_candidates.user_id
  and ranked_candidates.position = 1;

drop policy if exists "Users can leave their own groups" on public.community_group_memberships;
create policy "Non-owner members can leave their own groups"
on public.community_group_memberships for delete to authenticated
using (
  user_id = (select auth.uid())
  and role <> 'owner'
);

alter table public.community_group_moderation_audit
  drop constraint if exists community_group_moderation_audit_action_check;
alter table public.community_group_moderation_audit
  add constraint community_group_moderation_audit_action_check
  check (action in ('ban', 'unban', 'remove_post', 'transfer_owner'));

create or replace function public.transfer_community_group_ownership(
  target_group_id uuid,
  target_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  actor_role text;
  target_role text;
begin
  select role into actor_role
  from public.community_group_memberships
  where group_id = target_group_id and user_id = actor_id;

  select role into target_role
  from public.community_group_memberships
  where group_id = target_group_id and user_id = target_user_id;

  if actor_role <> 'owner' then raise exception 'only the group owner can transfer ownership'; end if;
  if target_user_id = actor_id or target_role <> 'admin' then raise exception 'ownership can only be transferred to an admin'; end if;

  update public.community_group_memberships
  set role = case
    when user_id = target_user_id then 'owner'
    when user_id = actor_id then 'admin'
    else role
  end
  where group_id = target_group_id and user_id in (actor_id, target_user_id);

  insert into public.community_group_moderation_audit (group_id, actor_id, target_user_id, action)
  values (target_group_id, actor_id, target_user_id, 'transfer_owner');
end;
$$;

revoke all on function public.transfer_community_group_ownership(uuid, uuid) from public;
grant execute on function public.transfer_community_group_ownership(uuid, uuid) to authenticated;
