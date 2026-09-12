-- Conversation controls belong to the authenticated member, not the iOS client.
-- Deploy the compatible Worker before applying this migration; see rollout notes.
create table public.community_conversation_preferences (
  conversation_id uuid not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  is_muted boolean not null default false,
  is_restricted boolean not null default false,
  background_style text not null default 'plain' check (background_style in ('plain', 'dots', 'grid')),
  bubble_color text not null default 'teal' check (bubble_color in ('teal', 'blue', 'purple', 'neutral')),
  updated_at timestamptz not null default now(),
  primary key (conversation_id, user_id),
  foreign key (conversation_id, user_id) references public.community_conversation_members(conversation_id, user_id) on delete cascade
);
alter table public.community_conversation_preferences enable row level security;
create policy "Members read their own conversation preferences"
on public.community_conversation_preferences for select to authenticated
using (user_id = (select auth.uid()) and public.can_access_community_conversation(conversation_id));
revoke all on public.community_conversation_preferences from anon, authenticated;
grant select on public.community_conversation_preferences to authenticated;

create or replace function public.update_community_conversation_preferences(
  target_conversation_id uuid, muted boolean, restricted boolean, background text, bubble text
) returns void language plpgsql security definer set search_path = '' as $$
begin
  if (select auth.uid()) is null or not public.can_access_community_conversation(target_conversation_id) then
    raise exception 'conversation unavailable';
  end if;
  if muted is null or restricted is null or background is null or bubble is null
     or background not in ('plain', 'dots', 'grid') or bubble not in ('teal', 'blue', 'purple', 'neutral') then
    raise exception 'invalid conversation preference';
  end if;
  insert into public.community_conversation_preferences (conversation_id, user_id, is_muted, is_restricted, background_style, bubble_color)
  values (target_conversation_id, (select auth.uid()), muted, restricted, background, bubble)
  on conflict (conversation_id, user_id) do update set
    is_muted = excluded.is_muted, is_restricted = excluded.is_restricted,
    background_style = excluded.background_style, bubble_color = excluded.bubble_color, updated_at = now();
end;
$$;
revoke all on function public.update_community_conversation_preferences(uuid, boolean, boolean, text, text) from public;
grant execute on function public.update_community_conversation_preferences(uuid, boolean, boolean, text, text) to authenticated;

-- Transport signals are separate from the permanent community activity inbox.
-- No message body, avatar, contact field or attachment is copied into them.
create table public.community_message_signals (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references auth.users(id) on delete cascade,
  conversation_id uuid not null references public.community_conversations(id) on delete cascade,
  type text not null check (type in ('message_request', 'direct_message')),
  event_key text not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '24 hours'),
  unique (recipient_id, event_key)
);
create index community_message_signals_expiry_idx on public.community_message_signals(expires_at);
alter table public.community_message_signals enable row level security;
create policy "Recipients read unexpired message signals"
on public.community_message_signals for select to authenticated
using (recipient_id = (select auth.uid()) and expires_at > now() and public.can_access_community_conversation(conversation_id));
revoke all on public.community_message_signals from anon, authenticated;
grant select on public.community_message_signals to authenticated;
grant select, delete on public.community_message_signals to service_role;
grant select on public.community_conversation_preferences to service_role;

create or replace function public.prune_community_message_signals()
returns bigint language plpgsql security definer set search_path = '' as $$
declare removed bigint;
begin
  delete from public.community_message_signals where expires_at <= now();
  get diagnostics removed = row_count;
  return removed;
end;
$$;
revoke all on function public.prune_community_message_signals() from public;
grant execute on function public.prune_community_message_signals() to service_role;

create or replace function public.create_community_message_request_notification()
returns trigger language plpgsql security definer set search_path = '' as $$
declare recipient uuid;
begin
  if new.status <> 'pending' then return new; end if;
  perform public.prune_community_message_signals();
  recipient := case when new.participant_one_id = new.requested_by_id then new.participant_two_id else new.participant_one_id end;
  insert into public.community_message_signals (recipient_id, conversation_id, type, event_key)
  values (recipient, new.id, 'message_request', 'message-request:' || new.id::text)
  on conflict (recipient_id, event_key) do nothing;
  return new;
end;
$$;

create or replace function public.create_community_direct_message_notification()
returns trigger language plpgsql security definer set search_path = '' as $$
declare conversation public.community_conversations; recipient uuid;
begin
  select * into conversation from public.community_conversations where id = new.conversation_id;
  if conversation.id is null or conversation.status <> 'active' then return new; end if;
  perform public.prune_community_message_signals();
  recipient := case when conversation.participant_one_id = new.sender_id then conversation.participant_two_id else conversation.participant_one_id end;
  -- Emit a signal for each new message so the inbox can reorder immediately.
  -- The Worker controls device delivery independently of activity storage.
  insert into public.community_message_signals (recipient_id, conversation_id, type, event_key)
  values (recipient, new.conversation_id, 'direct_message', 'direct-message:' || new.id::text)
  on conflict (recipient_id, event_key) do nothing;
  return new;
end;
$$;
revoke all on function public.create_community_message_request_notification() from public;
revoke all on function public.create_community_direct_message_notification() from public;

-- Stop archived message previews from accumulating in the activity inbox.
delete from public.community_notifications where type in ('message_request', 'direct_message');
alter table public.community_notifications add constraint community_notifications_no_message_activity
  check (type not in ('message_request', 'direct_message'));

-- The service-role Worker rechecks current membership, blocks and preferences
-- immediately before delivery. The client cannot invoke this capability.
create or replace function public.can_deliver_community_message_signal(target_signal_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.community_message_signals as signal
    join public.community_conversations as conversation on conversation.id = signal.conversation_id
    join public.community_conversation_members as member on member.conversation_id = conversation.id and member.user_id = signal.recipient_id
    left join public.community_conversation_preferences as preference on preference.conversation_id = conversation.id and preference.user_id = signal.recipient_id
    where signal.id = target_signal_id and signal.expires_at > now()
      and member.status in ('pending', 'active')
      and ((signal.type = 'message_request' and conversation.status = 'pending') or (signal.type = 'direct_message' and conversation.status = 'active'))
      and not coalesce(preference.is_muted, false) and not coalesce(preference.is_restricted, false)
      and not exists (
        select 1 from public.user_blocks as blocked
        where (blocked.blocker_id = conversation.participant_one_id and blocked.blocked_user_id = conversation.participant_two_id)
           or (blocked.blocker_id = conversation.participant_two_id and blocked.blocked_user_id = conversation.participant_one_id)
      )
  );
$$;
revoke all on function public.can_deliver_community_message_signal(uuid) from public;
grant execute on function public.can_deliver_community_message_signal(uuid) to service_role;

-- Restriction is a per-member inbox control: incoming messages remain available,
-- replies require removing the restriction, and receipts are suppressed for both.
create or replace function public.mark_community_conversation_read(target_conversation_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if (select auth.uid()) is null or not public.can_access_community_conversation(target_conversation_id) then
    raise exception 'conversation unavailable';
  end if;
  if exists (select 1 from public.community_conversation_preferences where conversation_id = target_conversation_id and user_id = (select auth.uid()) and is_restricted) then return; end if;
  update public.community_conversation_members set last_read_at = now(), updated_at = now()
  where conversation_id = target_conversation_id and user_id = (select auth.uid()) and status = 'active';
end;
$$;

create or replace function public.get_community_message_read_receipt(target_conversation_id uuid)
returns table (other_last_read_at timestamptz, are_read_receipts_enabled boolean)
language sql stable security definer set search_path = '' as $$
  with context as (
    select case when conversation.participant_one_id = (select auth.uid()) then conversation.participant_two_id else conversation.participant_one_id end as other_user_id
    from public.community_conversations as conversation
    where conversation.id = target_conversation_id and conversation.status = 'active' and public.can_access_community_conversation(conversation.id)
  ), consent as (
    select context.other_user_id,
      coalesce(caller_pref.read_receipts_enabled, false) and coalesce(other_pref.read_receipts_enabled, false)
      and not exists (select 1 from public.community_conversation_preferences where conversation_id = target_conversation_id and is_restricted) as enabled
    from context
    left join public.community_message_preferences as caller_pref on caller_pref.user_id = (select auth.uid())
    left join public.community_message_preferences as other_pref on other_pref.user_id = context.other_user_id
  )
  select case when consent.enabled then member.last_read_at else null end, consent.enabled
  from consent join public.community_conversation_members as member
    on member.conversation_id = target_conversation_id and member.user_id = consent.other_user_id and member.status = 'active';
$$;

-- Normalize all whitespace at the authoritative boundary and serialize sends
-- per sender so concurrent requests cannot bypass the existing rate limit.
create or replace function public.send_community_message(target_conversation_id uuid, message_body text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  caller_id uuid := (select auth.uid());
  normalized_body text := btrim(regexp_replace(coalesce(message_body, ''), '[[:space:]]+', ' ', 'g'));
  conversation public.community_conversations;
  new_message_id uuid;
begin
  if caller_id is null or char_length(normalized_body) not between 1 and 2000 then raise exception 'invalid message'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(caller_id::text, 0));
  select * into conversation from public.community_conversations where id = target_conversation_id;
  if conversation.id is null or conversation.status <> 'active' or not public.can_access_community_conversation(target_conversation_id)
     or not exists (select 1 from public.community_conversation_members where conversation_id = target_conversation_id and user_id = caller_id and status = 'active') then
    raise exception 'conversation unavailable';
  end if;
  if exists (select 1 from public.community_conversation_preferences where conversation_id = target_conversation_id and user_id = caller_id and is_restricted) then
    raise exception 'remove conversation restriction before replying';
  end if;
  if (select count(*) from public.community_messages where sender_id = caller_id and created_at > now() - interval '1 minute') >= 20 then raise exception 'message rate limit reached'; end if;
  insert into public.community_messages (conversation_id, sender_id, body) values (target_conversation_id, caller_id, normalized_body) returning id into new_message_id;
  update public.community_conversation_members set last_read_at = now(), updated_at = now() where conversation_id = target_conversation_id and user_id = caller_id;
  update public.community_conversations set updated_at = now() where id = target_conversation_id;
  return new_message_id;
end;
$$;
revoke all on function public.mark_community_conversation_read(uuid) from public;
revoke all on function public.get_community_message_read_receipt(uuid) from public;
revoke all on function public.send_community_message(uuid, text) from public;
grant execute on function public.mark_community_conversation_read(uuid) to authenticated;
grant execute on function public.get_community_message_read_receipt(uuid) to authenticated;
grant execute on function public.send_community_message(uuid, text) to authenticated;

-- Preserve the configured push endpoint and secret without embedding either in
-- source control. Only an existing INSERT webhook for our push route is copied.
-- Environments without that webhook must configure it explicitly before release.
do $$
declare webhook record; definition text;
begin
  for webhook in
    select trigger.oid, trigger.tgname
    from pg_catalog.pg_trigger as trigger
    join pg_catalog.pg_proc as procedure on procedure.oid = trigger.tgfoid
    join pg_catalog.pg_namespace as namespace on namespace.oid = procedure.pronamespace
    where trigger.tgrelid = 'public.community_notifications'::regclass and not trigger.tgisinternal
      and namespace.nspname = 'supabase_functions' and procedure.proname = 'http_request'
      and (trigger.tgtype & 4) = 4
      and pg_catalog.encode(trigger.tgargs, 'escape') like '%/internal/push/community-notification%'
  loop
    definition := pg_catalog.pg_get_triggerdef(webhook.oid);
    definition := replace(definition, 'CREATE TRIGGER ' || quote_ident(webhook.tgname), 'CREATE TRIGGER ' || quote_ident('message_signal_' || substr(md5(webhook.tgname), 1, 12)));
    definition := replace(definition, ' ON public.community_notifications ', ' ON public.community_message_signals ');
    execute definition;
  end loop;
end $$;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.community_message_signals;
  end if;
exception when duplicate_object then null;
end $$;

-- Hourly deletion provides a maximum 25-hour physical retention window when
-- pg_cron is enabled. Enqueue also prunes expired signals as a fallback.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('norge360-prune-message-signals', '17 * * * *', 'select public.prune_community_message_signals()');
  end if;
end $$;
