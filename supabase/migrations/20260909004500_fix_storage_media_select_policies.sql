-- Supabase Storage performs an INSERT followed by RETURNING on upload.
-- The existing user-folder INSERT policies therefore require matching SELECT
-- policies for the authenticated uploader to receive the created object.

drop policy if exists "Users can read their own avatars" on storage.objects;
create policy "Users can read their own avatars"
on storage.objects for select to authenticated
using (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = (select auth.jwt()->>'sub')
);

drop policy if exists "Users can read their own post media" on storage.objects;
create policy "Users can read their own post media"
on storage.objects for select to authenticated
using (
  bucket_id = 'post-media'
  and (storage.foldername(name))[1] = (select auth.jwt()->>'sub')
);
