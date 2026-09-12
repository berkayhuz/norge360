-- Group staff can remove a post from their own group without receiving broad
-- delete access to community content. The removal is audited and its private
-- storage paths are retained briefly only for post-delete object cleanup.

alter table public.community_group_moderation_audit
  add column if not exists target_post_id uuid;

alter table public.community_group_moderation_audit
  drop constraint if exists community_group_moderation_audit_action_check;

alter table public.community_group_moderation_audit
  add constraint community_group_moderation_audit_action_check
  check (action in ('ban', 'unban', 'remove_post'));

create table if not exists public.community_group_removed_post_media (
  storage_path text primary key,
  group_id uuid not null references public.community_groups(id) on delete cascade,
  post_id uuid not null,
  removed_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);

create index if not exists community_group_removed_post_media_group_created_idx
  on public.community_group_removed_post_media (group_id, created_at desc);

alter table public.community_group_removed_post_media enable row level security;

-- There is intentionally no client SELECT policy for cleanup records. They
-- merely extend the existing storage-delete authorization after post metadata
-- has been removed; they never expose a post or media path to the client.
drop policy if exists "Group staff can delete media from moderated posts" on storage.objects;
create policy "Group staff can delete media from moderated posts"
on storage.objects for delete to authenticated
using (
  bucket_id = 'post-media'
  and exists (
    select 1
    from public.community_group_removed_post_media as removed_media
    where removed_media.storage_path = storage.objects.name
      and public.can_manage_community_group(removed_media.group_id)
  )
);

create or replace function public.remove_community_group_post(target_post_id uuid)
returns table (storage_path text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  actor_role text;
  target_group_id uuid;
  target_author_id uuid;
  target_role text;
begin
  select post.group_id, post.author_id
    into target_group_id, target_author_id
  from public.community_posts as post
  where post.id = target_post_id;

  if target_group_id is null then
    raise exception 'group post not found';
  end if;

  select membership.role into actor_role
  from public.community_group_memberships as membership
  where membership.group_id = target_group_id
    and membership.user_id = actor_id;

  if actor_role not in ('owner', 'admin', 'moderator') then
    raise exception 'insufficient group permission';
  end if;

  -- Moderators and admins may moderate member posts, while only the owner can
  -- moderate staff posts. A member who has left the group is treated as a
  -- member for this purpose; otherwise their old content could never be
  -- removed by staff.
  select membership.role into target_role
  from public.community_group_memberships as membership
  where membership.group_id = target_group_id
    and membership.user_id = target_author_id;

  if actor_role <> 'owner' and coalesce(target_role, 'member') <> 'member' then
    raise exception 'you cannot moderate a staff member post';
  end if;

  insert into public.community_group_removed_post_media (storage_path, group_id, post_id, removed_by)
  select media.storage_path, target_group_id, target_post_id, actor_id
  from public.community_post_media as media
  where media.post_id = target_post_id
  on conflict on constraint community_group_removed_post_media_pkey do nothing;

  insert into public.community_group_moderation_audit (group_id, actor_id, target_user_id, target_post_id, action)
  values (target_group_id, actor_id, target_author_id, target_post_id, 'remove_post');

  delete from public.community_posts where id = target_post_id;

  return query
    select removed_media.storage_path
    from public.community_group_removed_post_media as removed_media
    where removed_media.post_id = target_post_id
    order by removed_media.storage_path;
end;
$$;

create or replace function public.acknowledge_community_group_post_media_cleanup(
  target_group_id uuid,
  paths text[]
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.can_manage_community_group(target_group_id) then
    raise exception 'insufficient group permission';
  end if;

  delete from public.community_group_removed_post_media
  where group_id = target_group_id
    and storage_path = any(paths);
end;
$$;

revoke all on function public.remove_community_group_post(uuid) from public;
grant execute on function public.remove_community_group_post(uuid) to authenticated;
revoke all on function public.acknowledge_community_group_post_media_cleanup(uuid, text[]) from public;
grant execute on function public.acknowledge_community_group_post_media_cleanup(uuid, text[]) to authenticated;
