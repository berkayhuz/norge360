-- Community profiles are public by default for continuity with the existing
-- feed. A member may hide their profile at any time; private profiles and all
-- associated community content are then excluded by RLS for other members.
alter table public.community_profiles
  add column if not exists is_public boolean not null default true;

drop policy if exists "Authenticated users can view visible community profiles" on public.community_profiles;
create policy "Authenticated users can view visible community profiles"
on public.community_profiles for select
to authenticated
using (
  user_id = (select auth.uid())
  or (is_public and public.can_view_community_user(user_id))
);

drop policy if exists "Authenticated users can view visible posts" on public.community_posts;
create policy "Authenticated users can view visible posts"
on public.community_posts for select
to authenticated
using (
  author_id = (select auth.uid())
  or (
    public.can_view_community_user(author_id)
    and exists (
      select 1
      from public.community_profiles as profile
      where profile.user_id = author_id
        and profile.is_public
    )
  )
);

drop policy if exists "Authenticated users can view visible comments" on public.community_comments;
create policy "Authenticated users can view visible comments"
on public.community_comments for select
to authenticated
using (
  author_id = (select auth.uid())
  or (
    public.can_view_community_user(author_id)
    and exists (
      select 1
      from public.community_profiles as author_profile
      where author_profile.user_id = author_id
        and author_profile.is_public
    )
    and exists (
      select 1
      from public.community_posts as post
      join public.community_profiles as post_author on post_author.user_id = post.author_id
      where post.id = post_id
        and post_author.is_public
    )
  )
);

drop policy if exists "Authenticated users can view visible post media" on public.community_post_media;
create policy "Authenticated users can view visible post media"
on public.community_post_media for select
to authenticated
using (
  exists (
    select 1
    from public.community_posts as post
    join public.community_profiles as profile on profile.user_id = post.author_id
    where post.id = post_id
      and (post.author_id = (select auth.uid()) or profile.is_public)
      and public.can_view_community_user(post.author_id)
  )
);

drop policy if exists "Authenticated users can view likes on visible posts" on public.community_post_likes;
create policy "Authenticated users can view likes on visible posts"
on public.community_post_likes for select
to authenticated
using (
  exists (
    select 1
    from public.community_posts as post
    join public.community_profiles as profile on profile.user_id = post.author_id
    where post.id = post_id
      and (post.author_id = (select auth.uid()) or profile.is_public)
      and public.can_view_community_user(post.author_id)
  )
);

drop policy if exists "Authenticated users can view edit history for visible posts" on public.community_post_edit_history;
create policy "Authenticated users can view edit history for visible posts"
on public.community_post_edit_history for select
to authenticated
using (
  exists (
    select 1
    from public.community_posts as post
    join public.community_profiles as profile on profile.user_id = post.author_id
    where post.id = post_id
      and (post.author_id = (select auth.uid()) or profile.is_public)
      and public.can_view_community_user(post.author_id)
  )
);
