-- Private group-chat media is staged in quarantine. No client receives a
-- permanent object URL and pending files are never returned to chat readers.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'group-chat-media', 'group-chat-media', false, 10485760,
  array['image/jpeg', 'image/png', 'image/heic', 'image/webp']
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create table if not exists public.community_group_chat_attachments (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.community_groups(id) on delete cascade,
  message_id uuid references public.community_group_chat_messages(id) on delete cascade,
  uploader_id uuid not null references auth.users(id) on delete cascade,
  storage_path text not null unique check (char_length(btrim(storage_path)) between 1 and 500),
  mime_type text not null check (mime_type in ('image/jpeg', 'image/png', 'image/heic', 'image/webp')),
  byte_size integer not null check (byte_size between 1 and 10485760),
  status text not null default 'pending_upload'
    check (status in ('pending_upload', 'pending_review', 'ready', 'rejected', 'deleted')),
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  deleted_at timestamptz,
  check (storage_path like group_id::text || '/%'),
  check ((status = 'ready') = (reviewed_at is not null))
);

create index if not exists community_group_chat_attachments_message_idx
  on public.community_group_chat_attachments (message_id, created_at)
  where status = 'ready';
create index if not exists community_group_chat_attachments_cleanup_idx
  on public.community_group_chat_attachments (status, created_at)
  where status in ('pending_upload', 'pending_review', 'rejected', 'deleted');

alter table public.community_group_chat_attachments enable row level security;
-- Worker service-role endpoints are the only attachment mutation/read path.
revoke all on public.community_group_chat_attachments from anon, authenticated;
