-- Account deletion crosses PostgreSQL, Supabase Storage, Cloudflare Images
-- and Auth. Keep the workflow durable and retryable instead of mutating
-- moderation records before an external provider operation has succeeded.

create table if not exists public.community_account_deletion_jobs (
  user_id uuid primary key,
  status text not null default 'pending'
    check (status in ('pending', 'cleanup_pending', 'finalizing', 'completed')),
  inventory_ready boolean not null default false,
  attempt_count integer not null default 0 check (attempt_count >= 0),
  requested_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  next_attempt_at timestamptz not null default now(),
  locked_until timestamptz,
  last_error text,
  completed_at timestamptz
);

create index if not exists community_account_deletion_jobs_due_idx
  on public.community_account_deletion_jobs (next_attempt_at, updated_at)
  where status <> 'completed';

create table if not exists public.community_account_deletion_media (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  media_kind text not null check (media_kind in ('storage', 'provider')),
  bucket text not null default '',
  object_key text not null check (char_length(btrim(object_key)) between 1 and 1_000),
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'deleted', 'failed')),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  locked_until timestamptz,
  next_attempt_at timestamptz not null default now(),
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists community_account_deletion_media_identity_idx
  on public.community_account_deletion_media(user_id, media_kind, bucket, object_key);
create index if not exists community_account_deletion_media_due_idx
  on public.community_account_deletion_media(user_id, next_attempt_at, updated_at)
  where status in ('pending', 'failed', 'processing');

alter table public.community_account_deletion_jobs enable row level security;
alter table public.community_account_deletion_media enable row level security;
revoke all on public.community_account_deletion_jobs from public, anon, authenticated;
revoke all on public.community_account_deletion_media from public, anon, authenticated;
grant select, insert, update, delete on public.community_account_deletion_jobs to service_role;
grant select, insert, update, delete on public.community_account_deletion_media to service_role;

create or replace function public.is_community_account_deletion_pending(account_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.community_account_deletion_jobs as job
    where job.user_id = account_user_id
      and job.status <> 'completed'
  );
$$;

revoke all on function public.is_community_account_deletion_pending(uuid) from public, anon, authenticated;
grant execute on function public.is_community_account_deletion_pending(uuid) to service_role;

create or replace function public.reject_community_account_deletion_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(current_setting('request.jwt.claim.role', true), '') = 'authenticated'
     and (select auth.uid()) is not null
     and public.is_community_account_deletion_pending((select auth.uid())) then
    raise exception 'account deletion pending' using errcode = '55000';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function public.reject_community_account_deletion_write() from public, anon, authenticated;
grant execute on function public.reject_community_account_deletion_write() to service_role;

-- A single database boundary blocks new client writes while the account is in
-- the deletion workflow. Security-definer RPCs retain their existing checks;
-- the request JWT role remains authenticated inside those RPCs, so this guard
-- also covers writes performed through them.
do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'user_relocation_plans',
    'user_account_profiles',
    'community_comment_hashtags',
    'community_profiles',
    'community_posts',
    'community_post_edit_history',
    'community_post_hashtags',
    'community_post_media',
    'community_comments',
    'community_events',
    'community_event_rsvps',
    'community_event_likes',
    'community_reports',
    'community_post_likes',
    'community_follows',
    'community_follow_visibility',
    'user_blocks',
    'community_groups',
    'community_group_memberships',
    'community_group_join_requests',
    'community_group_invitations',
    'community_event_invitations',
    'community_group_bans',
    'community_group_moderation_audit',
    'community_group_removed_post_media',
    'community_member_restrictions',
    'community_conversations',
    'community_conversation_members',
    'community_messages',
    'community_message_preferences',
    'community_message_member_hides',
    'community_push_devices',
    'community_push_preferences',
    'community_conversation_preferences',
    'community_group_chat_messages',
    'community_group_chat_message_member_hides',
    'community_group_chat_preferences',
    'community_group_chat_member_reads',
    'community_group_chat_push_fanout_jobs',
    'community_direct_message_attachments',
    'community_group_chat_attachments',
    'community_liked_posts_visibility',
    'community_message_signals',
    'community_notifications',
    'community_moderation_action_audit',
    'community_moderation_review_audit',
    'community_moderator_roles',
    'community_media_view_rate_limits',
    'community_profile_media_cleanup_outbox',
    'community_push_delivery_ledger'
  ] loop
    if to_regclass(format('public.%I', table_name)) is not null then
      execute format(
        'drop trigger if exists community_account_deletion_guard on public.%I',
        table_name
      );
      execute format(
        'create trigger community_account_deletion_guard before insert or update or delete on public.%I for each row execute function public.reject_community_account_deletion_write()',
        table_name
      );
    end if;
  end loop;
end;
$$;

create or replace function public.begin_community_account_deletion(account_user_id uuid)
returns table (job_status text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_status text;
begin
  if coalesce(current_setting('request.jwt.claim.role', true), '') <> 'service_role' then
    raise exception 'service role required';
  end if;
  if account_user_id is null then
    raise exception 'target user required';
  end if;
  if exists (
    select 1
    from public.community_group_memberships
    where user_id = account_user_id and role = 'owner'
  ) then
    raise exception 'owned groups require ownership transfer';
  end if;

  insert into public.community_account_deletion_jobs(user_id)
  values (account_user_id)
  on conflict (user_id) do update
  set next_attempt_at = case
        when public.community_account_deletion_jobs.status = 'completed'
          then public.community_account_deletion_jobs.next_attempt_at
        else now()
      end,
      locked_until = null,
      last_error = case
        when public.community_account_deletion_jobs.status = 'completed'
          then public.community_account_deletion_jobs.last_error
        else null
      end,
      updated_at = now();

  select status into current_status
  from public.community_account_deletion_jobs
  where user_id = account_user_id;
  return query select current_status;
end;
$$;

revoke all on function public.begin_community_account_deletion(uuid) from public, anon, authenticated;
grant execute on function public.begin_community_account_deletion(uuid) to service_role;

create or replace function public.claim_community_account_deletion_jobs(
  target_batch_size integer default 5,
  target_user_id uuid default null
)
returns table (
  user_id uuid,
  status text,
  inventory_ready boolean
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(current_setting('request.jwt.claim.role', true), '') <> 'service_role' then
    raise exception 'service role required';
  end if;
  if target_batch_size is null or target_batch_size < 1 or target_batch_size > 20 then
    raise exception 'invalid deletion batch size';
  end if;

  return query
  with candidates as (
    select job.user_id
    from public.community_account_deletion_jobs as job
    where job.status <> 'completed'
      and job.next_attempt_at <= now()
      and (job.locked_until is null or job.locked_until <= now())
      and (target_user_id is null or job.user_id = target_user_id)
    order by job.updated_at asc
    limit target_batch_size
    for update skip locked
  ), claimed as (
    update public.community_account_deletion_jobs as job
    set locked_until = now() + interval '5 minutes',
        attempt_count = job.attempt_count + 1,
        updated_at = now()
    from candidates
    where job.user_id = candidates.user_id
    returning job.user_id, job.status, job.inventory_ready
  )
  select claimed.user_id, claimed.status, claimed.inventory_ready
  from claimed;
end;
$$;

revoke all on function public.claim_community_account_deletion_jobs(integer, uuid) from public, anon, authenticated;
grant execute on function public.claim_community_account_deletion_jobs(integer, uuid) to service_role;

create or replace function public.record_community_account_deletion_inventory(
  account_user_id uuid,
  storage_objects jsonb,
  provider_asset_ids text[] default '{}'
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(current_setting('request.jwt.claim.role', true), '') <> 'service_role' then
    raise exception 'service role required';
  end if;
  if account_user_id is null or storage_objects is null then
    raise exception 'deletion inventory required';
  end if;
  if not exists (
    select 1
    from public.community_account_deletion_jobs
    where user_id = account_user_id and status <> 'completed'
  ) then
    raise exception 'deletion job not found';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(storage_objects) as item
    where item->>'bucket' not in ('avatars', 'profile-media', 'post-media')
       or char_length(btrim(coalesce(item->>'path', ''))) = 0
  ) then
    raise exception 'invalid storage deletion inventory';
  end if;

  insert into public.community_account_deletion_media(user_id, media_kind, bucket, object_key)
  select account_user_id, 'storage', item->>'bucket', item->>'path'
  from jsonb_array_elements(storage_objects) as item
  on conflict (user_id, media_kind, bucket, object_key) do nothing;

  insert into public.community_account_deletion_media(user_id, media_kind, bucket, object_key)
  select account_user_id, 'provider', '', btrim(asset_id)
  from unnest(coalesce(provider_asset_ids, '{}')) as asset_id
  where char_length(btrim(asset_id)) between 1 and 500
  on conflict (user_id, media_kind, bucket, object_key) do nothing;

  update public.community_account_deletion_jobs
  set inventory_ready = true,
      status = case when status = 'finalizing' then status else 'cleanup_pending' end,
      next_attempt_at = now(),
      locked_until = null,
      last_error = null,
      updated_at = now()
  where user_id = account_user_id
    and status <> 'completed';
end;
$$;

revoke all on function public.record_community_account_deletion_inventory(uuid, jsonb, text[]) from public, anon, authenticated;
grant execute on function public.record_community_account_deletion_inventory(uuid, jsonb, text[]) to service_role;

create or replace function public.claim_community_account_deletion_media(
  account_user_id uuid,
  target_batch_size integer default 50
)
returns table (
  media_id uuid,
  media_kind text,
  bucket text,
  object_key text
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(current_setting('request.jwt.claim.role', true), '') <> 'service_role' then
    raise exception 'service role required';
  end if;
  if account_user_id is null or target_batch_size is null
     or target_batch_size < 1 or target_batch_size > 100 then
    raise exception 'invalid media deletion batch size';
  end if;

  return query
  with candidates as (
    select media.id
    from public.community_account_deletion_media as media
    where media.user_id = account_user_id
      and (
        media.status in ('pending', 'failed')
        or (media.status = 'processing' and media.locked_until <= now())
      )
      and media.next_attempt_at <= now()
      and (media.locked_until is null or media.locked_until <= now())
    order by media.updated_at asc
    limit target_batch_size
    for update skip locked
  ), claimed as (
    update public.community_account_deletion_media as media
    set status = 'processing',
        attempt_count = media.attempt_count + 1,
        locked_until = now() + interval '5 minutes',
        updated_at = now()
    from candidates
    where media.id = candidates.id
    returning media.id, media.media_kind, media.bucket, media.object_key
  )
  select claimed.id, claimed.media_kind, claimed.bucket, claimed.object_key
  from claimed;
end;
$$;

revoke all on function public.claim_community_account_deletion_media(uuid, integer) from public, anon, authenticated;
grant execute on function public.claim_community_account_deletion_media(uuid, integer) to service_role;

create or replace function public.complete_community_account_deletion_media(
  target_media_id uuid,
  succeeded boolean,
  failure_reason text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(current_setting('request.jwt.claim.role', true), '') <> 'service_role' then
    raise exception 'service role required';
  end if;
  if target_media_id is null or succeeded is null then
    raise exception 'media result required';
  end if;

  update public.community_account_deletion_media
  set status = case when succeeded then 'deleted' else 'failed' end,
      locked_until = null,
      next_attempt_at = case when succeeded then now() else now() + interval '5 minutes' end,
      last_error = case when succeeded then null else left(nullif(btrim(failure_reason), ''), 500) end,
      updated_at = now()
  where id = target_media_id;
end;
$$;

revoke all on function public.complete_community_account_deletion_media(uuid, boolean, text) from public, anon, authenticated;
grant execute on function public.complete_community_account_deletion_media(uuid, boolean, text) to service_role;

create or replace function public.update_community_account_deletion_job(
  account_user_id uuid,
  next_status text,
  failure_reason text default null,
  retry_after_seconds integer default 300
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(current_setting('request.jwt.claim.role', true), '') <> 'service_role' then
    raise exception 'service role required';
  end if;
  if account_user_id is null
     or next_status not in ('pending', 'cleanup_pending', 'finalizing', 'completed')
     or retry_after_seconds is null or retry_after_seconds < 0 or retry_after_seconds > 86400 then
    raise exception 'invalid deletion job state';
  end if;

  update public.community_account_deletion_jobs
  set status = next_status,
      locked_until = null,
      next_attempt_at = case when next_status = 'completed' then now() else now() + make_interval(secs => retry_after_seconds) end,
      last_error = case when next_status = 'completed' then null else left(nullif(btrim(failure_reason), ''), 1_000) end,
      completed_at = case when next_status = 'completed' then now() else completed_at end,
      updated_at = now()
  where user_id = account_user_id;
end;
$$;

revoke all on function public.update_community_account_deletion_job(uuid, text, text, integer) from public, anon, authenticated;
grant execute on function public.update_community_account_deletion_job(uuid, text, text, integer) to service_role;

comment on table public.community_account_deletion_jobs is
  'Durable, service-owned account deletion state. The row intentionally has no Auth foreign key so failed jobs remain retryable.';
comment on table public.community_account_deletion_media is
  'Durable account-deletion media inventory and per-object cleanup state.';
