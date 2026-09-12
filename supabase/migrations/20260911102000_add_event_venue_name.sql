-- An optional, public venue name complements the deliberately approximate
-- area. It must never be used for a private address or precise live location.
alter table public.community_events
  add column if not exists venue_name text
  check (venue_name is null or char_length(trim(venue_name)) between 1 and 120);

create or replace function public.create_community_event(
  event_title text, event_description text, event_area_label text,
  event_starts_at timestamptz, event_capacity integer default null,
  event_venue_name text default null
)
returns public.community_events
language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := (select auth.uid()); normalized_area text := trim(event_area_label); normalized_venue text := nullif(trim(event_venue_name), ''); created_event public.community_events;
begin
  if actor_id is null then raise exception 'authentication required'; end if;
  if not exists (select 1 from public.community_profiles where user_id = actor_id) then raise exception 'profile required'; end if;
  if event_starts_at < now() + interval '15 minutes' or event_starts_at > now() + interval '366 days' then raise exception 'invalid event time'; end if;
  if normalized_area ~ '[0-9@]' or normalized_area ~* '(https?://|www\\.|street|road|address|gate|gata|vei|veien)' then raise exception 'use an approximate public area, not an address'; end if;
  if normalized_venue is not null and (char_length(normalized_venue) > 120 or normalized_venue ~ '[0-9@]' or normalized_venue ~* '(https?://|www\\.|address|gate|gata|vei|veien)') then raise exception 'use a public venue name, not an address'; end if;
  insert into public.community_events (host_id, title, description, area_label, venue_name, starts_at, capacity)
  values (actor_id, trim(event_title), trim(event_description), normalized_area, normalized_venue, event_starts_at, event_capacity) returning * into created_event;
  return created_event;
end;
$$;

revoke all on function public.create_community_event(text, text, text, timestamptz, integer, text) from public;
grant execute on function public.create_community_event(text, text, text, timestamptz, integer, text) to authenticated;

create or replace function public.create_community_group_event(
  event_group_id uuid, event_title text, event_description text, event_area_label text,
  event_starts_at timestamptz, event_capacity integer default null, event_venue_name text default null
)
returns public.community_events
language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := (select auth.uid()); actor_role text; normalized_venue text := nullif(trim(event_venue_name), ''); created_event public.community_events;
begin
  if actor_id is null then raise exception 'authentication required'; end if;
  select role into actor_role from public.community_group_memberships where group_id = event_group_id and user_id = actor_id;
  if actor_role not in ('owner', 'admin', 'moderator') then raise exception 'insufficient group permission'; end if;
  if char_length(trim(event_title)) not between 3 and 120 or char_length(trim(event_description)) not between 10 and 4000 then raise exception 'invalid event content'; end if;
  if char_length(trim(event_area_label)) not between 2 and 160 or trim(event_area_label) ~ '[0-9@]' then raise exception 'invalid approximate area'; end if;
  if normalized_venue is not null and (char_length(normalized_venue) > 120 or normalized_venue ~ '[0-9@]') then raise exception 'invalid public venue name'; end if;
  if event_starts_at <= now() + interval '15 minutes' then raise exception 'event must start in the future'; end if;
  if event_capacity is not null and event_capacity not between 1 and 500 then raise exception 'invalid event capacity'; end if;
  insert into public.community_events (host_id, group_id, title, description, area_label, venue_name, starts_at, capacity)
  values (actor_id, event_group_id, trim(event_title), trim(event_description), trim(event_area_label), normalized_venue, event_starts_at, event_capacity) returning * into created_event;
  return created_event;
end;
$$;

revoke all on function public.create_community_group_event(uuid, text, text, text, timestamptz, integer, text) from public;
grant execute on function public.create_community_group_event(uuid, text, text, text, timestamptz, integer, text) to authenticated;
