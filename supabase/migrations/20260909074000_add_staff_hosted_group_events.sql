-- Group events are intentionally more conservative than general events:
-- only an owner, admin, or moderator may host one, and group membership is
-- enforced by the existing events RLS policy before anyone can view or RSVP.

create or replace function public.create_community_group_event(
  event_group_id uuid,
  event_title text,
  event_description text,
  event_area_label text,
  event_starts_at timestamptz,
  event_capacity integer default null
)
returns public.community_events
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  actor_role text;
  created_event public.community_events;
begin
  if actor_id is null then raise exception 'authentication required'; end if;

  select role into actor_role
  from public.community_group_memberships
  where group_id = event_group_id and user_id = actor_id;

  if actor_role not in ('owner', 'admin', 'moderator') then
    raise exception 'insufficient group permission';
  end if;
  if char_length(trim(event_title)) not between 3 and 120 then raise exception 'invalid event title'; end if;
  if char_length(trim(event_description)) not between 10 and 4000 then raise exception 'invalid event description'; end if;
  if char_length(trim(event_area_label)) not between 2 and 160 then raise exception 'invalid approximate area'; end if;
  if event_starts_at <= now() + interval '15 minutes' then raise exception 'event must start in the future'; end if;
  if event_capacity is not null and event_capacity not between 1 and 500 then raise exception 'invalid event capacity'; end if;

  insert into public.community_events (
    host_id, group_id, title, description, area_label, starts_at, capacity
  ) values (
    actor_id,
    event_group_id,
    trim(event_title),
    trim(event_description),
    trim(event_area_label),
    event_starts_at,
    event_capacity
  ) returning * into created_event;

  return created_event;
end;
$$;

revoke all on function public.create_community_group_event(uuid, text, text, text, timestamptz, integer) from public;
grant execute on function public.create_community_group_event(uuid, text, text, text, timestamptz, integer) to authenticated;
