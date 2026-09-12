-- Let members independently control which relocation/profile context fields
-- appear on their public profile. Existing profiles remain visible by default.
alter table public.community_profiles
  add column if not exists show_norway_status boolean not null default true;

alter table public.community_profiles
  add column if not exists show_location boolean not null default true;
