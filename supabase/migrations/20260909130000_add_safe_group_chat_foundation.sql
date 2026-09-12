-- Phase 2a group chat: private, member-only, plain text. This migration does
-- not expose a client UI yet; reporting, hide, notification and moderation
-- slices must be added before it becomes reachable in the app.

create table if not exists public.community_group_chat_messages (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.community_groups(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 2_000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists community_group_chat_messages_group_created_idx
  on public.community_group_chat_messages (group_id, created_at desc);
create index if not exists community_group_chat_messages_sender_created_idx
  on public.community_group_chat_messages (sender_id, created_at desc);

alter table public.community_group_chat_messages enable row level security;

create or replace function public.can_access_community_group_chat(target_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
    and exists (
      select 1
      from public.community_group_memberships membership
      where membership.group_id = target_group_id
        and membership.user_id = (select auth.uid())
    )
    and not exists (
      select 1
      from public.community_group_bans ban
      where ban.group_id = target_group_id
        and ban.user_id = (select auth.uid())
    );
$$;

-- No direct client table access: all reads and writes remain behind RPCs.
revoke all on function public.can_access_community_group_chat(uuid) from public;
grant execute on function public.can_access_community_group_chat(uuid) to authenticated;
revoke all on public.community_group_chat_messages from anon, authenticated;

create or replace function public.list_community_group_chat_messages(target_group_id uuid)
returns table (
  id uuid,
  sender_id uuid,
  display_name text,
  username text,
  body text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.can_access_community_group_chat(target_group_id) then
    raise exception 'group chat unavailable';
  end if;

  return query
  select message.id, message.sender_id, profile.display_name, profile.username,
    message.body, message.created_at
  from public.community_group_chat_messages message
  join public.community_profiles profile on profile.user_id = message.sender_id
  where message.group_id = target_group_id
    and message.deleted_at is null
    and public.can_view_community_user(message.sender_id)
  order by message.created_at asc
  limit 200;
end;
$$;

create or replace function public.send_community_group_chat_message(
  target_group_id uuid,
  message_body text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  normalized_body text := btrim(regexp_replace(coalesce(message_body, ''), '[[:space:]]+', ' ', 'g'));
  new_message_id uuid;
begin
  if caller_id is null
     or char_length(normalized_body) not between 1 and 2_000
     or not public.can_access_community_group_chat(target_group_id) then
    raise exception 'group chat unavailable';
  end if;

  -- One member cannot flood group chat; this is deliberately independent of
  -- direct-message limits so both surfaces remain predictable.
  if (
    select count(*)
    from public.community_group_chat_messages
    where sender_id = caller_id
      and created_at > now() - interval '1 minute'
  ) >= 20 then
    raise exception 'group chat rate limit reached';
  end if;

  insert into public.community_group_chat_messages (group_id, sender_id, body)
  values (target_group_id, caller_id, normalized_body)
  returning id into new_message_id;
  return new_message_id;
end;
$$;

revoke all on function public.list_community_group_chat_messages(uuid) from public;
revoke all on function public.send_community_group_chat_message(uuid, text) from public;
grant execute on function public.list_community_group_chat_messages(uuid) to authenticated;
grant execute on function public.send_community_group_chat_message(uuid, text) to authenticated;
