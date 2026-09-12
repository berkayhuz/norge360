-- Phase 1 conversations: request-gated, plain-text direct messages only.
-- Clients receive SELECT access through RLS and use RPCs for every mutation.

create table if not exists public.community_conversations (
  id uuid primary key default gen_random_uuid(),
  kind text not null default 'direct' check (kind = 'direct'),
  participant_one_id uuid not null references auth.users(id) on delete cascade,
  participant_two_id uuid not null references auth.users(id) on delete cascade,
  requested_by_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'active', 'declined')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (participant_one_id < participant_two_id),
  check (requested_by_id = participant_one_id or requested_by_id = participant_two_id),
  unique (participant_one_id, participant_two_id)
);

create table if not exists public.community_conversation_members (
  conversation_id uuid not null references public.community_conversations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null check (status in ('pending', 'active', 'declined')),
  last_read_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);

create table if not exists public.community_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.community_conversations(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(trim(body)) between 1 and 2000),
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  updated_at timestamptz not null default now()
);

create index if not exists community_conversation_members_user_status_idx
  on public.community_conversation_members (user_id, status, updated_at desc);
create index if not exists community_messages_conversation_created_idx
  on public.community_messages (conversation_id, created_at desc);
create index if not exists community_messages_sender_created_idx
  on public.community_messages (sender_id, created_at desc);

alter table public.community_conversations enable row level security;
alter table public.community_conversation_members enable row level security;
alter table public.community_messages enable row level security;

create or replace function public.can_access_community_conversation(target_conversation_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.community_conversations as conversation
    join public.community_conversation_members as member
      on member.conversation_id = conversation.id
    where conversation.id = target_conversation_id
      and member.user_id = (select auth.uid())
      and member.status in ('pending', 'active')
      and public.can_view_community_user(
        case
          when conversation.participant_one_id = (select auth.uid()) then conversation.participant_two_id
          else conversation.participant_one_id
        end
      )
  );
$$;

revoke all on function public.can_access_community_conversation(uuid) from public;
grant execute on function public.can_access_community_conversation(uuid) to authenticated;

drop policy if exists "Members can read their conversations" on public.community_conversations;
create policy "Members can read their conversations"
on public.community_conversations for select to authenticated
using (public.can_access_community_conversation(id));

drop policy if exists "Members can read conversation membership" on public.community_conversation_members;
create policy "Members can read conversation membership"
on public.community_conversation_members for select to authenticated
using (public.can_access_community_conversation(conversation_id));

drop policy if exists "Active members can read messages" on public.community_messages;
create policy "Active members can read messages"
on public.community_messages for select to authenticated
using (
  public.can_access_community_conversation(conversation_id)
  and exists (
    select 1 from public.community_conversations as conversation
    join public.community_conversation_members as member
      on member.conversation_id = conversation.id
    where conversation.id = community_messages.conversation_id
      and conversation.status = 'active'
      and member.user_id = (select auth.uid())
      and member.status = 'active'
  )
);

create or replace function public.create_direct_conversation(target_user_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  first_participant uuid;
  second_participant uuid;
  existing_conversation public.community_conversations;
  new_conversation_id uuid;
begin
  if caller_id is null or target_user_id is null or caller_id = target_user_id then
    raise exception 'invalid conversation target';
  end if;
  if not public.can_view_community_user(target_user_id)
     or not exists (select 1 from public.community_profiles where user_id = target_user_id) then
    raise exception 'conversation unavailable';
  end if;

  first_participant := least(caller_id, target_user_id);
  second_participant := greatest(caller_id, target_user_id);
  select * into existing_conversation
  from public.community_conversations
  where participant_one_id = first_participant and participant_two_id = second_participant;

  if found then
    if existing_conversation.status = 'declined' then
      raise exception 'message request unavailable';
    end if;
    return existing_conversation.id;
  end if;

  insert into public.community_conversations (participant_one_id, participant_two_id, requested_by_id)
  values (first_participant, second_participant, caller_id)
  returning id into new_conversation_id;

  insert into public.community_conversation_members (conversation_id, user_id, status)
  values
    (new_conversation_id, caller_id, 'pending'),
    (new_conversation_id, target_user_id, 'pending');
  return new_conversation_id;
end;
$$;

create or replace function public.respond_to_direct_conversation(
  target_conversation_id uuid,
  accept_request boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  conversation public.community_conversations;
begin
  select * into conversation from public.community_conversations where id = target_conversation_id for update;
  if not found or caller_id is null or conversation.status <> 'pending' or conversation.requested_by_id = caller_id then
    raise exception 'conversation request unavailable';
  end if;
  if caller_id <> conversation.participant_one_id and caller_id <> conversation.participant_two_id then
    raise exception 'conversation request unavailable';
  end if;
  if not public.can_view_community_user(conversation.requested_by_id) then
    raise exception 'conversation request unavailable';
  end if;

  update public.community_conversations
  set status = case when accept_request then 'active' else 'declined' end, updated_at = now()
  where id = target_conversation_id;
  update public.community_conversation_members
  set status = case when accept_request then 'active' else 'declined' end, updated_at = now()
  where conversation_id = target_conversation_id;
end;
$$;

create or replace function public.send_community_message(
  target_conversation_id uuid,
  message_body text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  normalized_body text := trim(regexp_replace(coalesce(message_body, ''), '\\s+', ' ', 'g'));
  conversation public.community_conversations;
  other_participant uuid;
  new_message_id uuid;
begin
  if caller_id is null or char_length(normalized_body) not between 1 and 2000 then
    raise exception 'invalid message';
  end if;
  select * into conversation from public.community_conversations where id = target_conversation_id;
  if not found or conversation.status <> 'active' then raise exception 'conversation unavailable'; end if;
  if caller_id <> conversation.participant_one_id and caller_id <> conversation.participant_two_id then
    raise exception 'conversation unavailable';
  end if;
  if not exists (
    select 1 from public.community_conversation_members
    where conversation_id = target_conversation_id and user_id = caller_id and status = 'active'
  ) then raise exception 'conversation unavailable'; end if;

  other_participant := case when conversation.participant_one_id = caller_id then conversation.participant_two_id else conversation.participant_one_id end;
  if not public.can_view_community_user(other_participant) then raise exception 'conversation unavailable'; end if;
  if (select count(*) from public.community_messages where sender_id = caller_id and created_at > now() - interval '1 minute') >= 20 then
    raise exception 'message rate limit reached';
  end if;

  insert into public.community_messages (conversation_id, sender_id, body)
  values (target_conversation_id, caller_id, normalized_body)
  returning id into new_message_id;
  update public.community_conversation_members
  set last_read_at = now(), updated_at = now()
  where conversation_id = target_conversation_id and user_id = caller_id;
  update public.community_conversations set updated_at = now() where id = target_conversation_id;
  return new_message_id;
end;
$$;

create or replace function public.mark_community_conversation_read(target_conversation_id uuid)
returns void
language sql
security invoker
set search_path = ''
as $$
  update public.community_conversation_members
  set last_read_at = now(), updated_at = now()
  where conversation_id = target_conversation_id
    and user_id = (select auth.uid())
    and status = 'active';
$$;

revoke all on public.community_conversations from anon, authenticated;
revoke all on public.community_conversation_members from anon, authenticated;
revoke all on public.community_messages from anon, authenticated;
grant select on public.community_conversations to authenticated;
grant select on public.community_conversation_members to authenticated;
grant select on public.community_messages to authenticated;
revoke all on function public.create_direct_conversation(uuid) from public;
revoke all on function public.respond_to_direct_conversation(uuid, boolean) from public;
revoke all on function public.send_community_message(uuid, text) from public;
revoke all on function public.mark_community_conversation_read(uuid) from public;
grant execute on function public.create_direct_conversation(uuid) to authenticated;
grant execute on function public.respond_to_direct_conversation(uuid, boolean) to authenticated;
grant execute on function public.send_community_message(uuid, text) to authenticated;
grant execute on function public.mark_community_conversation_read(uuid) to authenticated;
