-- Complete the safety boundary required before group chat is exposed in iOS.

alter table public.community_group_chat_messages
  add column if not exists moderation_state text not null default 'active';
alter table public.community_group_chat_messages
  drop constraint if exists community_group_chat_messages_moderation_state_check;
alter table public.community_group_chat_messages
  add constraint community_group_chat_messages_moderation_state_check
  check (moderation_state in ('active', 'removed'));

create table if not exists public.community_group_chat_message_member_hides (
  message_id uuid not null references public.community_group_chat_messages(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  hidden_at timestamptz not null default now(),
  primary key (message_id, user_id)
);
alter table public.community_group_chat_message_member_hides enable row level security;
revoke all on public.community_group_chat_message_member_hides from anon, authenticated;

alter table public.community_reports
  drop constraint if exists community_reports_target_type_check;
alter table public.community_reports
  add constraint community_reports_target_type_check
  check (target_type in ('profile', 'post', 'comment', 'event', 'group', 'message', 'group_message'));
create unique index if not exists community_open_group_message_report_per_reporter_idx
  on public.community_reports (reporter_id, target_id)
  where target_type = 'group_message' and review_status = 'open';

alter table public.community_moderation_action_audit
  drop constraint if exists community_moderation_action_audit_target_type_check;
alter table public.community_moderation_action_audit
  add constraint community_moderation_action_audit_target_type_check
  check (target_type in ('profile', 'post', 'comment', 'group', 'group_message'));

create or replace function public.list_community_group_chat_messages(target_group_id uuid)
returns table (
  id uuid, sender_id uuid, display_name text, username text, body text, created_at timestamptz
)
language plpgsql security definer set search_path = '' as $$
begin
  if not public.can_access_community_group_chat(target_group_id) then
    raise exception 'group chat unavailable';
  end if;
  return query
  select message.id, message.sender_id, profile.display_name, profile.username, message.body, message.created_at
  from public.community_group_chat_messages message
  join public.community_profiles profile on profile.user_id = message.sender_id
  where message.group_id = target_group_id
    and message.deleted_at is null
    and message.moderation_state = 'active'
    and profile.moderation_state = 'active'
    and public.can_view_community_user(message.sender_id)
    and not exists (
      select 1 from public.community_group_chat_message_member_hides hidden
      where hidden.message_id = message.id and hidden.user_id = (select auth.uid())
    )
  order by message.created_at asc limit 200;
end;
$$;

create or replace function public.send_community_group_chat_message(target_group_id uuid, message_body text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  caller_id uuid := (select auth.uid());
  normalized_body text := btrim(regexp_replace(coalesce(message_body, ''), '[[:space:]]+', ' ', 'g'));
  new_message_id uuid;
begin
  if caller_id is null or char_length(normalized_body) not between 1 and 2000
     or not public.can_access_community_group_chat(target_group_id)
     or public.is_community_member_posting_restricted(caller_id)
     or not exists (select 1 from public.community_profiles where user_id = caller_id and moderation_state = 'active') then
    raise exception 'group chat unavailable';
  end if;
  if (select count(*) from public.community_group_chat_messages
      where sender_id = caller_id and created_at > now() - interval '1 minute') >= 20 then
    raise exception 'group chat rate limit reached';
  end if;
  insert into public.community_group_chat_messages (group_id, sender_id, body)
  values (target_group_id, caller_id, normalized_body) returning id into new_message_id;
  return new_message_id;
end;
$$;

create or replace function public.hide_community_group_chat_message_for_member(target_message_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare message_row public.community_group_chat_messages;
begin
  select * into message_row from public.community_group_chat_messages where id = target_message_id;
  if message_row.id is null or not public.can_access_community_group_chat(message_row.group_id) then
    raise exception 'group chat message unavailable';
  end if;
  insert into public.community_group_chat_message_member_hides (message_id, user_id)
  values (target_message_id, (select auth.uid())) on conflict do nothing;
end;
$$;

create or replace function public.report_community_group_chat_message(
  target_message_id uuid, report_reason text, report_details text default null
)
returns void language plpgsql security definer set search_path = '' as $$
declare
  caller_id uuid := (select auth.uid());
  message_row public.community_group_chat_messages;
  normalized_reason text := btrim(coalesce(report_reason, ''));
  normalized_details text := nullif(btrim(report_details), '');
begin
  select * into message_row from public.community_group_chat_messages where id = target_message_id;
  if caller_id is null or message_row.id is null or message_row.sender_id = caller_id
     or not public.can_access_community_group_chat(message_row.group_id)
     or not public.can_view_community_user(message_row.sender_id) then
    raise exception 'group chat message report unavailable';
  end if;
  if char_length(normalized_reason) not between 1 and 120
     or (normalized_details is not null and char_length(normalized_details) > 1000) then
    raise exception 'invalid group chat message report';
  end if;
  insert into public.community_reports (reporter_id, target_type, target_id, reason, details)
  values (caller_id, 'group_message', target_message_id, normalized_reason, normalized_details)
  on conflict (reporter_id, target_id) where target_type = 'group_message' and review_status = 'open' do nothing;
end;
$$;

create or replace function public.apply_community_group_chat_moderation_action(
  target_report_id uuid, acting_moderator_id uuid, requested_action text,
  moderation_note text default null, restriction_hours integer default null, member_notice text default null
)
returns void language plpgsql security definer set search_path = '' as $$
declare
  report_row public.community_reports; message_row public.community_group_chat_messages;
  staff_role text; subject_id uuid; audit_id uuid; reversed_action uuid;
  restriction_row public.community_member_restrictions;
  normalized_note text := nullif(btrim(moderation_note), '');
  normalized_notice text := nullif(btrim(member_notice), '');
begin
  if requested_action not in ('remove_content', 'restore_content', 'restrict_author', 'revoke_author_restriction')
     or (restriction_hours is not null and (restriction_hours < 1 or restriction_hours > 8760)) then
    raise exception 'invalid moderation action';
  end if;
  select role into staff_role from public.community_moderator_roles where user_id = acting_moderator_id;
  if staff_role not in ('admin', 'moderator') then raise exception 'enforcement role required'; end if;
  select * into report_row from public.community_reports where id = target_report_id for update;
  if report_row.id is null or report_row.target_type <> 'group_message' then raise exception 'target type is not supported'; end if;
  select * into message_row from public.community_group_chat_messages where id = report_row.target_id for update;
  if message_row.id is null then raise exception 'reported target is no longer available'; end if;
  subject_id := message_row.sender_id;

  if requested_action = 'remove_content' then
    update public.community_group_chat_messages set moderation_state = 'removed', updated_at = now() where id = message_row.id;
    insert into public.community_moderation_action_audit (report_id, moderator_id, action, target_type, target_id, subject_user_id, note, member_notice)
    values (report_row.id, acting_moderator_id, 'content_removed', 'group_message', message_row.id, subject_id, normalized_note, normalized_notice) returning id into audit_id;
  elsif requested_action = 'restore_content' then
    select id into reversed_action from public.community_moderation_action_audit where target_type = 'group_message' and target_id = message_row.id and action = 'content_removed' order by created_at desc limit 1;
    if reversed_action is null then raise exception 'no removed content action found'; end if;
    update public.community_group_chat_messages set moderation_state = 'active', updated_at = now() where id = message_row.id;
    insert into public.community_moderation_action_audit (report_id, moderator_id, action, target_type, target_id, subject_user_id, reverses_action_id, note, member_notice)
    values (report_row.id, acting_moderator_id, 'content_restored', 'group_message', message_row.id, subject_id, reversed_action, normalized_note, normalized_notice) returning id into audit_id;
  elsif requested_action = 'restrict_author' then
    insert into public.community_member_restrictions (user_id, scope, expires_at)
    values (subject_id, 'posting', case when restriction_hours is null then null else now() + make_interval(hours => restriction_hours) end)
    on conflict (user_id, scope) where status = 'active' do update set expires_at = excluded.expires_at returning * into restriction_row;
    insert into public.community_moderation_action_audit (report_id, moderator_id, action, target_type, target_id, subject_user_id, restriction_id, note, member_notice)
    values (report_row.id, acting_moderator_id, 'member_restricted', 'group_message', message_row.id, subject_id, restriction_row.id, normalized_note, normalized_notice) returning id into audit_id;
  else
    select * into restriction_row from public.community_member_restrictions where user_id = subject_id and scope = 'posting' and status = 'active' for update;
    if restriction_row.id is null then raise exception 'no active posting restriction found'; end if;
    update public.community_member_restrictions set status = 'revoked', revoked_at = now(), revoked_by = acting_moderator_id where id = restriction_row.id;
    select id into reversed_action from public.community_moderation_action_audit where restriction_id = restriction_row.id and action = 'member_restricted' order by created_at desc limit 1;
    insert into public.community_moderation_action_audit (report_id, moderator_id, action, target_type, target_id, subject_user_id, restriction_id, reverses_action_id, note, member_notice)
    values (report_row.id, acting_moderator_id, 'member_restriction_revoked', 'group_message', message_row.id, subject_id, restriction_row.id, reversed_action, normalized_note, normalized_notice) returning id into audit_id;
  end if;
  if subject_id <> acting_moderator_id then
    insert into public.community_notifications (recipient_id, actor_id, type, body, event_key)
    values (subject_id, acting_moderator_id,
      case when requested_action = 'remove_content' then 'moderation_content_removed'
           when requested_action = 'restore_content' then 'moderation_content_restored'
           when requested_action = 'restrict_author' then 'moderation_member_restricted'
           else 'moderation_member_restriction_revoked' end,
      normalized_notice, 'moderation:' || audit_id::text)
    on conflict (recipient_id, event_key) where event_key is not null do nothing;
  end if;
end;
$$;

revoke all on function public.list_community_group_chat_messages(uuid) from public;
revoke all on function public.send_community_group_chat_message(uuid, text) from public;
revoke all on function public.hide_community_group_chat_message_for_member(uuid) from public;
revoke all on function public.report_community_group_chat_message(uuid, text, text) from public;
revoke all on function public.apply_community_group_chat_moderation_action(uuid, uuid, text, text, integer, text) from public;
grant execute on function public.list_community_group_chat_messages(uuid) to authenticated;
grant execute on function public.send_community_group_chat_message(uuid, text) to authenticated;
grant execute on function public.hide_community_group_chat_message_for_member(uuid) to authenticated;
grant execute on function public.report_community_group_chat_message(uuid, text, text) to authenticated;
grant execute on function public.apply_community_group_chat_moderation_action(uuid, uuid, text, text, integer, text) to service_role;
