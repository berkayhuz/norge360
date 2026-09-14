-- Saved posts are private member-owned records. Mutations stay behind
-- security-definer RPCs so the iOS client cannot impersonate another member.

create table if not exists public.community_post_saves (
  post_id uuid not null references public.community_posts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create index if not exists community_post_saves_user_created_post_index
  on public.community_post_saves (user_id, created_at desc, post_id);

alter table public.community_post_saves enable row level security;
revoke all on public.community_post_saves from public, anon, authenticated;
grant select on public.community_post_saves to authenticated;

drop policy if exists "Users can view their own saved posts"
  on public.community_post_saves;
create policy "Users can view their own saved posts"
on public.community_post_saves for select
to authenticated
using ((select auth.uid()) = user_id);

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

  select *
  into target_post
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
     or (target_post.group_id is not null and not exists (
       select 1
       from public.community_groups as community_group
       where community_group.id = target_post.group_id
         and community_group.moderation_state = 'active'
     )) then
    raise exception 'post unavailable';
  end if;

  if exists (
    select 1
    from public.community_post_saves as saved
    where saved.post_id = target_post_id
      and saved.user_id = actor_id
  ) then
    delete from public.community_post_saves
    where post_id = target_post_id
      and user_id = actor_id;
    return false;
  end if;

  insert into public.community_post_saves (post_id, user_id)
  values (target_post_id, actor_id);
  return true;
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
  join public.community_posts as post
    on post.id = saved.post_id
  where saved.user_id = (select auth.uid())
    and post.moderation_state = 'active'
  order by saved.created_at desc
  limit 100;
$$;

revoke all on function public.toggle_community_post_save(uuid)
  from public, anon, authenticated;
grant execute on function public.toggle_community_post_save(uuid)
  to authenticated;

revoke all on function public.list_own_community_saved_post_ids()
  from public, anon, authenticated;
grant execute on function public.list_own_community_saved_post_ids()
  to authenticated;

-- This table is created after the general account-deletion trigger migration,
-- so attach the same server-side write boundary here as well.
do $$
begin
  if to_regprocedure('public.reject_community_account_deletion_write()') is not null then
    drop trigger if exists community_account_deletion_guard
      on public.community_post_saves;
    create trigger community_account_deletion_guard
      before insert or update or delete on public.community_post_saves
      for each row
      execute function public.reject_community_account_deletion_write();
  end if;
end;
$$;

comment on table public.community_post_saves is
  'Private saved-post records. Only the owning member may read them.';
