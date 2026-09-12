-- Store only normalized moderation outcomes, never the image bytes or a
-- provider response. A clean automated result still remains pending_review
-- until the media-delivery/reviewer policy is explicitly enabled.

alter table public.community_group_chat_attachments
  add column if not exists scan_provider text,
  add column if not exists scan_status text not null default 'not_started'
    check (scan_status in ('not_started', 'passed', 'needs_review', 'rejected', 'unavailable')),
  add column if not exists scan_summary text,
  add column if not exists scanned_at timestamptz;

comment on column public.community_group_chat_attachments.scan_summary is
  'Normalized Google Vision safety outcome only; never store provider payloads or image content.';
