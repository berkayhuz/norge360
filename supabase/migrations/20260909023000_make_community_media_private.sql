-- Community media is private at the Storage layer. The iOS app requests
-- short-lived signed URLs only after the matching database RLS checks pass.
update storage.buckets
set public = false
where id in ('avatars', 'post-media');

drop policy if exists "Users can read their own avatars" on storage.objects;
create policy "Authenticated users can read permitted avatars"
on storage.objects for select
to authenticated
using (
  bucket_id = 'avatars'
  and (
    (storage.foldername(name))[1] = (select auth.jwt()->>'sub')
    or exists (
      select 1
      from public.community_profiles as profile
      where profile.avatar_path = name
        and profile.is_public
        and public.can_view_community_user(profile.user_id)
    )
  )
);

drop policy if exists "Users can read their own post media" on storage.objects;
create policy "Authenticated users can read permitted post media"
on storage.objects for select
to authenticated
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
        and profile.is_public
        and public.can_view_community_user(post.author_id)
    )
  )
);
