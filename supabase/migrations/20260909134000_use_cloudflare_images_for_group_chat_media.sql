-- Cloudflare Images is the private staging provider for group-chat images.
-- The legacy storage_path remains an opaque group-scoped reference so older
-- quarantine rows remain valid; it is never delivered to clients.

alter table public.community_group_chat_attachments
  add column if not exists storage_provider text not null default 'supabase_storage'
    check (storage_provider in ('supabase_storage', 'cloudflare_images')),
  add column if not exists provider_asset_id text;

create unique index if not exists community_group_chat_attachments_provider_asset_id_key
  on public.community_group_chat_attachments (provider_asset_id)
  where provider_asset_id is not null;

comment on column public.community_group_chat_attachments.provider_asset_id is
  'Private Cloudflare Images asset ID. Never expose this directly; signed delivery is server-authorized after review.';
