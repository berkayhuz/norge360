alter table public.community_groups
  add column if not exists posting_permission text not null default 'members'
  check (posting_permission in ('members', 'moderators_and_above'));

create or replace function public.can_post_to_community_group(target_group_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.community_groups as community_group
    join public.community_group_memberships as membership on membership.group_id = community_group.id
    where community_group.id = target_group_id
      and membership.user_id = (select auth.uid())
      and (
        community_group.posting_permission = 'members'
        or membership.role in ('owner', 'admin', 'moderator')
      )
  );
$$;
revoke all on function public.can_post_to_community_group(uuid) from public;
grant execute on function public.can_post_to_community_group(uuid) to authenticated;

drop policy if exists "Users can create their own posts" on public.community_posts;
create policy "Users can create their own posts"
on public.community_posts for insert to authenticated
with check (
  (select auth.uid()) = author_id
  and exists (select 1 from public.community_profiles where user_id = (select auth.uid()))
  and (group_id is null or public.can_post_to_community_group(group_id))
);

create or replace function public.update_community_group_posting_permission(target_group_id uuid, permission text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if permission not in ('members', 'moderators_and_above') then raise exception 'invalid posting permission'; end if;
  if not exists (
    select 1 from public.community_group_memberships
    where group_id = target_group_id and user_id = (select auth.uid()) and role in ('owner', 'admin')
  ) then raise exception 'insufficient group permission'; end if;
  update public.community_groups set posting_permission = permission where id = target_group_id;
end;
$$;
revoke all on function public.update_community_group_posting_permission(uuid, text) from public;
grant execute on function public.update_community_group_posting_permission(uuid, text) to authenticated;
