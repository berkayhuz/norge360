-- A member may mute one group chat without disabling all message pushes.
-- The preference never changes group membership, message visibility, or the
-- realtime stream; it only prevents a device-delivery signal.

create table public.community_group_chat_preferences (
  group_id uuid not null references public.community_groups(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  is_muted boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (group_id, user_id),
  foreign key (group_id, user_id)
    references public.community_group_memberships(group_id, user_id) on delete cascade
);

alter table public.community_group_chat_preferences enable row level security;
revoke all on public.community_group_chat_preferences from anon, authenticated;
grant select on public.community_group_chat_preferences to service_role;

create or replace function public.get_community_group_chat_notification_preference(target_group_id uuid)
returns table (is_muted boolean)
language plpgsql security definer set search_path = '' as $$
begin
  if not public.can_access_community_group_chat(target_group_id) then
    raise exception 'group chat unavailable';
  end if;
  return query
  select coalesce(preference.is_muted, false)
  from (select 1) as fallback
  left join public.community_group_chat_preferences as preference
    on preference.group_id = target_group_id
    and preference.user_id = (select auth.uid());
end;
$$;

create or replace function public.update_community_group_chat_notification_preference(
  target_group_id uuid,
  muted boolean
)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if muted is null or not public.can_access_community_group_chat(target_group_id) then
    raise exception 'group chat unavailable';
  end if;
  insert into public.community_group_chat_preferences (group_id, user_id, is_muted, updated_at)
  values (target_group_id, (select auth.uid()), muted, now())
  on conflict (group_id, user_id) do update
  set is_muted = excluded.is_muted, updated_at = excluded.updated_at;
end;
$$;

revoke all on function public.get_community_group_chat_notification_preference(uuid) from public;
revoke all on function public.update_community_group_chat_notification_preference(uuid, boolean) from public;
grant execute on function public.get_community_group_chat_notification_preference(uuid) to authenticated;
grant execute on function public.update_community_group_chat_notification_preference(uuid, boolean) to authenticated;

-- Replace the previous Worker-only eligibility function so mute changes take
-- effect immediately, including for a signal already waiting in the webhook.
create or replace function public.can_deliver_community_group_chat_signal(target_signal_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.community_group_chat_signals as signal
    join public.community_group_chat_messages as message on message.id = signal.message_id
    join public.community_group_memberships as membership
      on membership.group_id = signal.group_id and membership.user_id = signal.recipient_id
    join public.community_profiles as recipient_profile on recipient_profile.user_id = signal.recipient_id
    join public.community_profiles as sender_profile on sender_profile.user_id = message.sender_id
    left join public.community_group_chat_preferences as preference
      on preference.group_id = signal.group_id and preference.user_id = signal.recipient_id
    where signal.id = target_signal_id
      and signal.expires_at > now()
      and signal.type = 'group_chat_message'
      and message.group_id = signal.group_id
      and message.deleted_at is null
      and message.moderation_state = 'active'
      and message.sender_id <> signal.recipient_id
      and recipient_profile.moderation_state = 'active'
      and sender_profile.moderation_state = 'active'
      and not coalesce(preference.is_muted, false)
      and not exists (
        select 1 from public.community_group_bans as ban
        where ban.group_id = signal.group_id and ban.user_id = signal.recipient_id
      )
      and not exists (
        select 1 from public.user_blocks as block
        where (block.blocker_id = message.sender_id and block.blocked_user_id = signal.recipient_id)
           or (block.blocker_id = signal.recipient_id and block.blocked_user_id = message.sender_id)
      )
  );
$$;
revoke all on function public.can_deliver_community_group_chat_signal(uuid) from public;
grant execute on function public.can_deliver_community_group_chat_signal(uuid) to service_role;
