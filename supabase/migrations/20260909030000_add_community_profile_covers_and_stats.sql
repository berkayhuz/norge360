alter table public.community_profiles
  add column if not exists cover_path text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('profile-media', 'profile-media', false, 5242880, array['image/jpeg', 'image/png', 'image/heic'])
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Users can upload their own profile media" on storage.objects;
create policy "Users can upload their own profile media"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'profile-media'
  and (storage.foldername(name))[1] = (select auth.jwt()->>'sub')
);

drop policy if exists "Authenticated users can read permitted profile media" on storage.objects;
create policy "Authenticated users can read permitted profile media"
on storage.objects for select to authenticated
using (
  bucket_id = 'profile-media'
  and (
    (storage.foldername(name))[1] = (select auth.jwt()->>'sub')
    or exists (
      select 1
      from public.community_profiles as profile
      where profile.cover_path = name
        and profile.is_public
        and public.can_view_community_user(profile.user_id)
    )
  )
);

drop policy if exists "Users can update their own profile media" on storage.objects;
create policy "Users can update their own profile media"
on storage.objects for update to authenticated
using (
  bucket_id = 'profile-media'
  and (storage.foldername(name))[1] = (select auth.jwt()->>'sub')
)
with check (
  bucket_id = 'profile-media'
  and (storage.foldername(name))[1] = (select auth.jwt()->>'sub')
);

drop policy if exists "Users can delete their own profile media" on storage.objects;
create policy "Users can delete their own profile media"
on storage.objects for delete to authenticated
using (
  bucket_id = 'profile-media'
  and (storage.foldername(name))[1] = (select auth.jwt()->>'sub'));

create or replace view public.community_member_profile_stats
with (security_invoker = true)
as
select
  post.author_id as user_id,
  count(distinct post.id)::integer as posts_count,
  count(distinct (like_row.post_id, like_row.user_id))::integer as likes_count,
  count(distinct comment.id)::integer as comments_count
from public.community_posts as post
left join public.community_post_likes as like_row on like_row.post_id = post.id
left join public.community_comments as comment on comment.post_id = post.id
group by post.author_id;
