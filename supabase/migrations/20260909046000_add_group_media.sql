alter table public.community_groups add column if not exists photo_path text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('group-media', 'group-media', false, 5242880, array['image/jpeg'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Authenticated users can read group media" on storage.objects;
drop policy if exists "Group managers can upload group media" on storage.objects;
drop policy if exists "Group managers can delete group media" on storage.objects;

create policy "Authenticated users can read group media" on storage.objects for select to authenticated
using (bucket_id = 'group-media');
create policy "Group managers can upload group media" on storage.objects for insert to authenticated
with check (bucket_id = 'group-media' and public.can_manage_community_group(((storage.foldername(name))[1])::uuid));
create policy "Group managers can delete group media" on storage.objects for delete to authenticated
using (bucket_id = 'group-media' and public.can_manage_community_group(((storage.foldername(name))[1])::uuid));

create or replace function public.set_community_group_photo(target_group_id uuid, new_path text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.can_manage_community_group(target_group_id) then raise exception 'insufficient group permission'; end if;
  if new_path !~ ('^' || target_group_id::text || '/[a-z0-9-]+\\.jpg$') then raise exception 'invalid group media path'; end if;
  update public.community_groups set photo_path = new_path where id = target_group_id;
end;
$$;
revoke all on function public.set_community_group_photo(uuid, text) from public;
grant execute on function public.set_community_group_photo(uuid, text) to authenticated;
