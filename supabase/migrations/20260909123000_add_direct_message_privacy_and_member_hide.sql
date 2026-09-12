-- Phase 2 direct messages: privacy-preserving read receipts and reversible
-- per-member hiding. This does not hard-delete content used by moderation.

create table if not exists public.community_message_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  read_receipts_enabled boolean not null default false,
  updated_at timestamptz not null default now()
);

create table if not exists public.community_message_member_hides (
  message_id uuid not null references public.community_messages(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  hidden_at timestamptz not null default now(),
  primary key (message_id, user_id)
);

create index if not exists community_message_member_hides_user_message_idx
  on public.community_message_member_hides (user_id, message_id);

alter table public.community_message_preferences enable row level security;
alter table public.community_message_member_hides enable row level security;

drop policy if exists "Members can read their own message preferences" on public.community_message_preferences;
create policy "Members can read their own message preferences"
on public.community_message_preferences for select to authenticated
using (user_id = (select auth.uid()));

drop policy if exists "Members can read their own message hides" on public.community_message_member_hides;
create policy "Members can read their own message hides"
on public.community_message_member_hides for select to authenticated
using (user_id = (select auth.uid()));

-- Messages hidden by the current member are omitted at the database boundary.
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
  and not exists (
    select 1 from public.community_message_member_hides as hidden
    where hidden.message_id = community_messages.id
      and hidden.user_id = (select auth.uid())
  )
);

create or replace function public.update_community_message_read_receipts(
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

  insert into public.community_message_preferences (user_id, read_receipts_enabled, updated_at)
  values ((select auth.uid()), coalesce(enabled, false), now())
  on conflict (user_id) do update
  set read_receipts_enabled = excluded.read_receipts_enabled,
      updated_at = excluded.updated_at;
end;
$$;

create or replace function public.get_community_message_read_receipt(
  target_conversation_id uuid
)
returns table (
  other_last_read_at timestamptz,
  are_read_receipts_enabled boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  with context as (
    select
      conversation.participant_one_id,
      conversation.participant_two_id,
      (select auth.uid()) as caller_id
    from public.community_conversations as conversation
    where conversation.id = target_conversation_id
      and conversation.status = 'active'
      and public.can_access_community_conversation(conversation.id)
  ), participants as (
    select
      case
        when context.participant_one_id = context.caller_id then context.participant_two_id
        else context.participant_one_id
      end as other_user_id,
      context.caller_id
    from context
  )
  select
    case
      when coalesce(caller_preference.read_receipts_enabled, false)
       and coalesce(other_preference.read_receipts_enabled, false)
      then other_member.last_read_at
      else null
    end as other_last_read_at,
    coalesce(caller_preference.read_receipts_enabled, false)
      and coalesce(other_preference.read_receipts_enabled, false) as are_read_receipts_enabled
  from participants
  join public.community_conversation_members as other_member
    on other_member.conversation_id = target_conversation_id
   and other_member.user_id = participants.other_user_id
   and other_member.status = 'active'
  left join public.community_message_preferences as caller_preference
    on caller_preference.user_id = participants.caller_id
  left join public.community_message_preferences as other_preference
    on other_preference.user_id = participants.other_user_id;
$$;

create or replace function public.hide_community_message_for_member(
  target_message_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  message_row public.community_messages;
begin
  if (select auth.uid()) is null then
    raise exception 'authentication required';
  end if;

  select * into message_row
  from public.community_messages
  where id = target_message_id;

  if message_row.id is null
     or not public.can_access_community_conversation(message_row.conversation_id)
     or not exists (
       select 1
       from public.community_conversation_members as member
       where member.conversation_id = message_row.conversation_id
         and member.user_id = (select auth.uid())
         and member.status = 'active'
     ) then
    raise exception 'message unavailable';
  end if;

  insert into public.community_message_member_hides (message_id, user_id)
  values (target_message_id, (select auth.uid()))
  on conflict (message_id, user_id) do nothing;
end;
$$;

create or replace function public.restore_community_message_for_member(
  target_message_id uuid
)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.community_message_member_hides
  where message_id = target_message_id
    and user_id = (select auth.uid());
$$;

revoke all on public.community_message_preferences from anon, authenticated;
revoke all on public.community_message_member_hides from anon, authenticated;
grant select on public.community_message_preferences to authenticated;
grant select on public.community_message_member_hides to authenticated;
revoke all on function public.update_community_message_read_receipts(boolean) from public;
revoke all on function public.get_community_message_read_receipt(uuid) from public;
revoke all on function public.hide_community_message_for_member(uuid) from public;
revoke all on function public.restore_community_message_for_member(uuid) from public;
grant execute on function public.update_community_message_read_receipts(boolean) to authenticated;
grant execute on function public.get_community_message_read_receipt(uuid) to authenticated;
grant execute on function public.hide_community_message_for_member(uuid) to authenticated;
grant execute on function public.restore_community_message_for_member(uuid) to authenticated;
