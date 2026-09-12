-- Events intentionally expose only an approximate public area. Creation and RSVP
-- updates go through security-definer functions so capacity and group visibility
-- cannot be bypassed by an untrusted client.
drop policy if exists "Authenticated users can view visible events" on public.community_events;
create policy "Authenticated users can view visible events"
on public.community_events for select to authenticated
using (
  public.can_view_community_user(host_id)
  and (
    group_id is null
    or public.is_community_group_member(group_id)
  )
);

drop policy if exists "Users can create their own events" on public.community_events;
drop policy if exists "Users can update their own events" on public.community_events;
drop policy if exists "Users can delete their own events" on public.community_events;
drop policy if exists "Users can create their own event RSVP" on public.community_event_rsvps;
drop policy if exists "Users can update their own event RSVP" on public.community_event_rsvps;
drop policy if exists "Users can delete their own event RSVP" on public.community_event_rsvps;

create or replace function public.create_community_event(
  event_title text,
  event_description text,
  event_area_label text,
  event_starts_at timestamptz,
  event_capacity integer default null
)
returns public.community_events
language plpgsql security definer set search_path = '' as $$
declare
  actor_id uuid := (select auth.uid());
  normalized_area text := trim(event_area_label);
  created_event public.community_events;
begin
  if actor_id is null then raise exception 'authentication required'; end if;
  if not exists (select 1 from public.community_profiles where user_id = actor_id) then raise exception 'profile required'; end if;
  if event_starts_at < now() + interval '15 minutes' then raise exception 'event must start at least 15 minutes from now'; end if;
  if event_starts_at > now() + interval '366 days' then raise exception 'event is too far in the future'; end if;
  -- Neighbourhood/city labels are allowed. Street-level locations, links, handles,
  -- and house numbers are not accepted in the public area field.
  if normalized_area ~ '[0-9@]' or normalized_area ~* '(https?://|www\\.|street|road|address|gate|gata|vei|veien)' then
    raise exception 'use an approximate public area, not an address';
  end if;

  insert into public.community_events (host_id, title, description, area_label, starts_at, capacity)
  values (actor_id, trim(event_title), trim(event_description), normalized_area, event_starts_at, event_capacity)
  returning * into created_event;
  return created_event;
end;
$$;

create or replace function public.set_community_event_rsvp(target_event_id uuid, next_status text)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  actor_id uuid := (select auth.uid());
  target_event public.community_events;
  going_count integer;
begin
  if actor_id is null then raise exception 'authentication required'; end if;
  if next_status not in ('interested', 'going', 'none') then raise exception 'invalid RSVP status'; end if;

  select * into target_event from public.community_events where id = target_event_id for update;
  if target_event.id is null then raise exception 'event not found'; end if;
  if target_event.starts_at <= now() then raise exception 'event has already started'; end if;
  if not public.can_view_community_user(target_event.host_id) then raise exception 'event unavailable'; end if;
  if target_event.group_id is not null and not public.is_community_group_member(target_event.group_id) then raise exception 'event unavailable'; end if;

  if next_status = 'none' then
    delete from public.community_event_rsvps where event_id = target_event_id and user_id = actor_id;
    return;
  end if;

  if next_status = 'going' and target_event.capacity is not null then
    select count(*) into going_count from public.community_event_rsvps
    where event_id = target_event_id and status = 'going' and user_id <> actor_id;
    if going_count >= target_event.capacity then raise exception 'event is at capacity'; end if;
  end if;

  insert into public.community_event_rsvps (event_id, user_id, status)
  values (target_event_id, actor_id, next_status)
  on conflict (event_id, user_id) do update set status = excluded.status, updated_at = now();
end;
$$;

create or replace function public.delete_community_event(target_event_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  delete from public.community_events
  where id = target_event_id and host_id = (select auth.uid());
  if not found then raise exception 'event not found or not owned'; end if;
end;
$$;

revoke all on function public.create_community_event(text, text, text, timestamptz, integer) from public;
grant execute on function public.create_community_event(text, text, text, timestamptz, integer) to authenticated;
revoke all on function public.set_community_event_rsvp(uuid, text) from public;
grant execute on function public.set_community_event_rsvp(uuid, text) to authenticated;
revoke all on function public.delete_community_event(uuid) from public;
grant execute on function public.delete_community_event(uuid) to authenticated;
