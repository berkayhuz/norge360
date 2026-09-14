-- Account deletion is executed by the secret-bearing Worker, never by the
-- native client. Moderation/report records may need to outlive the account,
-- so retain the record while removing the deleted member's identity links.

alter table public.community_group_bans
  alter column created_by drop not null;
alter table public.community_group_bans
  drop constraint if exists community_group_bans_created_by_fkey;
alter table public.community_group_bans
  add constraint community_group_bans_created_by_fkey
  foreign key (created_by) references auth.users(id) on delete set null;

alter table public.community_group_moderation_audit
  alter column actor_id drop not null,
  alter column target_user_id drop not null;
alter table public.community_group_moderation_audit
  drop constraint if exists community_group_moderation_audit_actor_id_fkey,
  drop constraint if exists community_group_moderation_audit_target_user_id_fkey;
alter table public.community_group_moderation_audit
  add constraint community_group_moderation_audit_actor_id_fkey
  foreign key (actor_id) references auth.users(id) on delete set null,
  add constraint community_group_moderation_audit_target_user_id_fkey
  foreign key (target_user_id) references auth.users(id) on delete set null;

alter table public.community_group_removed_post_media
  alter column removed_by drop not null;
alter table public.community_group_removed_post_media
  drop constraint if exists community_group_removed_post_media_removed_by_fkey;
alter table public.community_group_removed_post_media
  add constraint community_group_removed_post_media_removed_by_fkey
  foreign key (removed_by) references auth.users(id) on delete set null;

alter table public.community_moderation_action_audit
  alter column moderator_id drop not null,
  alter column target_id drop not null;
alter table public.community_moderation_action_audit
  drop constraint if exists community_moderation_action_audit_moderator_id_fkey;
alter table public.community_moderation_action_audit
  add constraint community_moderation_action_audit_moderator_id_fkey
  foreign key (moderator_id) references auth.users(id) on delete set null;

alter table public.community_moderation_review_audit
  alter column moderator_id drop not null;
alter table public.community_moderation_review_audit
  drop constraint if exists community_moderation_review_audit_moderator_id_fkey;
alter table public.community_moderation_review_audit
  add constraint community_moderation_review_audit_moderator_id_fkey
  foreign key (moderator_id) references auth.users(id) on delete set null;

alter table public.community_reports
  alter column reporter_id drop not null,
  alter column target_id drop not null;
alter table public.community_reports
  drop constraint if exists community_reports_reporter_id_fkey;
alter table public.community_reports
  add constraint community_reports_reporter_id_fkey
  foreign key (reporter_id) references auth.users(id) on delete set null;

create or replace function public.prepare_community_account_deletion(account_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(current_setting('request.jwt.claim.role', true), '') <> 'service_role' then
    raise exception 'service role required';
  end if;
  if account_user_id is null then
    raise exception 'target user required';
  end if;
  if exists (
    select 1
    from public.community_group_memberships
    where user_id = account_user_id and role = 'owner'
  ) then
    raise exception 'owned groups require ownership transfer';
  end if;

  -- Keep moderation/report records available for the defined retention
  -- process, but remove direct identity references before auth.users is
  -- deleted. User-owned posts, profiles, plans, devices and relationships
  -- continue through their existing account cascade.
  update public.community_group_bans
  set created_by = null
  where created_by = account_user_id;

  update public.community_group_moderation_audit
  set actor_id = null
  where actor_id = account_user_id;
  update public.community_group_moderation_audit
  set target_user_id = null
  where target_user_id = account_user_id;

  update public.community_group_removed_post_media
  set removed_by = null
  where removed_by = account_user_id;

  update public.community_moderation_action_audit
  set moderator_id = null
  where moderator_id = account_user_id;

  update public.community_moderation_review_audit
  set moderator_id = null
  where moderator_id = account_user_id;

  update public.community_reports
  set reporter_id = null
  where reporter_id = account_user_id;

  -- A profile report target is the member UUID itself. Detach it before
  -- deleting auth.users so retained reports cannot identify the deleted user.
  update public.community_reports
  set target_id = null
  where target_type = 'profile' and target_id = account_user_id;

  update public.community_moderation_action_audit
  set target_id = null
  where target_type = 'profile' and target_id = account_user_id;
end;
$$;

revoke all on function public.prepare_community_account_deletion(uuid) from public, anon, authenticated;
grant execute on function public.prepare_community_account_deletion(uuid) to service_role;
