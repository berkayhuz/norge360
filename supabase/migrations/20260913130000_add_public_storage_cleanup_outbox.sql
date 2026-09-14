-- Public post and group media must not depend on a best-effort client-side
-- Storage delete. Queue old object paths in the same database transaction as
-- the metadata mutation and let the server-only Worker retry cleanup.

create table if not exists public.community_storage_cleanup_outbox (
  id uuid primary key default gen_random_uuid(),
  bucket_id text not null check (bucket_id in ('post-media', 'group-media')),
  storage_path text not null check (char_length(btrim(storage_path)) between 1 and 500),
  attempts integer not null default 0 check (attempts >= 0),
  available_at timestamptz not null default now(),
  processed_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  unique (bucket_id, storage_path)
);

create index if not exists community_storage_cleanup_pending_idx
  on public.community_storage_cleanup_outbox (available_at, created_at, id)
  where processed_at is null;

alter table public.community_storage_cleanup_outbox enable row level security;
revoke all on table public.community_storage_cleanup_outbox from anon, authenticated;

create or replace function public.queue_community_post_media_cleanup()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.community_storage_cleanup_outbox (bucket_id, storage_path)
  values ('post-media', old.storage_path)
  on conflict (bucket_id, storage_path) do nothing;
  return old;
end;
$$;

drop trigger if exists queue_community_post_media_cleanup on public.community_post_media;
create trigger queue_community_post_media_cleanup
after delete on public.community_post_media
for each row execute procedure public.queue_community_post_media_cleanup();

create or replace function public.queue_community_group_photo_cleanup()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.photo_path is not null and old.photo_path <> new.photo_path then
    insert into public.community_storage_cleanup_outbox (bucket_id, storage_path)
    values ('group-media', old.photo_path)
    on conflict (bucket_id, storage_path) do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists queue_community_group_photo_cleanup on public.community_groups;
create trigger queue_community_group_photo_cleanup
after update of photo_path on public.community_groups
for each row execute procedure public.queue_community_group_photo_cleanup();

create or replace function public.purge_community_storage_cleanup_outbox(
  target_batch_size integer default 500
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  removed_count integer;
begin
  if target_batch_size is null or target_batch_size < 1 or target_batch_size > 5_000 then
    raise exception 'invalid cleanup purge batch size';
  end if;

  delete from public.community_storage_cleanup_outbox
  where id in (
    select id
    from public.community_storage_cleanup_outbox
    where processed_at is not null
      and processed_at < now() - interval '7 days'
    order by processed_at asc
    limit target_batch_size
  );

  get diagnostics removed_count = row_count;
  return removed_count;
end;
$$;

revoke all on function public.queue_community_post_media_cleanup() from public, anon, authenticated;
revoke all on function public.queue_community_group_photo_cleanup() from public, anon, authenticated;
revoke all on function public.purge_community_storage_cleanup_outbox(integer) from public, anon, authenticated;
grant execute on function public.purge_community_storage_cleanup_outbox(integer) to service_role;

comment on table public.community_storage_cleanup_outbox is
  'Server-owned retry queue for public Storage objects whose database metadata was replaced or deleted.';
comment on function public.queue_community_post_media_cleanup() is
  'Queues post-media Storage cleanup whenever post-media metadata is deleted, including cascades.';
comment on function public.queue_community_group_photo_cleanup() is
  'Queues the previous group photo for server-side Storage cleanup after a photo replacement.';
comment on function public.purge_community_storage_cleanup_outbox(integer) is
  'Removes completed public Storage cleanup records after their retention window.';
