-- Community reports are write-only for members. Review is intentionally
-- server-mediated and auditable; no iOS client receives moderator authority.

alter table public.community_reports
  add column if not exists review_status text not null default 'open';

alter table public.community_reports
  drop constraint if exists community_reports_review_status_check;

alter table public.community_reports
  add constraint community_reports_review_status_check
  check (review_status in ('open', 'resolved', 'dismissed'));

alter table public.community_reports
  add column if not exists resolution_action text;

alter table public.community_reports
  drop constraint if exists community_reports_resolution_action_check;

alter table public.community_reports
  add constraint community_reports_resolution_action_check
  check (
    resolution_action is null
    or resolution_action in ('no_action', 'needs_investigation', 'member_contacted', 'escalated')
  );

alter table public.community_reports
  add column if not exists resolution_note text;

alter table public.community_reports
  drop constraint if exists community_reports_resolution_note_length_check;

alter table public.community_reports
  add constraint community_reports_resolution_note_length_check
  check (resolution_note is null or char_length(trim(resolution_note)) <= 1_000);

create index if not exists community_reports_review_queue_index
  on public.community_reports (review_status, created_at desc);

create table if not exists public.community_moderator_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('reviewer', 'moderator', 'admin')),
  granted_at timestamptz not null default now(),
  granted_by uuid references auth.users(id) on delete set null
);

create table if not exists public.community_moderation_review_audit (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references public.community_reports(id) on delete cascade,
  moderator_id uuid not null references auth.users(id) on delete restrict,
  previous_status text not null,
  next_status text not null,
  action text not null,
  note text,
  created_at timestamptz not null default now()
);

create index if not exists community_moderation_review_audit_report_created_index
  on public.community_moderation_review_audit (report_id, created_at desc);

alter table public.community_moderator_roles enable row level security;
alter table public.community_moderation_review_audit enable row level security;

-- No client policies are created for these tables. The Worker authenticates a
-- staff JWT and uses the service role only to call the guarded RPC below.

create or replace function public.resolve_community_report(
  target_report_id uuid,
  acting_moderator_id uuid,
  next_review_status text,
  next_resolution_action text,
  next_resolution_note text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing_report public.community_reports;
  moderator_role text;
begin
  if next_review_status not in ('resolved', 'dismissed') then
    raise exception 'invalid review status';
  end if;

  if next_resolution_action not in ('no_action', 'needs_investigation', 'member_contacted', 'escalated') then
    raise exception 'invalid resolution action';
  end if;

  if next_resolution_note is not null and char_length(trim(next_resolution_note)) > 1000 then
    raise exception 'resolution note is too long';
  end if;

  select role into moderator_role
  from public.community_moderator_roles
  where user_id = acting_moderator_id;

  if moderator_role is null then
    raise exception 'moderator role required';
  end if;

  select * into existing_report
  from public.community_reports
  where id = target_report_id
  for update;

  if existing_report.id is null then
    raise exception 'report not found';
  end if;

  if existing_report.review_status <> 'open' then
    raise exception 'report is already reviewed';
  end if;

  update public.community_reports
  set review_status = next_review_status,
      resolution_action = next_resolution_action,
      resolution_note = nullif(trim(next_resolution_note), ''),
      reviewed_at = now(),
      reviewed_by = acting_moderator_id
  where id = target_report_id;

  insert into public.community_moderation_review_audit (
    report_id, moderator_id, previous_status, next_status, action, note
  ) values (
    target_report_id,
    acting_moderator_id,
    existing_report.review_status,
    next_review_status,
    next_resolution_action,
    nullif(trim(next_resolution_note), '')
  );
end;
$$;

revoke all on function public.resolve_community_report(uuid, uuid, text, text, text) from public;
grant execute on function public.resolve_community_report(uuid, uuid, text, text, text) to service_role;
