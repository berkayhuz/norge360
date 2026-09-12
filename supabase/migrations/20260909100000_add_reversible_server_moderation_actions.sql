-- Server-only community enforcement. Ordinary clients cannot read these tables
-- or set moderation state; the Worker calls the guarded RPC below using its
-- service-role credential after verifying a staff JWT.

alter table public.community_profiles
  add column if not exists moderation_state text not null default 'active';
alter table public.community_posts
  add column if not exists moderation_state text not null default 'active';
alter table public.community_comments
  add column if not exists moderation_state text not null default 'active';
alter table public.community_groups
  add column if not exists moderation_state text not null default 'active';

alter table public.community_profiles drop constraint if exists community_profiles_moderation_state_check;
alter table public.community_profiles add constraint community_profiles_moderation_state_check
  check (moderation_state in ('active', 'restricted'));
alter table public.community_posts drop constraint if exists community_posts_moderation_state_check;
alter table public.community_posts add constraint community_posts_moderation_state_check
  check (moderation_state in ('active', 'removed'));
alter table public.community_comments drop constraint if exists community_comments_moderation_state_check;
alter table public.community_comments add constraint community_comments_moderation_state_check
  check (moderation_state in ('active', 'removed'));
alter table public.community_groups drop constraint if exists community_groups_moderation_state_check;
alter table public.community_groups add constraint community_groups_moderation_state_check
  check (moderation_state in ('active', 'removed'));

create index if not exists community_posts_active_created_index
  on public.community_posts (created_at desc) where moderation_state = 'active';
create index if not exists community_comments_active_post_created_index
  on public.community_comments (post_id, created_at) where moderation_state = 'active';

create table if not exists public.community_member_restrictions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  scope text not null check (scope in ('posting')),
  status text not null default 'active' check (status in ('active', 'revoked')),
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  revoked_by uuid references auth.users(id) on delete set null,
  check (expires_at is null or expires_at > created_at),
  check ((status = 'active' and revoked_at is null) or (status = 'revoked' and revoked_at is not null))
);

create unique index if not exists community_member_active_posting_restriction_index
  on public.community_member_restrictions (user_id, scope)
  where status = 'active';

create table if not exists public.community_moderation_action_audit (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references public.community_reports(id) on delete restrict,
  moderator_id uuid not null references auth.users(id) on delete restrict,
  action text not null check (action in (
    'content_removed', 'content_restored', 'member_restricted', 'member_restriction_revoked'
  )),
  target_type text not null check (target_type in ('profile', 'post', 'comment', 'group')),
  target_id uuid not null,
  subject_user_id uuid references auth.users(id) on delete set null,
  restriction_id uuid references public.community_member_restrictions(id) on delete set null,
  reverses_action_id uuid references public.community_moderation_action_audit(id) on delete set null,
  note text check (note is null or char_length(trim(note)) <= 1000),
  member_notice text check (member_notice is null or char_length(trim(member_notice)) <= 500),
  created_at timestamptz not null default now()
);

alter table public.community_moderation_action_audit
  add column if not exists member_notice text;
alter table public.community_moderation_action_audit
  drop constraint if exists community_moderation_action_audit_member_notice_check;
alter table public.community_moderation_action_audit
  add constraint community_moderation_action_audit_member_notice_check
  check (member_notice is null or char_length(trim(member_notice)) <= 500);

create index if not exists community_moderation_action_audit_report_created_index
  on public.community_moderation_action_audit (report_id, created_at desc);
create index if not exists community_moderation_action_audit_target_created_index
  on public.community_moderation_action_audit (target_type, target_id, created_at desc);

alter table public.community_member_restrictions enable row level security;
alter table public.community_moderation_action_audit enable row level security;

-- No client policies: both tables are deliberately deny-by-default.

create or replace function public.is_community_member_posting_restricted(target_user_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.community_member_restrictions as restriction
    where restriction.user_id = target_user_id
      and restriction.scope = 'posting'
      and restriction.status = 'active'
      and (restriction.expires_at is null or restriction.expires_at > now())
  );
$$;
revoke all on function public.is_community_member_posting_restricted(uuid) from public;
grant execute on function public.is_community_member_posting_restricted(uuid) to authenticated;

create or replace function public.can_post_to_community_group(target_group_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.community_groups as community_group
    join public.community_group_memberships as membership on membership.group_id = community_group.id
    where community_group.id = target_group_id
      and community_group.moderation_state = 'active'
      and membership.user_id = (select auth.uid())
      and not public.is_community_member_posting_restricted((select auth.uid()))
      and (
        community_group.posting_permission = 'members'
        or membership.role in ('owner', 'admin', 'moderator')
      )
  );
$$;
revoke all on function public.can_post_to_community_group(uuid) from public;
grant execute on function public.can_post_to_community_group(uuid) to authenticated;

-- Group and event creation use SECURITY DEFINER RPCs, so ordinary INSERT RLS
-- is not enough to enforce a posting restriction. Keep the same guard at the
-- table boundary for those RPC-backed creation paths.
create or replace function public.prevent_restricted_community_content_creation()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare
  actor_id uuid := (select auth.uid());
begin
  if actor_id is null then raise exception 'authentication required'; end if;
  if public.is_community_member_posting_restricted(actor_id) then
    raise exception 'member posting is restricted';
  end if;
  if not exists (
    select 1 from public.community_profiles
    where user_id = actor_id and moderation_state = 'active'
  ) then
    raise exception 'active profile required';
  end if;
  return new;
end;
$$;

drop trigger if exists prevent_restricted_community_group_creation on public.community_groups;
create trigger prevent_restricted_community_group_creation
before insert on public.community_groups
for each row execute procedure public.prevent_restricted_community_content_creation();
drop trigger if exists prevent_restricted_community_event_creation on public.community_events;
create trigger prevent_restricted_community_event_creation
before insert on public.community_events
for each row execute procedure public.prevent_restricted_community_content_creation();

-- A member cannot forge a moderation-state update through PostgREST. The
-- Worker service role remains the only caller that can change this field.
create or replace function public.prevent_client_moderation_state_updates()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if new.moderation_state is distinct from old.moderation_state
     and coalesce(current_setting('request.jwt.claim.role', true), '') <> 'service_role' then
    raise exception 'moderation state is server managed';
  end if;
  return new;
end;
$$;

drop trigger if exists prevent_client_profile_moderation_state_updates on public.community_profiles;
create trigger prevent_client_profile_moderation_state_updates
before update on public.community_profiles
for each row execute procedure public.prevent_client_moderation_state_updates();
drop trigger if exists prevent_client_post_moderation_state_updates on public.community_posts;
create trigger prevent_client_post_moderation_state_updates
before update on public.community_posts
for each row execute procedure public.prevent_client_moderation_state_updates();
drop trigger if exists prevent_client_comment_moderation_state_updates on public.community_comments;
create trigger prevent_client_comment_moderation_state_updates
before update on public.community_comments
for each row execute procedure public.prevent_client_moderation_state_updates();
drop trigger if exists prevent_client_group_moderation_state_updates on public.community_groups;
create trigger prevent_client_group_moderation_state_updates
before update on public.community_groups
for each row execute procedure public.prevent_client_moderation_state_updates();

-- Enforce restrictions and moderation visibility at the database layer.
drop policy if exists "Authenticated users can view visible community profiles" on public.community_profiles;
create policy "Authenticated users can view visible community profiles"
on public.community_profiles for select to authenticated
using (
  user_id = (select auth.uid())
  or (
    moderation_state = 'active'
    and is_public
    and public.can_view_community_user(user_id)
  )
);

drop policy if exists "Authenticated users can view visible posts" on public.community_posts;
create policy "Authenticated users can view visible posts"
on public.community_posts for select to authenticated
using (
  moderation_state = 'active'
  and public.can_view_community_user(author_id)
  and exists (
    select 1 from public.community_profiles as profile
    where profile.user_id = author_id
      and profile.is_public
      and profile.moderation_state = 'active'
  )
  and (group_id is null or exists (
    select 1 from public.community_groups as community_group
    where community_group.id = group_id and community_group.moderation_state = 'active'
  ))
);

drop policy if exists "Authenticated users can view visible comments" on public.community_comments;
create policy "Authenticated users can view visible comments"
on public.community_comments for select to authenticated
using (
  moderation_state = 'active'
  and public.can_view_community_user(author_id)
  and exists (
    select 1 from public.community_profiles as author_profile
    where author_profile.user_id = author_id
      and author_profile.is_public
      and author_profile.moderation_state = 'active'
  )
  and exists (
    select 1
    from public.community_posts as post
    join public.community_profiles as post_author on post_author.user_id = post.author_id
    where post.id = post_id
      and post.moderation_state = 'active'
      and post_author.is_public
      and post_author.moderation_state = 'active'
  )
);

drop policy if exists "Authenticated users can view community groups" on public.community_groups;
create policy "Authenticated users can view community groups"
on public.community_groups for select to authenticated
using (moderation_state = 'active');

drop policy if exists "Users can create their own posts" on public.community_posts;
create policy "Users can create their own posts"
on public.community_posts for insert to authenticated
with check (
  (select auth.uid()) = author_id
  and not public.is_community_member_posting_restricted((select auth.uid()))
  and exists (
    select 1 from public.community_profiles as profile
    where profile.user_id = (select auth.uid()) and profile.moderation_state = 'active'
  )
  and (group_id is null or public.can_post_to_community_group(group_id))
);

drop policy if exists "Users can create their own comments" on public.community_comments;
create policy "Users can create their own comments"
on public.community_comments for insert to authenticated
with check (
  (select auth.uid()) = author_id
  and not public.is_community_member_posting_restricted((select auth.uid()))
  and exists (
    select 1 from public.community_profiles as profile
    where profile.user_id = (select auth.uid()) and profile.moderation_state = 'active'
  )
  and exists (
    select 1 from public.community_posts as post
    where post.id = post_id and post.moderation_state = 'active'
      and (post.group_id is null or public.can_post_to_community_group(post.group_id))
  )
);

drop policy if exists "Authenticated users can view visible post media" on public.community_post_media;
create policy "Authenticated users can view visible post media"
on public.community_post_media for select to authenticated
using (
  exists (
    select 1 from public.community_posts as post
    join public.community_profiles as profile on profile.user_id = post.author_id
    where post.id = post_id
      and post.moderation_state = 'active'
      and profile.is_public
      and profile.moderation_state = 'active'
      and public.can_view_community_user(post.author_id)
  )
);

drop policy if exists "Authenticated users can view likes on visible posts" on public.community_post_likes;
create policy "Authenticated users can view likes on visible posts"
on public.community_post_likes for select to authenticated
using (
  exists (
    select 1 from public.community_posts as post
    join public.community_profiles as profile on profile.user_id = post.author_id
    where post.id = post_id
      and post.moderation_state = 'active'
      and profile.is_public
      and profile.moderation_state = 'active'
      and public.can_view_community_user(post.author_id)
  )
);

drop policy if exists "Authenticated users can view edit history for visible posts" on public.community_post_edit_history;
create policy "Authenticated users can view edit history for visible posts"
on public.community_post_edit_history for select to authenticated
using (
  exists (
    select 1 from public.community_posts as post
    join public.community_profiles as profile on profile.user_id = post.author_id
    where post.id = post_id
      and post.moderation_state = 'active'
      and profile.is_public
      and profile.moderation_state = 'active'
      and public.can_view_community_user(post.author_id)
  )
);

drop policy if exists "Authenticated users can read permitted profile media" on storage.objects;
create policy "Authenticated users can read permitted profile media"
on storage.objects for select to authenticated
using (
  bucket_id = 'profile-media'
  and (
    (storage.foldername(name))[1] = (select auth.jwt()->>'sub')
    or exists (
      select 1 from public.community_profiles as profile
      where (profile.cover_path = name or profile.avatar_path = name)
        and profile.is_public
        and profile.moderation_state = 'active'
        and public.can_view_community_user(profile.user_id)
    )
  )
);

-- Moderation notifications do not reveal the reviewer's identity when that
-- profile is private, but always remain visible to their intended recipient.
alter table public.community_notifications drop constraint if exists community_notifications_type_check;
alter table public.community_notifications add constraint community_notifications_type_check
  check (type in (
    'follow', 'post_like', 'post_comment', 'group_join_approved', 'group_join_rejected',
    'moderation_content_removed', 'moderation_content_restored',
    'moderation_member_restricted', 'moderation_member_restriction_revoked'
  ));
alter table public.community_notifications
  add column if not exists body text;
alter table public.community_notifications
  drop constraint if exists community_notifications_body_length_check;
alter table public.community_notifications
  add constraint community_notifications_body_length_check
  check (body is null or char_length(trim(body)) <= 500);

drop policy if exists "Users can view their visible notifications" on public.community_notifications;
create policy "Users can view their visible notifications"
on public.community_notifications for select to authenticated
using (
  recipient_id = (select auth.uid())
  and (
    type in (
      'group_join_approved', 'group_join_rejected',
      'moderation_content_removed', 'moderation_content_restored',
      'moderation_member_restricted', 'moderation_member_restriction_revoked'
    )
    or public.can_view_community_user(actor_id)
  )
);

create or replace function public.apply_community_moderation_action(
  target_report_id uuid,
  acting_moderator_id uuid,
  requested_action text,
  moderation_note text default null,
  restriction_hours integer default null,
  member_notice text default null
)
returns void language plpgsql security definer set search_path = '' as $$
declare
  report_row public.community_reports;
  staff_role text;
  subject_id uuid;
  current_state text;
  restriction_row public.community_member_restrictions;
  reversed_action uuid;
  audit_id uuid;
  normalized_note text := nullif(trim(moderation_note), '');
  normalized_member_notice text := nullif(trim(member_notice), '');
begin
  if requested_action not in ('remove_content', 'restore_content', 'restrict_author', 'revoke_author_restriction') then
    raise exception 'invalid moderation action';
  end if;
  if normalized_note is not null and char_length(normalized_note) > 1000 then
    raise exception 'moderation note is too long';
  end if;
  if normalized_member_notice is not null and char_length(normalized_member_notice) > 500 then
    raise exception 'member notice is too long';
  end if;
  if restriction_hours is not null and (restriction_hours < 1 or restriction_hours > 8760) then
    raise exception 'restriction duration is invalid';
  end if;

  select role into staff_role from public.community_moderator_roles where user_id = acting_moderator_id;
  if staff_role is null then raise exception 'moderator role required'; end if;
  if staff_role not in ('admin', 'moderator') then
    raise exception 'enforcement role required';
  end if;

  select * into report_row from public.community_reports where id = target_report_id for update;
  if report_row.id is null then raise exception 'report not found'; end if;
  if report_row.target_type not in ('profile', 'post', 'comment', 'group') then
    raise exception 'target type is not supported by this action';
  end if;

  if report_row.target_type = 'profile' then
    select user_id, moderation_state into subject_id, current_state
    from public.community_profiles where user_id = report_row.target_id for update;
  elsif report_row.target_type = 'post' then
    select author_id, moderation_state into subject_id, current_state
    from public.community_posts where id = report_row.target_id for update;
  elsif report_row.target_type = 'comment' then
    select author_id, moderation_state into subject_id, current_state
    from public.community_comments where id = report_row.target_id for update;
  else
    select created_by, moderation_state into subject_id, current_state
    from public.community_groups where id = report_row.target_id for update;
  end if;
  if current_state is null then raise exception 'reported target is no longer available'; end if;

  if requested_action = 'remove_content' then
    if report_row.target_type = 'profile' then
      update public.community_profiles set moderation_state = 'restricted' where user_id = report_row.target_id;
    elsif report_row.target_type = 'post' then
      update public.community_posts set moderation_state = 'removed' where id = report_row.target_id;
    elsif report_row.target_type = 'comment' then
      update public.community_comments set moderation_state = 'removed' where id = report_row.target_id;
    else
      update public.community_groups set moderation_state = 'removed' where id = report_row.target_id;
    end if;
    insert into public.community_moderation_action_audit (report_id, moderator_id, action, target_type, target_id, subject_user_id, note, member_notice)
    values (report_row.id, acting_moderator_id, 'content_removed', report_row.target_type, report_row.target_id, subject_id, normalized_note, normalized_member_notice)
    returning id into audit_id;
    if subject_id is not null and subject_id <> acting_moderator_id then
      insert into public.community_notifications (recipient_id, actor_id, type, body, event_key)
      values (subject_id, acting_moderator_id, 'moderation_content_removed', normalized_member_notice, 'moderation:' || audit_id::text)
      on conflict (recipient_id, event_key) where event_key is not null do nothing;
    end if;
  elsif requested_action = 'restore_content' then
    select id into reversed_action from public.community_moderation_action_audit
    where target_type = report_row.target_type and target_id = report_row.target_id and action = 'content_removed'
    order by created_at desc limit 1;
    if reversed_action is null then raise exception 'no removed content action found'; end if;
    if report_row.target_type = 'profile' then
      update public.community_profiles set moderation_state = 'active' where user_id = report_row.target_id;
    elsif report_row.target_type = 'post' then
      update public.community_posts set moderation_state = 'active' where id = report_row.target_id;
    elsif report_row.target_type = 'comment' then
      update public.community_comments set moderation_state = 'active' where id = report_row.target_id;
    else
      update public.community_groups set moderation_state = 'active' where id = report_row.target_id;
    end if;
    insert into public.community_moderation_action_audit (report_id, moderator_id, action, target_type, target_id, subject_user_id, reverses_action_id, note, member_notice)
    values (report_row.id, acting_moderator_id, 'content_restored', report_row.target_type, report_row.target_id, subject_id, reversed_action, normalized_note, normalized_member_notice)
    returning id into audit_id;
    if subject_id is not null and subject_id <> acting_moderator_id then
      insert into public.community_notifications (recipient_id, actor_id, type, body, event_key)
      values (subject_id, acting_moderator_id, 'moderation_content_restored', normalized_member_notice, 'moderation:' || audit_id::text)
      on conflict (recipient_id, event_key) where event_key is not null do nothing;
    end if;
  elsif requested_action = 'restrict_author' then
    if subject_id is null then raise exception 'reported target has no member to restrict'; end if;
    insert into public.community_member_restrictions (user_id, scope, expires_at)
    values (subject_id, 'posting', case when restriction_hours is null then null else now() + make_interval(hours => restriction_hours) end)
    on conflict (user_id, scope) where status = 'active' do update
      set expires_at = excluded.expires_at
    returning * into restriction_row;
    insert into public.community_moderation_action_audit (report_id, moderator_id, action, target_type, target_id, subject_user_id, restriction_id, note, member_notice)
    values (report_row.id, acting_moderator_id, 'member_restricted', report_row.target_type, report_row.target_id, subject_id, restriction_row.id, normalized_note, normalized_member_notice)
    returning id into audit_id;
    if subject_id <> acting_moderator_id then
      insert into public.community_notifications (recipient_id, actor_id, type, body, event_key)
      values (subject_id, acting_moderator_id, 'moderation_member_restricted', normalized_member_notice, 'moderation:' || audit_id::text)
      on conflict (recipient_id, event_key) where event_key is not null do nothing;
    end if;
  else
    if subject_id is null then raise exception 'reported target has no member restriction'; end if;
    select * into restriction_row from public.community_member_restrictions
    where user_id = subject_id and scope = 'posting' and status = 'active' for update;
    if restriction_row.id is null then raise exception 'no active posting restriction found'; end if;
    update public.community_member_restrictions
    set status = 'revoked', revoked_at = now(), revoked_by = acting_moderator_id
    where id = restriction_row.id;
    select id into reversed_action from public.community_moderation_action_audit
    where restriction_id = restriction_row.id and action = 'member_restricted'
    order by created_at desc limit 1;
    insert into public.community_moderation_action_audit (report_id, moderator_id, action, target_type, target_id, subject_user_id, restriction_id, reverses_action_id, note, member_notice)
    values (report_row.id, acting_moderator_id, 'member_restriction_revoked', report_row.target_type, report_row.target_id, subject_id, restriction_row.id, reversed_action, normalized_note, normalized_member_notice)
    returning id into audit_id;
    if subject_id <> acting_moderator_id then
      insert into public.community_notifications (recipient_id, actor_id, type, body, event_key)
      values (subject_id, acting_moderator_id, 'moderation_member_restriction_revoked', normalized_member_notice, 'moderation:' || audit_id::text)
      on conflict (recipient_id, event_key) where event_key is not null do nothing;
    end if;
  end if;
end;
$$;

revoke all on function public.apply_community_moderation_action(uuid, uuid, text, text, integer, text) from public;
grant execute on function public.apply_community_moderation_action(uuid, uuid, text, text, integer, text) to service_role;
