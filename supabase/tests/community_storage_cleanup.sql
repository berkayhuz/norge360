-- Run against a disposable, fully migrated database as its owner.
-- Database triggers must queue public Storage paths even when the client
-- mutation succeeds and the provider is temporarily unavailable.
begin;

do $$
begin
  if to_regclass('public.community_storage_cleanup_outbox') is null
     or to_regprocedure('public.purge_community_storage_cleanup_outbox(integer)') is null then
    raise exception 'Missing public Storage cleanup outbox migration';
  end if;
end $$;

do $$
begin
  if has_function_privilege(
       'anon',
       'public.purge_community_storage_cleanup_outbox(integer)',
       'execute'
     )
     or has_function_privilege(
       'authenticated',
       'public.purge_community_storage_cleanup_outbox(integer)',
       'execute'
     )
     or not has_function_privilege(
       'service_role',
       'public.purge_community_storage_cleanup_outbox(integer)',
       'execute'
     ) then
    raise exception 'public Storage cleanup purge grant boundary is invalid';
  end if;
end $$;

insert into auth.users(id)
values ('a5000000-0000-4000-8000-000000000001');

insert into public.community_profiles(
  user_id, display_name, username, preferred_locale, norway_status
)
values (
  'a5000000-0000-4000-8000-000000000001',
  'Storage Cleanup Fixture',
  'storage_cleanup_fixture',
  'en',
  'resident'
);

insert into public.community_posts(id, author_id, title, body, kind)
values (
  'a5100000-0000-4000-8000-000000000001',
  'a5000000-0000-4000-8000-000000000001',
  'Storage cleanup post',
  'Storage cleanup fixture body',
  'update'
);

insert into public.community_post_media(
  id, post_id, storage_path, sort_order, width, height
)
values (
  'a5200000-0000-4000-8000-000000000001',
  'a5100000-0000-4000-8000-000000000001',
  'a5000000-0000-4000-8000-000000000001/post-fixture.jpg',
  0,
  640,
  480
);

delete from public.community_posts
where id = 'a5100000-0000-4000-8000-000000000001';

insert into public.community_groups(
  id, name, slug, description, scope, created_by, photo_path
)
values (
  'a5300000-0000-4000-8000-000000000001',
  'Storage Cleanup Group',
  'storage-cleanup-group',
  'Storage cleanup fixture group',
  'interest',
  'a5000000-0000-4000-8000-000000000001',
  'a5300000-0000-4000-8000-000000000001/old-photo.jpg'
);

update public.community_groups
set photo_path = 'a5300000-0000-4000-8000-000000000001/new-photo.jpg'
where id = 'a5300000-0000-4000-8000-000000000001';

do $$
begin
  if not exists (
    select 1
    from public.community_storage_cleanup_outbox
    where bucket_id = 'post-media'
      and storage_path = 'a5000000-0000-4000-8000-000000000001/post-fixture.jpg'
      and processed_at is null
  ) then
    raise exception 'post media deletion did not enqueue Storage cleanup';
  end if;

  if not exists (
    select 1
    from public.community_storage_cleanup_outbox
    where bucket_id = 'group-media'
      and storage_path = 'a5300000-0000-4000-8000-000000000001/old-photo.jpg'
      and processed_at is null
  ) then
    raise exception 'group photo replacement did not enqueue Storage cleanup';
  end if;
end $$;

rollback;
