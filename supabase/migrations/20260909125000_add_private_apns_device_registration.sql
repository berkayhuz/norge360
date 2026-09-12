-- Native APNs device records are server-only. The iOS client can register or
-- deactivate only its current token through authenticated RPCs.

create table if not exists public.community_push_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  token text not null unique,
  environment text not null check (environment in ('development', 'production')),
  is_active boolean not null default true,
  last_registered_at timestamptz not null default now(),
  last_delivery_at timestamptz,
  deactivated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists community_push_devices_active_user_environment_idx
  on public.community_push_devices (user_id, environment, updated_at desc)
  where is_active;

alter table public.community_push_devices enable row level security;

create table if not exists public.community_push_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  message_push_enabled boolean not null default true,
  updated_at timestamptz not null default now()
);

alter table public.community_push_preferences enable row level security;

drop policy if exists "Members can read their own push preferences" on public.community_push_preferences;
create policy "Members can read their own push preferences"
on public.community_push_preferences for select to authenticated
using (user_id = (select auth.uid()));

create or replace function public.register_community_push_device(
  target_token text,
  target_environment text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  normalized_token text := lower(trim(coalesce(target_token, '')));
begin
  if caller_id is null
     or target_environment not in ('development', 'production')
     or normalized_token !~ '^[a-f0-9]{32,512}$' then
    raise exception 'invalid push device';
  end if;

  -- A member may keep up to ten active app-device records. Existing tokens do
  -- not count, so repeat APNs registration is idempotent.
  if not exists (
    select 1 from public.community_push_devices where token = normalized_token
  ) and (
    select count(*) from public.community_push_devices
    where user_id = caller_id and is_active
  ) >= 10 then
    raise exception 'push device limit reached';
  end if;

  insert into public.community_push_devices (
    user_id, token, environment, is_active, last_registered_at, deactivated_at, updated_at
  ) values (
    caller_id, normalized_token, target_environment, true, now(), null, now()
  ) on conflict (token) do update
  set user_id = excluded.user_id,
      environment = excluded.environment,
      is_active = true,
      last_registered_at = now(),
      deactivated_at = null,
      updated_at = now();
end;
$$;

create or replace function public.deactivate_community_push_device(
  target_token text
)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.community_push_devices
  set is_active = false,
      deactivated_at = now(),
      updated_at = now()
  where user_id = (select auth.uid())
    and token = lower(trim(coalesce(target_token, '')))
    and is_active;
$$;

create or replace function public.update_community_message_push_enabled(
  enabled boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'authentication required';
  end if;

  insert into public.community_push_preferences (user_id, message_push_enabled, updated_at)
  values ((select auth.uid()), coalesce(enabled, false), now())
  on conflict (user_id) do update
  set message_push_enabled = excluded.message_push_enabled,
      updated_at = excluded.updated_at;
end;
$$;

revoke all on public.community_push_devices from anon, authenticated;
revoke all on public.community_push_preferences from anon, authenticated;
grant select on public.community_push_preferences to authenticated;
revoke all on function public.register_community_push_device(text, text) from public;
revoke all on function public.deactivate_community_push_device(text) from public;
revoke all on function public.update_community_message_push_enabled(boolean) from public;
grant execute on function public.register_community_push_device(text, text) to authenticated;
grant execute on function public.deactivate_community_push_device(text) to authenticated;
grant execute on function public.update_community_message_push_enabled(boolean) to authenticated;
