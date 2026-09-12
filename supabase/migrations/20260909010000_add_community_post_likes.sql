-- A single like per user and post. This intentionally stores no reaction text
-- or private profile data; the iOS feed derives display counts from these rows.
create table if not exists public.community_post_likes (
  post_id uuid not null references public.community_posts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create index if not exists community_post_likes_post_created_at_index
  on public.community_post_likes (post_id, created_at desc);

alter table public.community_post_likes enable row level security;

drop policy if exists "Authenticated users can view likes on visible posts" on public.community_post_likes;
create policy "Authenticated users can view likes on visible posts"
on public.community_post_likes for select
to authenticated
using (
  exists (
    select 1
    from public.community_posts as post
    where post.id = post_id
      and public.can_view_community_user(post.author_id)
  )
);

drop policy if exists "Users can like visible posts" on public.community_post_likes;
create policy "Users can like visible posts"
on public.community_post_likes for insert
to authenticated
with check (
  (select auth.uid()) = user_id
  and exists (
    select 1
    from public.community_posts as post
    where post.id = post_id
      and public.can_view_community_user(post.author_id)
      and (
        post.group_id is null
        or exists (
          select 1
          from public.community_group_memberships as membership
          where membership.group_id = post.group_id
            and membership.user_id = (select auth.uid())
        )
      )
  )
);

drop policy if exists "Users can remove their own likes" on public.community_post_likes;
create policy "Users can remove their own likes"
on public.community_post_likes for delete
to authenticated
using ((select auth.uid()) = user_id);
