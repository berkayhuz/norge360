-- PostgreSQL generated this name for the original anonymous group-scope
-- check. The previous migration added the replacement named check, but this
-- legacy constraint remained on existing databases.

alter table public.community_group_chat_attachments
  drop constraint if exists community_group_chat_attachments_check;

alter table public.community_group_chat_attachments
  drop constraint if exists community_group_chat_attachments_storage_path_group_scope_check;

alter table public.community_group_chat_attachments
  add constraint community_group_chat_attachments_storage_path_group_scope_check
  check (split_part(storage_path, '/', 1) = group_id::text);
