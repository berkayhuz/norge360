-- Upload URL issuance is a billable capability. Keep the quota independent
-- from attachment retention so cancellation and provider failures do not
-- restore a user's upload capacity.

create table if not exists public.community_media_upload_rate_limits (
  user_id uuid primary key references auth.users(id) on delete cascade,
  window_started_at timestamptz not null,
  request_count integer not null default 0 check (request_count between 0 and 7),
  updated_at timestamptz not null default now()
);

alter table public.community_media_upload_rate_limits enable row level security;
revoke all on public.community_media_upload_rate_limits from public, anon, authenticated;

-- Account deletion is a server-owned workflow. Prevent a pending deletion from
-- creating or mutating a new quota row after its deletion boundary is set.
drop trigger if exists community_account_deletion_guard
  on public.community_media_upload_rate_limits;
create trigger community_account_deletion_guard
before insert or update or delete on public.community_media_upload_rate_limits
for each row execute function public.reject_community_account_deletion_write();

create or replace function public.stage_community_group_chat_attachment(
  target_group_id uuid,
  target_uploader_id uuid,
  target_mime_type text,
  target_byte_size integer
)
returns table (
  attachment_id uuid,
  storage_path text,
  rate_limited boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_window timestamptz := clock_timestamp();
  current_count integer;
  new_attachment_id uuid;
  new_storage_path text;
begin
  if coalesce(current_setting('request.jwt.claim.role', true), '') <> 'service_role' then
    raise exception 'service role required';
  end if;
  if target_group_id is null
     or target_uploader_id is null
     or target_mime_type not in ('image/jpeg', 'image/png', 'image/heic', 'image/webp')
     or target_byte_size is null
     or target_byte_size not between 1 and 10485760
     or not exists (select 1 from auth.users where id = target_uploader_id)
     or not exists (select 1 from public.community_groups where id = target_group_id) then
    raise exception 'invalid media staging request';
  end if;

  insert into public.community_media_upload_rate_limits(
    user_id,
    window_started_at,
    request_count
  )
  values (target_uploader_id, current_window, 1)
  on conflict (user_id) do update
  set window_started_at = case
        when public.community_media_upload_rate_limits.window_started_at < excluded.window_started_at - interval '60 seconds'
          then excluded.window_started_at
        else public.community_media_upload_rate_limits.window_started_at
      end,
      request_count = case
        when public.community_media_upload_rate_limits.window_started_at < excluded.window_started_at - interval '60 seconds'
          then 1
        else least(public.community_media_upload_rate_limits.request_count + 1, 7)
      end,
      updated_at = now()
  returning request_count into current_count;

  if current_count > 6 then
    return query select null::uuid, null::text, true;
    return;
  end if;

  new_attachment_id := gen_random_uuid();
  new_storage_path := format('%s/%s/%s', target_group_id, target_uploader_id, new_attachment_id);

  insert into public.community_group_chat_attachments(
    id,
    group_id,
    uploader_id,
    storage_path,
    mime_type,
    byte_size,
    status,
    storage_provider
  )
  values (
    new_attachment_id,
    target_group_id,
    target_uploader_id,
    new_storage_path,
    target_mime_type,
    target_byte_size,
    'pending_upload',
    'cloudflare_images'
  );

  return query select new_attachment_id, new_storage_path, false;
end;
$$;

create or replace function public.stage_community_direct_message_attachment(
  target_conversation_id uuid,
  target_uploader_id uuid,
  target_mime_type text,
  target_byte_size integer
)
returns table (
  attachment_id uuid,
  storage_path text,
  rate_limited boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_window timestamptz := clock_timestamp();
  current_count integer;
  new_attachment_id uuid;
  new_storage_path text;
begin
  if coalesce(current_setting('request.jwt.claim.role', true), '') <> 'service_role' then
    raise exception 'service role required';
  end if;
  if target_conversation_id is null
     or target_uploader_id is null
     or target_mime_type not in ('image/jpeg', 'image/png', 'image/heic', 'image/webp')
     or target_byte_size is null
     or target_byte_size not between 1 and 10485760
     or not exists (select 1 from auth.users where id = target_uploader_id)
     or not exists (
       select 1
       from public.community_conversations conversation
       join public.community_conversation_members membership
         on membership.conversation_id = conversation.id
        and membership.user_id = target_uploader_id
        and membership.status = 'active'
       where conversation.id = target_conversation_id
         and conversation.status = 'active'
     ) then
    raise exception 'invalid media staging request';
  end if;

  insert into public.community_media_upload_rate_limits(
    user_id,
    window_started_at,
    request_count
  )
  values (target_uploader_id, current_window, 1)
  on conflict (user_id) do update
  set window_started_at = case
        when public.community_media_upload_rate_limits.window_started_at < excluded.window_started_at - interval '60 seconds'
          then excluded.window_started_at
        else public.community_media_upload_rate_limits.window_started_at
      end,
      request_count = case
        when public.community_media_upload_rate_limits.window_started_at < excluded.window_started_at - interval '60 seconds'
          then 1
        else least(public.community_media_upload_rate_limits.request_count + 1, 7)
      end,
      updated_at = now()
  returning request_count into current_count;

  if current_count > 6 then
    return query select null::uuid, null::text, true;
    return;
  end if;

  new_attachment_id := gen_random_uuid();
  new_storage_path := format('%s/%s/%s', target_conversation_id, target_uploader_id, new_attachment_id);

  insert into public.community_direct_message_attachments(
    id,
    conversation_id,
    uploader_id,
    storage_reference,
    mime_type,
    byte_size,
    status
  )
  values (
    new_attachment_id,
    target_conversation_id,
    target_uploader_id,
    new_storage_path,
    target_mime_type,
    target_byte_size,
    'pending_upload'
  );

  return query select new_attachment_id, new_storage_path, false;
end;
$$;

revoke all on function public.stage_community_group_chat_attachment(uuid, uuid, text, integer) from public, anon, authenticated;
revoke all on function public.stage_community_direct_message_attachment(uuid, uuid, text, integer) from public, anon, authenticated;
grant execute on function public.stage_community_group_chat_attachment(uuid, uuid, text, integer) to service_role;
grant execute on function public.stage_community_direct_message_attachment(uuid, uuid, text, integer) to service_role;

comment on table public.community_media_upload_rate_limits is
  'Server-owned per-member upload URL quota. It intentionally outlives staged attachment rows.';
comment on function public.stage_community_group_chat_attachment(uuid, uuid, text, integer) is
  'Atomically reserves the member upload quota and stages a private group-chat attachment for the service Worker.';
comment on function public.stage_community_direct_message_attachment(uuid, uuid, text, integer) is
  'Atomically reserves the member upload quota and stages a private direct-message attachment for the service Worker.';
