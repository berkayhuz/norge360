-- A join decision is a durable, recipient-only notification. The event key makes
-- retries idempotent while still allowing a later, newly submitted request to notify again.
alter table public.community_notifications
  drop constraint if exists community_notifications_type_check;
alter table public.community_notifications
  add constraint community_notifications_type_check
  check (type in ('follow', 'post_like', 'post_comment', 'group_join_approved', 'group_join_rejected'));

alter table public.community_notifications
  add column if not exists group_id uuid references public.community_groups(id) on delete cascade,
  add column if not exists event_key text;

create unique index if not exists community_notifications_recipient_event_key_idx
  on public.community_notifications (recipient_id, event_key)
  where event_key is not null;

-- Group decision notifications intentionally remain visible even where the reviewing
-- administrator has a private profile: the row does not disclose their identity.
drop policy if exists "Users can view their visible notifications" on public.community_notifications;
create policy "Users can view their visible notifications"
on public.community_notifications for select to authenticated
using (
  recipient_id = (select auth.uid())
  and (
    type in ('group_join_approved', 'group_join_rejected')
    or public.can_view_community_user(actor_id)
  )
);

create or replace function public.review_community_group_join_request(
  target_group_id uuid,
  target_user_id uuid,
  decision text
)
returns void language plpgsql security definer set search_path = '' as $$
declare
  actor_id uuid := (select auth.uid());
  actor_role text;
  request_time timestamptz;
begin
  select role into actor_role from public.community_group_memberships
  where group_id = target_group_id and user_id = actor_id;
  if actor_role not in ('owner', 'admin') then raise exception 'insufficient group permission'; end if;
  if decision not in ('approved', 'rejected') then raise exception 'invalid request decision'; end if;

  select requested_at into request_time from public.community_group_join_requests
  where group_id = target_group_id and user_id = target_user_id and status = 'pending';
  if request_time is null then raise exception 'pending join request not found'; end if;

  if decision = 'approved' then
    insert into public.community_group_memberships (group_id, user_id, role)
    values (target_group_id, target_user_id, 'member')
    on conflict (group_id, user_id) do nothing;
  end if;

  update public.community_group_join_requests
  set status = decision, reviewed_at = now(), reviewed_by = actor_id
  where group_id = target_group_id and user_id = target_user_id;

  insert into public.community_notifications (recipient_id, actor_id, type, group_id, event_key)
  values (
    target_user_id,
    actor_id,
    case when decision = 'approved' then 'group_join_approved' else 'group_join_rejected' end,
    target_group_id,
    'group-join:' || target_group_id::text || ':' || target_user_id::text || ':' || extract(epoch from request_time)::bigint::text || ':' || decision
  )
  on conflict (recipient_id, event_key) where event_key is not null do nothing;
end;
$$;

revoke all on function public.review_community_group_join_request(uuid, uuid, text) from public;
grant execute on function public.review_community_group_join_request(uuid, uuid, text) to authenticated;
