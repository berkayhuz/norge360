-- Direct-message reports are write-only for members and visible only through
-- the privileged, audited moderation workflow.

alter table public.community_reports
  drop constraint if exists community_reports_target_type_check;
alter table public.community_reports
  add constraint community_reports_target_type_check
  check (target_type in ('profile', 'post', 'comment', 'event', 'group', 'message'));

create unique index if not exists community_open_message_report_per_reporter_idx
  on public.community_reports (reporter_id, target_id)
  where target_type = 'message' and review_status = 'open';

create or replace function public.report_community_message(
  target_message_id uuid,
  report_reason text,
  report_details text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  message_row public.community_messages;
  normalized_reason text := trim(coalesce(report_reason, ''));
  normalized_details text := nullif(trim(report_details), '');
begin
  select * into message_row from public.community_messages where id = target_message_id;
  if caller_id is null or message_row.id is null or message_row.sender_id = caller_id then
    raise exception 'message report unavailable';
  end if;
  if char_length(normalized_reason) not between 1 and 120
     or (normalized_details is not null and char_length(normalized_details) > 1000) then
    raise exception 'invalid message report';
  end if;
  if not exists (
    select 1 from public.community_conversation_members as member
    where member.conversation_id = message_row.conversation_id
      and member.user_id = caller_id
      and member.status = 'active'
  ) or not public.can_view_community_user(message_row.sender_id) then
    raise exception 'message report unavailable';
  end if;

  insert into public.community_reports (reporter_id, target_type, target_id, reason, details)
  values (caller_id, 'message', target_message_id, normalized_reason, normalized_details)
  on conflict (reporter_id, target_id) where target_type = 'message' and review_status = 'open'
  do nothing;
end;
$$;

revoke all on function public.report_community_message(uuid, text, text) from public;
grant execute on function public.report_community_message(uuid, text, text) to authenticated;
