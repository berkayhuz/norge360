-- Private groups are hidden from discovery. A member, a pending join requester,
-- or an invited user may still resolve the group so the invitation can be acted on.
alter table public.community_groups
  drop constraint if exists community_groups_visibility_check;
alter table public.community_groups
  add constraint community_groups_visibility_check
  check (visibility in ('public', 'approval_required', 'private'));

create table if not exists public.community_group_invitations (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.community_groups(id) on delete cascade,
  target_user_id uuid not null references auth.users(id) on delete cascade,
  invited_by uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined')),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  check (target_user_id <> invited_by)
);

create unique index if not exists community_group_pending_invitation_idx
  on public.community_group_invitations (group_id, target_user_id)
  where status = 'pending';

alter table public.community_group_invitations enable row level security;
revoke all on public.community_group_invitations from anon, authenticated;
grant select on public.community_group_invitations to authenticated;
create policy "Invitees can view their group invitations"
on public.community_group_invitations for select to authenticated
using (target_user_id = (select auth.uid()));
create policy "Group managers can view their group invitations"
on public.community_group_invitations for select to authenticated
using (exists (
  select 1 from public.community_group_memberships membership
  where membership.group_id = community_group_invitations.group_id
    and membership.user_id = (select auth.uid())
    and membership.role in ('owner', 'admin')
));

-- Reapply the group visibility boundary after the original public-group policy.
drop policy if exists "Authenticated users can view community groups" on public.community_groups;
create policy "Authenticated users can view community groups"
on public.community_groups for select to authenticated
using (
  moderation_state = 'active'
  and (
    visibility <> 'private'
    or exists (
      select 1 from public.community_group_memberships membership
      where membership.group_id = community_groups.id
        and membership.user_id = (select auth.uid())
    )
    or exists (
      select 1 from public.community_group_join_requests request
      where request.group_id = community_groups.id
        and request.user_id = (select auth.uid())
        and request.status = 'pending'
    )
    or exists (
      select 1 from public.community_group_invitations invitation
      where invitation.group_id = community_groups.id
        and invitation.target_user_id = (select auth.uid())
        and invitation.status = 'pending'
    )
  )
);

create or replace function public.create_community_group(
  group_name text,
  group_slug text,
  group_description text,
  group_scope text,
  group_city_or_region text default null,
  group_visibility text default 'public'
)
returns public.community_groups
language plpgsql security definer set search_path = '' as $$
declare
  created_group public.community_groups;
  normalized_slug text := lower(trim(group_slug));
begin
  if (select auth.uid()) is null then raise exception 'authentication required'; end if;
  if not public.is_valid_community_group_slug(normalized_slug) then raise exception 'invalid group slug'; end if;
  if char_length(trim(group_name)) not between 3 and 100 then raise exception 'invalid group name'; end if;
  if char_length(trim(group_description)) not between 10 and 500 then raise exception 'invalid group description'; end if;
  if group_scope not in ('city', 'interest') then raise exception 'invalid group scope'; end if;
  if group_visibility not in ('public', 'approval_required', 'private') then raise exception 'invalid group visibility'; end if;
  if exists (select 1 from public.community_groups where slug = normalized_slug) then raise exception 'group slug unavailable'; end if;
  if not exists (select 1 from public.community_profiles where user_id = (select auth.uid())) then raise exception 'profile required'; end if;

  insert into public.community_groups (name, slug, description, scope, city_or_region, visibility, created_by)
  values (trim(group_name), normalized_slug, trim(group_description), group_scope,
    nullif(trim(group_city_or_region), ''), group_visibility, (select auth.uid()))
  returning * into created_group;

  insert into public.community_group_memberships (group_id, user_id, role)
  values (created_group.id, (select auth.uid()), 'owner');
  return created_group;
end;
$$;

create or replace function public.update_community_group_visibility(target_group_id uuid, next_visibility text)
returns void language plpgsql security definer set search_path = '' as $$
declare actor_role text;
begin
  select role into actor_role from public.community_group_memberships
  where group_id = target_group_id and user_id = (select auth.uid());
  if actor_role not in ('owner', 'admin') then raise exception 'insufficient group permission'; end if;
  if next_visibility not in ('public', 'approval_required', 'private') then raise exception 'invalid group visibility'; end if;
  update public.community_groups set visibility = next_visibility where id = target_group_id;
end;
$$;

create or replace function public.invite_community_group_member(target_group_id uuid, target_user_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare
  actor_id uuid := (select auth.uid());
  actor_role text;
  invitee_id uuid := target_user_id;
begin
  if actor_id is null then raise exception 'authentication required'; end if;
  if invitee_id = actor_id then raise exception 'cannot invite yourself'; end if;
  select role into actor_role from public.community_group_memberships
  where group_id = target_group_id and user_id = actor_id;
  if actor_role not in ('owner', 'admin') then raise exception 'insufficient group permission'; end if;
  if not exists (select 1 from public.community_groups where id = target_group_id and moderation_state = 'active') then
    raise exception 'group unavailable';
  end if;
  if not exists (select 1 from public.community_profiles where user_id = invitee_id) then
    raise exception 'target member unavailable';
  end if;
  if exists (select 1 from public.user_blocks where
      (blocker_id = actor_id and blocked_user_id = invitee_id)
      or (blocker_id = invitee_id and blocked_user_id = actor_id)) then
    raise exception 'member unavailable';
  end if;
  if exists (select 1 from public.community_group_memberships where group_id = target_group_id and user_id = invitee_id) then
    raise exception 'member already belongs to group';
  end if;

  insert into public.community_group_invitations (group_id, target_user_id, invited_by, status, created_at, responded_at)
  values (target_group_id, invitee_id, actor_id, 'pending', now(), null)
  on conflict (group_id, target_user_id) where status = 'pending' do update
    set invited_by = excluded.invited_by, created_at = excluded.created_at, responded_at = null;

  insert into public.community_notifications (recipient_id, actor_id, type, group_id, event_key)
  values (invitee_id, actor_id, 'group_invitation', target_group_id,
    'group-invitation:' || target_group_id::text || ':' || invitee_id::text || ':' || extract(epoch from now())::bigint::text);
end;
$$;

create table if not exists public.community_event_invitations (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.community_events(id) on delete cascade,
  target_user_id uuid not null references auth.users(id) on delete cascade,
  invited_by uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined')),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  check (target_user_id <> invited_by)
);

create unique index if not exists community_event_pending_invitation_idx
  on public.community_event_invitations (event_id, target_user_id)
  where status = 'pending';

alter table public.community_event_invitations enable row level security;
revoke all on public.community_event_invitations from anon, authenticated;

create or replace function public.invite_community_event_member(target_event_id uuid, target_user_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare
  actor_id uuid := (select auth.uid());
  target_event public.community_events;
  invitee_id uuid := target_user_id;
begin
  if actor_id is null then raise exception 'authentication required'; end if;
  if invitee_id = actor_id then raise exception 'cannot invite yourself'; end if;
  select * into target_event from public.community_events where id = target_event_id;
  if target_event.id is null or target_event.starts_at <= now() then raise exception 'event unavailable'; end if;
  if target_event.group_id is not null and not exists (
    select 1 from public.community_group_memberships
    where group_id = target_event.group_id and user_id = invitee_id
  ) then raise exception 'target member is not in this group'; end if;
  if not exists (select 1 from public.community_profiles where user_id = invitee_id) then
    raise exception 'target member unavailable';
  end if;
  if exists (select 1 from public.user_blocks where
      (blocker_id = actor_id and blocked_user_id = invitee_id)
      or (blocker_id = invitee_id and blocked_user_id = actor_id)) then
    raise exception 'member unavailable';
  end if;

  insert into public.community_event_invitations (event_id, target_user_id, invited_by, status, created_at, responded_at)
  values (target_event_id, invitee_id, actor_id, 'pending', now(), null)
  on conflict (event_id, target_user_id) where status = 'pending' do update
    set invited_by = excluded.invited_by, created_at = excluded.created_at, responded_at = null;

  insert into public.community_notifications (recipient_id, actor_id, type, event_id, event_key)
  values (invitee_id, actor_id, 'event_invitation', target_event_id,
    'event-invitation:' || target_event_id::text || ':' || invitee_id::text || ':' || extract(epoch from now())::bigint::text);
end;
$$;

-- Invitations are private recipient metadata, but their target can resolve the
-- related group/event through the notification destination.
drop policy if exists "Users can view their visible notifications" on public.community_notifications;
create policy "Users can view their visible notifications"
on public.community_notifications for select to authenticated
using (
  recipient_id = (select auth.uid())
  and (
    type in ('group_join_approved', 'group_join_rejected', 'group_invitation', 'event_invitation')
    or public.can_view_community_user(actor_id)
  )
);

alter table public.community_notifications drop constraint if exists community_notifications_type_check;
alter table public.community_notifications add constraint community_notifications_type_check
  check (type in (
    'follow', 'post_like', 'post_comment', 'group_join_approved', 'group_join_rejected',
    'group_invitation', 'moderation_content_removed', 'moderation_content_restored',
    'moderation_member_restricted', 'moderation_member_restriction_revoked',
    'message_request', 'direct_message', 'event_updated', 'event_reminder', 'event_invitation'
  ));

revoke all on function public.invite_community_group_member(uuid, uuid) from public;
grant execute on function public.invite_community_group_member(uuid, uuid) to authenticated;
revoke all on function public.invite_community_event_member(uuid, uuid) from public;
grant execute on function public.invite_community_event_member(uuid, uuid) to authenticated;
