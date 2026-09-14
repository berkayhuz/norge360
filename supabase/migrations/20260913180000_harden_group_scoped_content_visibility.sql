-- Group visibility is an authorization boundary, not only a discovery concern.
-- Public groups expose public content; approval-required and private groups
-- expose content only to accepted members. Pending requests and invitations
-- may resolve group metadata, but they do not grant content access.
create or replace function public.can_view_community_group(target_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.community_groups as community_group
    where community_group.id = target_group_id
      and community_group.moderation_state = 'active'
      and (
        community_group.visibility = 'public'
        or exists (
          select 1
          from public.community_group_memberships as membership
          where membership.group_id = community_group.id
            and membership.user_id = (select auth.uid())
        )
      )
  );
$$;

revoke all on function public.can_view_community_group(uuid) from public;
grant execute on function public.can_view_community_group(uuid) to authenticated;

-- Like/save RPCs are intentionally SECURITY DEFINER because their mutation
-- tables are server-authorized. Reapply the group visibility check explicitly
-- instead of relying on the caller's table RLS inside those functions.
create or replace function public.toggle_community_post_like(target_post_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  target_post public.community_posts;
begin
  if actor_id is null then
    raise exception 'authentication required';
  end if;

  select * into target_post
  from public.community_posts
  where id = target_post_id;

  if target_post.id is null
     or target_post.moderation_state <> 'active'
     or not public.can_view_community_user(target_post.author_id)
     or not exists (
       select 1
       from public.community_profiles as profile
       where profile.user_id = target_post.author_id
         and profile.is_public
         and profile.moderation_state = 'active'
     )
     or (target_post.group_id is not null
         and not public.can_view_community_group(target_post.group_id)) then
    raise exception 'post unavailable';
  end if;

  insert into public.community_post_likes (post_id, user_id)
  values (target_post_id, actor_id)
  on conflict (post_id, user_id) do nothing;
  if found then
    return true;
  end if;

  delete from public.community_post_likes
  where post_id = target_post_id and user_id = actor_id;
  return false;
end;
$$;

create or replace function public.toggle_community_post_save(target_post_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  target_post public.community_posts;
begin
  if actor_id is null then
    raise exception 'authentication required';
  end if;

  select * into target_post
  from public.community_posts
  where id = target_post_id;

  if target_post.id is null
     or target_post.moderation_state <> 'active'
     or not public.can_view_community_user(target_post.author_id)
     or not exists (
       select 1
       from public.community_profiles as profile
       where profile.user_id = target_post.author_id
         and profile.is_public
         and profile.moderation_state = 'active'
     )
     or (target_post.group_id is not null
         and not public.can_view_community_group(target_post.group_id)) then
    raise exception 'post unavailable';
  end if;

  if exists (
    select 1
    from public.community_post_saves as saved
    where saved.post_id = target_post_id and saved.user_id = actor_id
  ) then
    delete from public.community_post_saves
    where post_id = target_post_id and user_id = actor_id;
    return false;
  end if;

  insert into public.community_post_saves (post_id, user_id)
  values (target_post_id, actor_id);
  return true;
end;
$$;

create or replace function public.list_community_liked_post_ids(target_user_id uuid)
returns table (post_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
begin
  if actor_id is null then
    raise exception 'authentication required';
  end if;
  if not public.can_view_community_liked_posts(target_user_id) then
    raise exception 'liked posts unavailable';
  end if;

  return query
  select like_row.post_id
  from public.community_post_likes as like_row
  join public.community_posts as post on post.id = like_row.post_id
  join public.community_profiles as profile on profile.user_id = post.author_id
  where like_row.user_id = target_user_id
    and post.moderation_state = 'active'
    and (
      post.author_id = actor_id
      or (
        profile.is_public
        and public.can_view_community_user(post.author_id)
      )
    )
    and (post.group_id is null or public.can_view_community_group(post.group_id))
  order by like_row.created_at desc
  limit 30;
end;
$$;

create or replace function public.list_own_community_saved_post_ids()
returns table (post_id uuid)
language sql
stable
security definer
set search_path = ''
as $$
  select saved.post_id
  from public.community_post_saves as saved
  join public.community_posts as post on post.id = saved.post_id
  where saved.user_id = (select auth.uid())
    and post.moderation_state = 'active'
    and (post.group_id is null or public.can_view_community_group(post.group_id))
  order by saved.created_at desc
  limit 100;
$$;

revoke all on function public.toggle_community_post_like(uuid) from public;
grant execute on function public.toggle_community_post_like(uuid) to authenticated;
revoke all on function public.toggle_community_post_save(uuid) from public;
grant execute on function public.toggle_community_post_save(uuid) to authenticated;
revoke all on function public.list_community_liked_post_ids(uuid) from public;
grant execute on function public.list_community_liked_post_ids(uuid) to authenticated;
revoke all on function public.list_own_community_saved_post_ids() from public;
grant execute on function public.list_own_community_saved_post_ids() to authenticated;

drop policy if exists "Authenticated users can view visible posts" on public.community_posts;
create policy "Authenticated users can view visible posts"
on public.community_posts for select to authenticated
using (
  moderation_state = 'active'
  and public.can_view_community_user(author_id)
  and exists (
    select 1
    from public.community_profiles as profile
    where profile.user_id = author_id
      and profile.moderation_state = 'active'
      and (profile.user_id = (select auth.uid()) or profile.is_public)
  )
  and (group_id is null or public.can_view_community_group(group_id))
);

drop policy if exists "Authenticated users can view visible comments" on public.community_comments;
create policy "Authenticated users can view visible comments"
on public.community_comments for select to authenticated
using (
  moderation_state = 'active'
  and public.can_view_community_user(author_id)
  and exists (
    select 1
    from public.community_profiles as author_profile
    where author_profile.user_id = author_id
      and author_profile.moderation_state = 'active'
      and (author_profile.user_id = (select auth.uid()) or author_profile.is_public)
  )
  and exists (
    select 1
    from public.community_posts as post
    join public.community_profiles as post_author on post_author.user_id = post.author_id
    where post.id = post_id
      and post.moderation_state = 'active'
      and post_author.moderation_state = 'active'
      and (post_author.user_id = (select auth.uid()) or post_author.is_public)
      and (post.group_id is null or public.can_view_community_group(post.group_id))
  )
);

drop policy if exists "Authenticated users can view visible post media" on public.community_post_media;
create policy "Authenticated users can view visible post media"
on public.community_post_media for select to authenticated
using (
  exists (
    select 1
    from public.community_posts as post
    join public.community_profiles as profile on profile.user_id = post.author_id
    where post.id = post_id
      and post.moderation_state = 'active'
      and profile.moderation_state = 'active'
      and (post.author_id = (select auth.uid()) or profile.is_public)
      and public.can_view_community_user(post.author_id)
      and (post.group_id is null or public.can_view_community_group(post.group_id))
  )
);

drop policy if exists "Authenticated users can view likes on visible posts" on public.community_post_likes;
create policy "Authenticated users can view likes on visible posts"
on public.community_post_likes for select to authenticated
using (
  exists (
    select 1
    from public.community_posts as post
    join public.community_profiles as profile on profile.user_id = post.author_id
    where post.id = post_id
      and post.moderation_state = 'active'
      and profile.moderation_state = 'active'
      and (post.author_id = (select auth.uid()) or profile.is_public)
      and public.can_view_community_user(post.author_id)
      and (post.group_id is null or public.can_view_community_group(post.group_id))
  )
);

drop policy if exists "Authenticated users can view edit history for visible posts" on public.community_post_edit_history;
create policy "Authenticated users can view edit history for visible posts"
on public.community_post_edit_history for select to authenticated
using (
  exists (
    select 1
    from public.community_posts as post
    join public.community_profiles as profile on profile.user_id = post.author_id
    where post.id = post_id
      and post.moderation_state = 'active'
      and profile.moderation_state = 'active'
      and (post.author_id = (select auth.uid()) or profile.is_public)
      and public.can_view_community_user(post.author_id)
      and (post.group_id is null or public.can_view_community_group(post.group_id))
  )
);

-- Hashtag rows are projections of post/comment content and must inherit the
-- same visibility boundary before invoker search RPCs can read them.
drop policy if exists "Authenticated users can view visible post hashtags" on public.community_post_hashtags;
create policy "Authenticated users can view visible post hashtags"
on public.community_post_hashtags for select to authenticated
using (
  exists (
    select 1
    from public.community_posts as post
    join public.community_profiles as profile on profile.user_id = post.author_id
    where post.id = post_id
      and post.moderation_state = 'active'
      and profile.moderation_state = 'active'
      and (post.author_id = (select auth.uid()) or profile.is_public)
      and public.can_view_community_user(post.author_id)
      and (post.group_id is null or public.can_view_community_group(post.group_id))
  )
);

drop policy if exists "Authenticated users can view visible comment hashtags" on public.community_comment_hashtags;
create policy "Authenticated users can view visible comment hashtags"
on public.community_comment_hashtags for select to authenticated
using (
  exists (
    select 1
    from public.community_comments as comment
    join public.community_posts as post on post.id = comment.post_id
    join public.community_profiles as comment_author on comment_author.user_id = comment.author_id
    join public.community_profiles as post_author on post_author.user_id = post.author_id
    where comment.id = comment_id
      and comment.moderation_state = 'active'
      and comment_author.moderation_state = 'active'
      and post.moderation_state = 'active'
      and post_author.moderation_state = 'active'
      and (comment.author_id = (select auth.uid()) or comment_author.is_public)
      and (post.author_id = (select auth.uid()) or post_author.is_public)
      and public.can_view_community_user(comment.author_id)
      and public.can_view_community_user(post.author_id)
      and (post.group_id is null or public.can_view_community_group(post.group_id))
  )
);

-- These read-only projections previously used SECURITY DEFINER only to avoid
-- client-side fan-out. They do not need elevated privileges; invoker mode
-- makes the database RLS policies the final boundary for every projection.
alter function public.list_community_feed_page(text, integer) security invoker;
alter function public.list_community_post_comments(uuid, text, integer) security invoker;
alter function public.list_community_member_media_posts_page(uuid, text, integer) security invoker;
alter function public.search_community_post_results(text) security invoker;
alter function public.search_community_hashtags(text) security invoker;
alter function public.search_community_hashtag_posts(text) security invoker;

-- Private/approval-required group photos follow the same member boundary.
drop policy if exists "Authenticated users can read group media" on storage.objects;
create policy "Authenticated users can read group media" on storage.objects
for select to authenticated
using (
  bucket_id = 'group-media'
  and public.can_view_community_group(((storage.foldername(name))[1])::uuid)
);

-- Post-media signed URL issuance must not bypass group membership even when a
-- storage path is known. Database RLS protects the row; this protects the blob.
drop policy if exists "Authenticated users can read permitted post media" on storage.objects;
create policy "Authenticated users can read permitted post media" on storage.objects
for select to authenticated
using (
  bucket_id = 'post-media'
  and (
    (storage.foldername(name))[1] = (select auth.jwt()->>'sub')
    or exists (
      select 1
      from public.community_post_media as media
      join public.community_posts as post on post.id = media.post_id
      join public.community_profiles as profile on profile.user_id = post.author_id
      where media.storage_path = name
        and post.moderation_state = 'active'
        and profile.moderation_state = 'active'
        and (post.author_id = (select auth.uid()) or profile.is_public)
        and public.can_view_community_user(post.author_id)
        and (post.group_id is null or public.can_view_community_group(post.group_id))
    )
  )
);
