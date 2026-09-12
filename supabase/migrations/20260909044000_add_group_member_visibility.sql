create or replace function public.is_community_group_member(target_group_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.community_group_memberships
    where group_id = target_group_id and user_id = (select auth.uid())
  );
$$;
revoke all on function public.is_community_group_member(uuid) from public;
grant execute on function public.is_community_group_member(uuid) to authenticated;

drop policy if exists "Members can view group membership roster" on public.community_group_memberships;
create policy "Members can view group membership roster"
on public.community_group_memberships for select to authenticated
using (public.is_community_group_member(group_id));
