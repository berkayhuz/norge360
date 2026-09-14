-- Event photos live in their own private bucket and must be included in the
-- existing resumable account-deletion inventory and cleanup workflow.

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
    select 1 from public.community_account_deletion_jobs
    where user_id = account_user_id and status <> 'completed'
  ) then
    raise exception 'deletion job not found';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(storage_objects) as item
    where item->>'bucket' not in ('avatars', 'profile-media', 'post-media', 'event-media')
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
  where user_id = account_user_id and status <> 'completed';
end;
$$;

revoke all on function public.record_community_account_deletion_inventory(uuid, jsonb, text[]) from public, anon, authenticated;
grant execute on function public.record_community_account_deletion_inventory(uuid, jsonb, text[]) to service_role;
