-- Group-chat push fan-out is an asynchronous transport concern. Keep one
-- durable job in the message transaction, then let the service Worker create
-- recipient signals in bounded, retryable batches.
create table if not exists public.community_group_chat_push_fanout_jobs (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.community_groups(id) on delete cascade,
  message_id uuid not null references public.community_group_chat_messages(id) on delete cascade,
  cursor_user_id uuid,
  status text not null default 'pending' check (status in ('pending', 'completed')),
  attempts integer not null default 0 check (attempts >= 0),
  available_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  unique (message_id)
);

create index if not exists community_group_chat_push_fanout_jobs_pending_idx
  on public.community_group_chat_push_fanout_jobs (status, available_at, created_at, id)
  where status = 'pending';

alter table public.community_group_chat_push_fanout_jobs enable row level security;
revoke all on public.community_group_chat_push_fanout_jobs from anon, authenticated;
grant select on public.community_group_chat_push_fanout_jobs to service_role;

create or replace function public.create_community_group_chat_push_signals()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.deleted_at is not null or new.moderation_state <> 'active' then
    return new;
  end if;

  insert into public.community_group_chat_push_fanout_jobs (group_id, message_id)
  values (new.group_id, new.id)
  on conflict (message_id) do nothing;

  return new;
end;
$$;

revoke all on function public.create_community_group_chat_push_signals() from public;

create or replace function public.process_community_group_chat_push_fanout(
  target_job_id uuid,
  batch_size integer default 100
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  fanout_job public.community_group_chat_push_fanout_jobs;
  selected_count integer;
  last_user_id uuid;
begin
  if batch_size is null or batch_size < 1 or batch_size > 500 then
    raise exception 'invalid group chat fan-out batch size';
  end if;

  select * into fanout_job
  from public.community_group_chat_push_fanout_jobs as job
  where job.id = target_job_id
    and job.status = 'pending'
    and job.available_at <= now()
  for update skip locked;

  if not found then
    return false;
  end if;

  update public.community_group_chat_push_fanout_jobs
  set attempts = attempts + 1
  where id = fanout_job.id;

  with selected as materialized (
    select membership.user_id
    from public.community_group_memberships as membership
    join public.community_group_chat_messages as message
      on message.id = fanout_job.message_id
     and message.group_id = membership.group_id
    where membership.group_id = fanout_job.group_id
      and membership.user_id <> message.sender_id
      and membership.created_at <= fanout_job.created_at
      and (
        fanout_job.cursor_user_id is null
        or membership.user_id > fanout_job.cursor_user_id
      )
      and message.deleted_at is null
      and message.moderation_state = 'active'
      and not exists (
        select 1
        from public.community_group_bans as ban
        where ban.group_id = fanout_job.group_id
          and ban.user_id = membership.user_id
      )
      and not exists (
        select 1
        from public.user_blocks as block
        where (block.blocker_id = message.sender_id and block.blocked_user_id = membership.user_id)
           or (block.blocker_id = membership.user_id and block.blocked_user_id = message.sender_id)
      )
    order by membership.user_id
    limit batch_size
  ),
  inserted as (
    insert into public.community_group_chat_signals (
      recipient_id, group_id, message_id, type, event_key
    )
    select
      selected.user_id,
      fanout_job.group_id,
      fanout_job.message_id,
      'group_chat_message',
      'group-chat-message:' || fanout_job.message_id::text || ':' || selected.user_id::text
    from selected
    on conflict (recipient_id, event_key) do nothing
    returning recipient_id
  )
  select count(*)::integer,
    (select selected_last.user_id
     from selected as selected_last
     order by selected_last.user_id desc
     limit 1)
    into selected_count, last_user_id
  from selected
  left join inserted on inserted.recipient_id = selected.user_id;

  if selected_count = 0 then
    update public.community_group_chat_push_fanout_jobs
    set status = 'completed', completed_at = now()
    where id = fanout_job.id;
    return false;
  end if;

  update public.community_group_chat_push_fanout_jobs
  set cursor_user_id = last_user_id,
      status = case when selected_count < batch_size then 'completed' else 'pending' end,
      available_at = now(),
      completed_at = case when selected_count < batch_size then now() else null end
  where id = fanout_job.id;

  return selected_count >= batch_size;
end;
$$;

revoke all on function public.process_community_group_chat_push_fanout(uuid, integer) from public;
grant execute on function public.process_community_group_chat_push_fanout(uuid, integer) to service_role;

-- Reuse an existing authenticated database webhook so the job row wakes the
-- secret-bearing Worker without adding a second public HTTP integration.
do $$
declare
  webhook record;
  definition text;
  source_table text;
begin
  source_table := case
    when to_regclass('public.community_group_chat_signals') is not null then 'community_group_chat_signals'
    when to_regclass('public.community_message_signals') is not null then 'community_message_signals'
    when to_regclass('public.community_notifications') is not null then 'community_notifications'
    else null
  end;

  if source_table is null then
    raise notice 'No existing push webhook table was found; configure group-chat fan-out delivery before release.';
    return;
  end if;

  for webhook in
    select trigger.oid, trigger.tgname
    from pg_catalog.pg_trigger as trigger
    join pg_catalog.pg_proc as procedure on procedure.oid = trigger.tgfoid
    join pg_catalog.pg_namespace as namespace on namespace.oid = procedure.pronamespace
    where trigger.tgrelid = ('public.' || source_table)::regclass
      and not trigger.tgisinternal
      and namespace.nspname = 'supabase_functions'
      and procedure.proname = 'http_request'
      and (trigger.tgtype & 4) = 4
      and pg_catalog.encode(trigger.tgargs, 'escape') like '%/internal/push/community-notification%'
  loop
    definition := pg_catalog.pg_get_triggerdef(webhook.oid);
    definition := replace(
      definition,
      'CREATE TRIGGER ' || quote_ident(webhook.tgname),
      'CREATE TRIGGER ' || quote_ident('group_chat_fanout_job_' || substr(md5(webhook.tgname), 1, 12))
    );
    definition := replace(
      definition,
      ' ON public.' || source_table || ' ',
      ' ON public.community_group_chat_push_fanout_jobs '
    );
    execute definition;
  end loop;
end $$;
