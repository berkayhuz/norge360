-- Rich event metadata and private event media.
-- Public events keep a broad meeting area. Street names are optional context,
-- but house numbers, URLs, and exact private addresses are rejected below.

alter table public.community_events
  add column if not exists county_code text,
  add column if not exists municipality_code text,
  add column if not exists district_name text,
  add column if not exists neighborhood_name text,
  add column if not exists street_name text,
  add column if not exists category text,
  add column if not exists theme text,
  add column if not exists format text,
  add column if not exists age_range text,
  add column if not exists alcohol_policy text,
  add column if not exists price_type text,
  add column if not exists language text,
  add column if not exists is_indoor boolean not null default true,
  add column if not exists is_family_friendly boolean not null default false,
  add column if not exists is_pet_friendly boolean not null default false,
  add column if not exists is_accessible boolean not null default false,
  add column if not exists food_provided boolean not null default false,
  add column if not exists registration_required boolean not null default false;

create index if not exists community_events_location_index
  on public.community_events (county_code, municipality_code, starts_at, id);

create index if not exists community_events_category_index
  on public.community_events (category, starts_at, id);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('event-media', 'event-media', false, 10485760, array['image/jpeg', 'image/png', 'image/heic'])
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create table if not exists public.community_event_media (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.community_events(id) on delete cascade,
  storage_path text not null unique check (char_length(trim(storage_path)) between 1 and 500),
  sort_order smallint not null check (sort_order between 0 and 5),
  width integer not null check (width between 1 and 10000),
  height integer not null check (height between 1 and 10000),
  created_at timestamptz not null default now(),
  unique (event_id, sort_order)
);

create index if not exists community_event_media_event_order_index
  on public.community_event_media (event_id, sort_order);

create or replace function public.enforce_community_event_media_limit()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if (
    select count(*)
    from public.community_event_media
    where event_id = new.event_id
  ) >= 6 then
    raise exception 'A community event can contain at most six images.';
  end if;
  return new;
end;
$$;

drop trigger if exists enforce_community_event_media_limit on public.community_event_media;
create trigger enforce_community_event_media_limit
before insert on public.community_event_media
for each row execute procedure public.enforce_community_event_media_limit();

alter table public.community_event_media enable row level security;

drop policy if exists "Authenticated users can view visible event media" on public.community_event_media;
create policy "Authenticated users can view visible event media"
on public.community_event_media for select to authenticated
using (
  exists (
    select 1
    from public.community_events as event
    where event.id = event_id
      and public.can_view_community_user(event.host_id)
      and (event.group_id is null or public.is_community_group_member(event.group_id))
  )
);

drop policy if exists "Hosts can attach media to their own events" on public.community_event_media;
create policy "Hosts can attach media to their own events"
on public.community_event_media for insert to authenticated
with check (
  exists (
    select 1
    from public.community_events as event
    where event.id = event_id and event.host_id = (select auth.uid())
  )
);

drop policy if exists "Hosts can delete media from their own events" on public.community_event_media;
create policy "Hosts can delete media from their own events"
on public.community_event_media for delete to authenticated
using (
  exists (
    select 1
    from public.community_events as event
    where event.id = event_id and event.host_id = (select auth.uid())
  )
);

drop policy if exists "Users can upload their own event media" on storage.objects;
create policy "Users can upload their own event media"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'event-media'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists "Authenticated users can read permitted event media" on storage.objects;
create policy "Authenticated users can read permitted event media"
on storage.objects for select to authenticated
using (
  bucket_id = 'event-media'
  and (
    (storage.foldername(name))[1] = (select auth.uid())::text
    or exists (
      select 1
      from public.community_event_media as media
      join public.community_events as event on event.id = media.event_id
      where media.storage_path = name
        and public.can_view_community_user(event.host_id)
        and (event.group_id is null or public.is_community_group_member(event.group_id))
    )
  )
);

drop policy if exists "Hosts can delete their own event media" on storage.objects;
create policy "Hosts can delete their own event media"
on storage.objects for delete to authenticated
using (
  bucket_id = 'event-media'
  and exists (
    select 1
    from public.community_event_media as media
    join public.community_events as event on event.id = media.event_id
    where media.storage_path = name and event.host_id = (select auth.uid())
  )
);

create or replace function public.validate_community_event_options(
  event_category text,
  event_format text,
  event_age_range text,
  event_alcohol_policy text,
  event_price_type text,
  event_language text
)
returns void
language plpgsql
immutable
set search_path = ''
as $$
begin
  if event_category is not null and event_category not in (
    'social', 'sports', 'workshop', 'culture', 'food', 'outdoors',
    'networking', 'family', 'volunteering', 'market', 'other'
  ) then raise exception 'invalid event category'; end if;
  if event_format is not null and event_format not in ('in_person', 'online', 'hybrid') then
    raise exception 'invalid event format';
  end if;
  if event_age_range is not null and event_age_range not in ('all_ages', '18_plus', '20_plus', 'family', 'custom') then
    raise exception 'invalid event age range';
  end if;
  if event_alcohol_policy is not null and event_alcohol_policy not in ('alcohol_free', 'optional', 'served', 'unknown') then
    raise exception 'invalid alcohol policy';
  end if;
  if event_price_type is not null and event_price_type not in ('free', 'paid', 'donation', 'member_only') then
    raise exception 'invalid event price type';
  end if;
  if event_language is not null and event_language not in ('english', 'norwegian', 'turkish', 'multilingual', 'other') then
    raise exception 'invalid event language';
  end if;
end;
$$;

create or replace function public.create_community_event(
  event_title text,
  event_description text,
  event_area_label text,
  event_starts_at timestamptz,
  event_capacity integer,
  event_venue_name text,
  event_county_code text,
  event_municipality_code text,
  event_district_name text,
  event_neighborhood_name text,
  event_street_name text,
  event_category text,
  event_theme text,
  event_format text,
  event_age_range text,
  event_alcohol_policy text,
  event_price_type text,
  event_language text,
  event_is_indoor boolean,
  event_is_family_friendly boolean,
  event_is_pet_friendly boolean,
  event_is_accessible boolean,
  event_food_provided boolean,
  event_registration_required boolean
)
returns public.community_events
language plpgsql security definer set search_path = '' as $$
declare
  actor_id uuid := (select auth.uid());
  normalized_area text := nullif(trim(event_area_label), '');
  normalized_venue text := nullif(trim(event_venue_name), '');
  normalized_street text := nullif(trim(event_street_name), '');
  created_event public.community_events;
begin
  if actor_id is null then raise exception 'authentication required'; end if;
  if not exists (select 1 from public.community_profiles where user_id = actor_id) then raise exception 'profile required'; end if;
  if char_length(trim(event_title)) not between 3 and 120 then raise exception 'invalid event title'; end if;
  if char_length(trim(event_description)) not between 10 and 4000 then raise exception 'invalid event description'; end if;
  if normalized_area is null or char_length(normalized_area) not between 2 and 160 then raise exception 'invalid event area'; end if;
  if event_starts_at <= now() + interval '15 minutes' or event_starts_at > now() + interval '366 days' then raise exception 'invalid event time'; end if;
  if event_capacity is not null and event_capacity not between 1 and 500 then raise exception 'invalid event capacity'; end if;
  if event_county_code is not null and event_county_code !~ '^[0-9]{2}$' then raise exception 'invalid county'; end if;
  if event_municipality_code is not null and event_municipality_code !~ '^[0-9]{4}$' then raise exception 'invalid municipality'; end if;
  if event_county_code is not null and event_municipality_code is not null
     and left(event_municipality_code, 2) <> event_county_code then raise exception 'municipality does not belong to county'; end if;
  if normalized_venue is not null and (char_length(normalized_venue) > 120 or normalized_venue ~ '[0-9@]' or normalized_venue ~* '(https?://|www\.|address|gate|gata|vei|veien)') then
    raise exception 'use a public venue name, not an address';
  end if;
  if normalized_street is not null and (char_length(normalized_street) > 120 or normalized_street ~ '[0-9@]' or normalized_street ~* '(https?://|www\.)') then
    raise exception 'use a street name without a precise address';
  end if;
  if event_theme is not null and char_length(trim(event_theme)) > 100 then raise exception 'event theme is too long'; end if;
  perform public.validate_community_event_options(event_category, event_format, event_age_range, event_alcohol_policy, event_price_type, event_language);
  insert into public.community_events (
    host_id, title, description, area_label, venue_name, county_code, municipality_code,
    district_name, neighborhood_name, street_name, category, theme, format, age_range,
    alcohol_policy, price_type, language, is_indoor, is_family_friendly, is_pet_friendly,
    is_accessible, food_provided, registration_required, starts_at, capacity
  ) values (
    actor_id, trim(event_title), trim(event_description), normalized_area, normalized_venue,
    event_county_code, event_municipality_code, nullif(trim(event_district_name), ''),
    nullif(trim(event_neighborhood_name), ''), normalized_street, nullif(trim(event_category), ''),
    nullif(trim(event_theme), ''), nullif(trim(event_format), ''), nullif(trim(event_age_range), ''),
    nullif(trim(event_alcohol_policy), ''), nullif(trim(event_price_type), ''), nullif(trim(event_language), ''),
    coalesce(event_is_indoor, true), coalesce(event_is_family_friendly, false), coalesce(event_is_pet_friendly, false),
    coalesce(event_is_accessible, false), coalesce(event_food_provided, false), coalesce(event_registration_required, false),
    event_starts_at, event_capacity
  ) returning * into created_event;
  return created_event;
end;
$$;

create or replace function public.create_community_group_event(
  event_group_id uuid,
  event_title text,
  event_description text,
  event_area_label text,
  event_starts_at timestamptz,
  event_capacity integer,
  event_venue_name text,
  event_county_code text,
  event_municipality_code text,
  event_district_name text,
  event_neighborhood_name text,
  event_street_name text,
  event_category text,
  event_theme text,
  event_format text,
  event_age_range text,
  event_alcohol_policy text,
  event_price_type text,
  event_language text,
  event_is_indoor boolean,
  event_is_family_friendly boolean,
  event_is_pet_friendly boolean,
  event_is_accessible boolean,
  event_food_provided boolean,
  event_registration_required boolean
)
returns public.community_events
language plpgsql security definer set search_path = '' as $$
declare
  actor_id uuid := (select auth.uid());
  actor_role text;
  normalized_area text := nullif(trim(event_area_label), '');
  normalized_venue text := nullif(trim(event_venue_name), '');
  normalized_street text := nullif(trim(event_street_name), '');
  created_event public.community_events;
begin
  if actor_id is null then raise exception 'authentication required'; end if;
  select role into actor_role from public.community_group_memberships where group_id = event_group_id and user_id = actor_id;
  if actor_role not in ('owner', 'admin', 'moderator') then raise exception 'insufficient group permission'; end if;
  if char_length(trim(event_title)) not between 3 and 120 or char_length(trim(event_description)) not between 10 and 4000 then raise exception 'invalid event content'; end if;
  if normalized_area is null or char_length(normalized_area) not between 2 and 160 then raise exception 'invalid event area'; end if;
  if event_starts_at <= now() + interval '15 minutes' or event_starts_at > now() + interval '366 days' then raise exception 'invalid event time'; end if;
  if event_capacity is not null and event_capacity not between 1 and 500 then raise exception 'invalid event capacity'; end if;
  if event_county_code is not null and event_county_code !~ '^[0-9]{2}$' then raise exception 'invalid county'; end if;
  if event_municipality_code is not null and event_municipality_code !~ '^[0-9]{4}$' then raise exception 'invalid municipality'; end if;
  if event_county_code is not null and event_municipality_code is not null
     and left(event_municipality_code, 2) <> event_county_code then raise exception 'municipality does not belong to county'; end if;
  if normalized_venue is not null and (char_length(normalized_venue) > 120 or normalized_venue ~ '[0-9@]' or normalized_venue ~* '(https?://|www\.|address|gate|gata|vei|veien)') then raise exception 'use a public venue name, not an address'; end if;
  if normalized_street is not null and (char_length(normalized_street) > 120 or normalized_street ~ '[0-9@]' or normalized_street ~* '(https?://|www\.)') then raise exception 'use a street name without a precise address'; end if;
  if event_theme is not null and char_length(trim(event_theme)) > 100 then raise exception 'event theme is too long'; end if;
  perform public.validate_community_event_options(event_category, event_format, event_age_range, event_alcohol_policy, event_price_type, event_language);
  insert into public.community_events (
    host_id, group_id, title, description, area_label, venue_name, county_code, municipality_code,
    district_name, neighborhood_name, street_name, category, theme, format, age_range,
    alcohol_policy, price_type, language, is_indoor, is_family_friendly, is_pet_friendly,
    is_accessible, food_provided, registration_required, starts_at, capacity
  ) values (
    actor_id, event_group_id, trim(event_title), trim(event_description), normalized_area, normalized_venue,
    event_county_code, event_municipality_code, nullif(trim(event_district_name), ''),
    nullif(trim(event_neighborhood_name), ''), normalized_street, nullif(trim(event_category), ''),
    nullif(trim(event_theme), ''), nullif(trim(event_format), ''), nullif(trim(event_age_range), ''),
    nullif(trim(event_alcohol_policy), ''), nullif(trim(event_price_type), ''), nullif(trim(event_language), ''),
    coalesce(event_is_indoor, true), coalesce(event_is_family_friendly, false), coalesce(event_is_pet_friendly, false),
    coalesce(event_is_accessible, false), coalesce(event_food_provided, false), coalesce(event_registration_required, false),
    event_starts_at, event_capacity
  ) returning * into created_event;
  return created_event;
end;
$$;

revoke all on function public.validate_community_event_options(text, text, text, text, text, text) from public, anon, authenticated;
revoke all on function public.create_community_event(text, text, text, timestamptz, integer, text, text, text, text, text, text, text, text, text, text, text, text, text, boolean, boolean, boolean, boolean, boolean, boolean) from public, anon, authenticated;
grant execute on function public.create_community_event(text, text, text, timestamptz, integer, text, text, text, text, text, text, text, text, text, text, text, text, text, boolean, boolean, boolean, boolean, boolean, boolean) to authenticated;
revoke all on function public.create_community_group_event(uuid, text, text, text, timestamptz, integer, text, text, text, text, text, text, text, text, text, text, text, text, text, boolean, boolean, boolean, boolean, boolean, boolean) from public, anon, authenticated;
grant execute on function public.create_community_group_event(uuid, text, text, text, timestamptz, integer, text, text, text, text, text, text, text, text, text, text, text, text, text, boolean, boolean, boolean, boolean, boolean, boolean) to authenticated;
