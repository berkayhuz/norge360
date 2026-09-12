-- Migration version 20260910111000. Group-chat push is a short-lived transport signal, not an activity-inbox
-- item. It intentionally contains no sender name, message text, attachment
-- reference, or group metadata that could reach APNs.

create table if not exists public.community_group_chat_signals (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references auth.users(id) on delete cascade,
  group_id uuid not null references public.community_groups(id) on delete cascade,
  message_id uuid not null references public.community_group_chat_messages(id) on delete cascade,
  type text not null check (type = 'group_chat_message'),
  event_key text not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '24 hours'),
  unique (recipient_id, event_key)
);

create index community_group_chat_signals_expiry_idx
  on public.community_group_chat_signals (expires_at);
create index community_group_chat_signals_recipient_idx
  on public.community_group_chat_signals (recipient_id, created_at desc);

alter table public.community_group_chat_signals enable row level security;
revoke all on public.community_group_chat_signals from anon, authenticated;
grant select, delete on public.community_group_chat_signals to service_role;

-- Fan-out is capped deliberately: a large group must not turn one chat send
-- into an unbounded notification burst. The message itself remains available
-- to every authorized member through the normal group-chat path.
create or replace function public.create_community_group_chat_push_signals()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.deleted_at is not null or new.moderation_state <> 'active' then
    return new;
  end if;

  insert into public.community_group_chat_signals (
    recipient_id, group_id, message_id, type, event_key
  )
  select membership.user_id, new.group_id, new.id, 'group_chat_message',
    'group-chat-message:' || new.id::text || ':' || membership.user_id::text
  from public.community_group_memberships as membership
  where membership.group_id = new.group_id
    and membership.user_id <> new.sender_id
    and not exists (
      select 1
      from public.community_group_bans as ban
      where ban.group_id = new.group_id and ban.user_id = membership.user_id
    )
    and not exists (
      select 1
      from public.user_blocks as block
      where (block.blocker_id = new.sender_id and block.blocked_user_id = membership.user_id)
         or (block.blocker_id = membership.user_id and block.blocked_user_id = new.sender_id)
    )
  order by membership.user_id
  limit 100
  on conflict (recipient_id, event_key) do nothing;

  return new;
end;
$$;

drop trigger if exists community_group_chat_push_signal_after_insert
  on public.community_group_chat_messages;
create trigger community_group_chat_push_signal_after_insert
after insert on public.community_group_chat_messages
for each row execute function public.create_community_group_chat_push_signals();

-- Recheck all mutable safety state immediately before delivery. Only the
-- secret-bearing Worker has this capability; iOS cannot call it.
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
    where signal.id = target_signal_id
      and signal.expires_at > now()
      and signal.type = 'group_chat_message'
      and message.group_id = signal.group_id
      and message.deleted_at is null
      and message.moderation_state = 'active'
      and message.sender_id <> signal.recipient_id
      and recipient_profile.moderation_state = 'active'
      and sender_profile.moderation_state = 'active'
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
revoke all on function public.create_community_group_chat_push_signals() from public;
revoke all on function public.can_deliver_community_group_chat_signal(uuid) from public;
grant execute on function public.can_deliver_community_group_chat_signal(uuid) to service_role;

-- Reuse the already-configured authenticated database webhook. Its payload is
-- only the new signal ID; the Worker reloads and authorizes every delivery.
do $$
declare webhook record; definition text; source_table text;
begin
  source_table := case
    when to_regclass('public.community_message_signals') is not null then 'community_message_signals'
    when to_regclass('public.community_notifications') is not null then 'community_notifications'
    else null
  end;
  if source_table is null then
    raise notice 'No existing push webhook table was found; configure a group-chat push webhook before release.';
    return;
  end if;

  for webhook in
    select trigger.oid, trigger.tgname
    from pg_catalog.pg_trigger as trigger
    join pg_catalog.pg_proc as procedure on procedure.oid = trigger.tgfoid
    join pg_catalog.pg_namespace as namespace on namespace.oid = procedure.pronamespace
    where trigger.tgrelid = ('public.' || source_table)::regclass and not trigger.tgisinternal
      and namespace.nspname = 'supabase_functions' and procedure.proname = 'http_request'
      and (trigger.tgtype & 4) = 4
      and pg_catalog.encode(trigger.tgargs, 'escape') like '%/internal/push/community-notification%'
  loop
    definition := pg_catalog.pg_get_triggerdef(webhook.oid);
    definition := replace(definition, 'CREATE TRIGGER ' || quote_ident(webhook.tgname), 'CREATE TRIGGER ' || quote_ident('group_chat_signal_' || substr(md5(webhook.tgname), 1, 12)));
    definition := replace(definition, ' ON public.' || source_table || ' ', ' ON public.community_group_chat_signals ');
    execute definition;
  end loop;
end $$;

-- Expired signals are not application data. The enqueue path below makes this
-- work even without pg_cron; pg_cron bounds physical retention when available.
create or replace function public.prune_community_group_chat_signals()
returns bigint language plpgsql security definer set search_path = '' as $$
declare removed bigint;
begin
  delete from public.community_group_chat_signals where expires_at <= now();
  get diagnostics removed = row_count;
  return removed;
end;
$$;
revoke all on function public.prune_community_group_chat_signals() from public;
grant execute on function public.prune_community_group_chat_signals() to service_role;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule(
      'prune-community-group-chat-signals-hourly',
      '15 * * * *',
      'select public.prune_community_group_chat_signals()'
    );
  end if;
exception when unique_violation then null;
end $$;
