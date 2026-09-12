-- Public, user-generated community media. These buckets intentionally contain
-- only avatars and media attached to public community posts; never documents or
-- sensitive relocation information.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('avatars', 'avatars', false, 5242880, array['image/jpeg', 'image/png', 'image/heic']),
  ('post-media', 'post-media', false, 10485760, array['image/jpeg', 'image/png', 'image/heic'])
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

alter table public.community_profiles
  add column if not exists avatar_path text;

create table if not exists public.community_post_media (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.community_posts(id) on delete cascade,
  storage_path text not null unique check (char_length(trim(storage_path)) between 1 and 500),
  sort_order smallint not null check (sort_order between 0 and 5),
  width integer not null check (width between 1 and 10000),
  height integer not null check (height between 1 and 10000),
  created_at timestamptz not null default now(),
  unique (post_id, sort_order)
);

create index if not exists community_post_media_post_order_index
  on public.community_post_media (post_id, sort_order);

create or replace function public.enforce_community_post_media_limit()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if (
    select count(*)
    from public.community_post_media
    where post_id = new.post_id
  ) >= 6 then
    raise exception 'A community post can contain at most six images.';
  end if;
  return new;
end;
$$;

drop trigger if exists enforce_community_post_media_limit on public.community_post_media;
create trigger enforce_community_post_media_limit
before insert on public.community_post_media
for each row execute procedure public.enforce_community_post_media_limit();

alter table public.community_post_media enable row level security;

drop policy if exists "Authenticated users can view visible post media" on public.community_post_media;
create policy "Authenticated users can view visible post media"
on public.community_post_media for select
to authenticated
using (
  exists (
    select 1
    from public.community_posts as post
    where post.id = post_id
      and public.can_view_community_user(post.author_id)
  )
);

drop policy if exists "Users can attach media to their own posts" on public.community_post_media;
create policy "Users can attach media to their own posts"
on public.community_post_media for insert
to authenticated
with check (
  exists (
    select 1
    from public.community_posts as post
    where post.id = post_id
      and post.author_id = (select auth.uid())
  )
);

drop policy if exists "Users can delete media from their own posts" on public.community_post_media;
create policy "Users can delete media from their own posts"
on public.community_post_media for delete
to authenticated
using (
  exists (
    select 1
    from public.community_posts as post
    where post.id = post_id
      and post.author_id = (select auth.uid())
  )
);

-- Object reads are public because avatars and post images are public community
-- content. Object mutations remain tied to the authenticated user-id folder.
-- Storage uploads return the created object metadata, so the uploader also
-- needs a matching SELECT policy even though the buckets are public.
drop policy if exists "Users can read their own avatars" on storage.objects;
create policy "Users can read their own avatars"
on storage.objects for select to authenticated
using (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = (select auth.jwt()->>'sub')
);

drop policy if exists "Users can upload their own avatars" on storage.objects;
create policy "Users can upload their own avatars"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists "Users can update their own avatars" on storage.objects;
create policy "Users can update their own avatars"
on storage.objects for update to authenticated
using (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = (select auth.uid())::text
)
with check (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists "Users can delete their own avatars" on storage.objects;
create policy "Users can delete their own avatars"
on storage.objects for delete to authenticated
using (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists "Users can upload their own post media" on storage.objects;
create policy "Users can upload their own post media"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'post-media'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists "Users can read their own post media" on storage.objects;
create policy "Users can read their own post media"
on storage.objects for select to authenticated
using (
  bucket_id = 'post-media'
  and (storage.foldername(name))[1] = (select auth.jwt()->>'sub')
);

drop policy if exists "Users can delete their own post media" on storage.objects;
create policy "Users can delete their own post media"
on storage.objects for delete to authenticated
using (
  bucket_id = 'post-media'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);
