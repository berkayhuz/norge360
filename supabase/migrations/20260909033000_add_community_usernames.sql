-- Public community identities use a durable, URL-safe username. The unique
-- index is the source of truth; the availability RPC is only a UX convenience.
alter table public.community_profiles
  add column if not exists username text;

update public.community_profiles
set username = 'member_' || left(replace(user_id::text, '-', ''), 12)
where username is null;

alter table public.community_profiles
  alter column username set not null;

alter table public.community_profiles
  drop constraint if exists community_profiles_username_format;
alter table public.community_profiles
  add constraint community_profiles_username_format
  check (username ~ '^[a-z0-9](?:[a-z0-9_]{1,28}[a-z0-9])?$');

create unique index if not exists community_profiles_username_lower_unique
  on public.community_profiles (lower(username));

create or replace function public.is_community_username_available(candidate text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  normalized text := lower(trim(candidate));
  reserved text[] := array[
    'about', 'admin', 'api', 'app', 'auth', 'community', 'discover',
    'explore', 'feed', 'groups', 'help', 'home', 'login', 'messages',
    'norge360', 'notifications', 'plan', 'privacy', 'profile', 'search',
    'settings', 'signup', 'support', 'terms', 'user', 'users', 'www'
  ];
begin
  if normalized !~ '^[a-z0-9](?:[a-z0-9_]{1,28}[a-z0-9])?$'
    or normalized = any (reserved) then
    return false;
  end if;

  return not exists (
    select 1
    from public.community_profiles
    where lower(username) = normalized
      and user_id <> (select auth.uid())
  );
end;
$$;

revoke all on function public.is_community_username_available(text) from public;
grant execute on function public.is_community_username_available(text) to authenticated;
