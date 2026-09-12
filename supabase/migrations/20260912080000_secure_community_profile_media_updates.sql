-- Profile media replacement must update the profile row and retain the old
-- object for server-side cleanup as one authenticated database operation.
-- The client never receives or deletes the previous storage path.

create table if not exists public.community_profile_media_cleanup_outbox (
  id uuid primary key default gen_random_uuid(),
  bucket_id text not null check (bucket_id in ('avatars', 'profile-media')),
  storage_path text not null check (char_length(trim(storage_path)) between 1 and 500),
  attempts integer not null default 0 check (attempts >= 0),
  available_at timestamptz not null default now(),
  processed_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  unique (bucket_id, storage_path)
);

create index if not exists community_profile_media_cleanup_pending_idx
  on public.community_profile_media_cleanup_outbox (available_at, created_at, id)
  where processed_at is null;

alter table public.community_profile_media_cleanup_outbox enable row level security;
revoke all on table public.community_profile_media_cleanup_outbox from anon, authenticated;

create or replace function public.swap_own_community_profile_media(
  media_kind text,
  new_path text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  old_path text;
  cleanup_bucket_id text;
begin
  if actor_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  if media_kind not in ('avatar', 'cover') or new_path is null then
    raise exception 'invalid profile media update' using errcode = '22023';
  end if;

  if media_kind = 'avatar' then
    cleanup_bucket_id := 'avatars';
    if new_path !~ ('^' || actor_id::text || '/avatar-[0-9a-f-]+[.]jpg$') then
      raise exception 'invalid avatar storage path' using errcode = '22023';
    end if;
  else
    cleanup_bucket_id := 'profile-media';
    if new_path !~ ('^' || actor_id::text || '/cover-[0-9a-f-]+[.]jpg$') then
      raise exception 'invalid cover storage path' using errcode = '22023';
    end if;
  end if;

  select case when media_kind = 'avatar' then profile.avatar_path else profile.cover_path end
    into old_path
  from public.community_profiles as profile
  where profile.user_id = actor_id
  for update;

  if not found then
    raise exception 'community profile not found' using errcode = 'P0002';
  end if;

  if media_kind = 'avatar' then
    update public.community_profiles
    set avatar_path = new_path
    where user_id = actor_id;
  else
    update public.community_profiles
    set cover_path = new_path
    where user_id = actor_id;
  end if;

  if old_path is not null and old_path <> new_path then
    insert into public.community_profile_media_cleanup_outbox (bucket_id, storage_path)
    values (cleanup_bucket_id, old_path)
    on conflict (bucket_id, storage_path) do nothing;
  end if;
end;
$$;

revoke all on function public.swap_own_community_profile_media(text, text) from public;
revoke all on function public.swap_own_community_profile_media(text, text) from anon;
grant execute on function public.swap_own_community_profile_media(text, text) to authenticated;
