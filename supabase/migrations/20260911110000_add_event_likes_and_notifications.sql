-- A like is a private subscription to an event. It is not an RSVP and it is
-- deliberately stored separately so a member can follow updates without
-- disclosing attendance.
create table if not exists public.community_event_likes (
  event_id uuid not null references public.community_events(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (event_id, user_id)
);

create index if not exists community_event_likes_event_idx
  on public.community_event_likes (event_id, created_at desc);

alter table public.community_event_likes enable row level security;

drop policy if exists "Members can view likes for visible events" on public.community_event_likes;
create policy "Members can view likes for visible events"
on public.community_event_likes for select to authenticated
using (
  exists (
    select 1 from public.community_events as event
    where event.id = community_event_likes.event_id
      and public.can_view_community_user(event.host_id)
      and (event.group_id is null or public.is_community_group_member(event.group_id))
  )
);

-- Event membership is changed only by this RPC; the client never supplies the
-- liking member ID and direct table writes remain unavailable.
create or replace function public.set_community_event_like(target_event_id uuid, next_liked boolean)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  actor_id uuid := (select auth.uid());
  target_event public.community_events;
begin
  if actor_id is null then raise exception 'authentication required'; end if;
  select * into target_event from public.community_events where id = target_event_id;
  if target_event.id is null or target_event.starts_at <= now() then raise exception 'event unavailable'; end if;
  if not public.can_view_community_user(target_event.host_id) then raise exception 'event unavailable'; end if;
  if target_event.group_id is not null and not public.is_community_group_member(target_event.group_id) then
    raise exception 'event unavailable';
  end if;

  if next_liked then
    insert into public.community_event_likes (event_id, user_id)
    values (target_event_id, actor_id)
    on conflict (event_id, user_id) do nothing;
  else
    delete from public.community_event_likes where event_id = target_event_id and user_id = actor_id;
  end if;
end;
$$;

alter table public.community_notifications
  add column if not exists event_id uuid references public.community_events(id) on delete cascade;
alter table public.community_notifications drop constraint if exists community_notifications_type_check;
alter table public.community_notifications add constraint community_notifications_type_check
  check (type in (
    'follow', 'post_like', 'post_comment', 'group_join_approved', 'group_join_rejected',
    'moderation_content_removed', 'moderation_content_restored',
    'moderation_member_restricted', 'moderation_member_restriction_revoked',
    'message_request', 'direct_message', 'event_updated', 'event_reminder'
  ));

-- The event host is the actor. A liked event changing its meaningful public
-- details creates a privacy-safe in-app notification for each current liker.
create or replace function public.notify_community_event_likers_of_update()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.title is not distinct from old.title
     and new.description is not distinct from old.description
     and new.area_label is not distinct from old.area_label
     and new.starts_at is not distinct from old.starts_at
     and new.capacity is not distinct from old.capacity then
    return new;
  end if;

  insert into public.community_notifications (recipient_id, actor_id, type, event_id, event_key)
  select liked.user_id, new.host_id, 'event_updated', new.id,
         'event-update:' || new.id::text || ':' || new.updated_at::text
  from public.community_event_likes as liked
  where liked.event_id = new.id and liked.user_id <> new.host_id;
  return new;
end;
$$;

drop trigger if exists community_event_like_update_notification on public.community_events;
create trigger community_event_like_update_notification
after update on public.community_events
for each row execute procedure public.notify_community_event_likers_of_update();

-- Called by the secret-bearing scheduled Worker. The event key makes a reminder
-- idempotent per event and member; it never includes event details in the row.
create or replace function public.queue_community_event_reminders()
returns integer language plpgsql security definer set search_path = '' as $$
declare inserted_count integer;
begin
  insert into public.community_notifications (recipient_id, actor_id, type, event_id, event_key)
  select liked.user_id, event.host_id, 'event_reminder', event.id,
         'event-reminder:' || event.id::text
  from public.community_events as event
  join public.community_event_likes as liked on liked.event_id = event.id
  where event.starts_at > now()
    and event.starts_at <= now() + interval '24 hours'
    and liked.user_id <> event.host_id
  on conflict (recipient_id, event_key) where event_key is not null do nothing;
  get diagnostics inserted_count = row_count;
  return inserted_count;
end;
$$;

revoke all on table public.community_event_likes from public, authenticated;
grant select on table public.community_event_likes to authenticated;
revoke all on function public.set_community_event_like(uuid, boolean) from public;
grant execute on function public.set_community_event_like(uuid, boolean) to authenticated;
revoke all on function public.queue_community_event_reminders() from public, authenticated;
grant execute on function public.queue_community_event_reminders() to service_role;
revoke all on function public.notify_community_event_likers_of_update() from public;
