-- Group-chat read state is privacy data. The client never writes this table
-- directly and a sender can receive only an aggregate count, never reader IDs.

create table if not exists public.community_group_chat_member_reads (
  group_id uuid not null references public.community_groups(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  last_read_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

create index if not exists community_group_chat_member_reads_group_read_idx
  on public.community_group_chat_member_reads (group_id, last_read_at desc);

alter table public.community_group_chat_member_reads enable row level security;
revoke all on public.community_group_chat_member_reads from anon, authenticated;

create or replace function public.mark_community_group_chat_read(target_group_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare caller_id uuid := (select auth.uid());
begin
  if caller_id is null or not public.can_access_community_group_chat(target_group_id) then
    raise exception 'group chat unavailable';
  end if;

  -- Disabled means no new read state is persisted. Existing historical state
  -- is never disclosed while the preference remains disabled.
  if not coalesce((
    select read_receipts_enabled
    from public.community_message_preferences
    where user_id = caller_id
  ), false) then
    return;
  end if;

  insert into public.community_group_chat_member_reads (group_id, user_id, last_read_at, updated_at)
  values (target_group_id, caller_id, now(), now())
  on conflict (group_id, user_id) do update
  set last_read_at = greatest(community_group_chat_member_reads.last_read_at, excluded.last_read_at),
      updated_at = now();
end;
$$;

create or replace function public.get_community_group_chat_message_read_receipt(target_message_id uuid)
returns table (seen_count integer, latest_read_at timestamptz, are_read_receipts_enabled boolean)
language sql stable security definer set search_path = '' as $$
  with message_context as (
    select message.id, message.group_id, message.created_at
    from public.community_group_chat_messages message
    where message.id = target_message_id
      and message.sender_id = (select auth.uid())
      and message.deleted_at is null
      and message.moderation_state = 'active'
      and public.can_access_community_group_chat(message.group_id)
  ), caller_consent as (
    select coalesce(preference.read_receipts_enabled, false) as enabled
    from (select 1) singleton
    left join public.community_message_preferences preference
      on preference.user_id = (select auth.uid())
  ), eligible_reads as (
    select reads.last_read_at
    from message_context context
    join public.community_group_chat_member_reads reads
      on reads.group_id = context.group_id
     and reads.user_id <> (select auth.uid())
     and reads.last_read_at >= context.created_at
    join public.community_group_memberships membership
      on membership.group_id = reads.group_id and membership.user_id = reads.user_id
    left join public.community_group_bans ban
      on ban.group_id = reads.group_id and ban.user_id = reads.user_id
    join public.community_message_preferences preference
      on preference.user_id = reads.user_id and preference.read_receipts_enabled
    where ban.user_id is null
      and (select enabled from caller_consent)
  )
  select count(*)::integer, max(last_read_at), (select enabled from caller_consent)
  from eligible_reads;
$$;

revoke all on function public.mark_community_group_chat_read(uuid) from public;
revoke all on function public.get_community_group_chat_message_read_receipt(uuid) from public;
grant execute on function public.mark_community_group_chat_read(uuid) to authenticated;
grant execute on function public.get_community_group_chat_message_read_receipt(uuid) to authenticated;
