-- PostgreSQL's regex engine rejects the previous {32,512} repetition bound.
-- Validate the length separately and keep the regular expression unbounded.

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
     or char_length(normalized_token) not between 32 and 512
     or normalized_token !~ '^[a-f0-9]+$' then
    raise exception 'invalid push device';
  end if;

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

revoke all on function public.register_community_push_device(text, text) from public;
grant execute on function public.register_community_push_device(text, text) to authenticated;
