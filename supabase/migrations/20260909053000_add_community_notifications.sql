create table if not exists public.community_notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references auth.users(id) on delete cascade,
  actor_id uuid not null references auth.users(id) on delete cascade,
  type text not null check (type in ('follow', 'post_like', 'post_comment')),
  post_id uuid references public.community_posts(id) on delete cascade,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  constraint community_notifications_no_self_notification check (recipient_id <> actor_id)
);

create index if not exists community_notifications_recipient_created_idx
  on public.community_notifications (recipient_id, created_at desc);

alter table public.community_notifications enable row level security;

drop policy if exists "Users can view their visible notifications" on public.community_notifications;
drop policy if exists "Users can update their own notifications" on public.community_notifications;
drop policy if exists "Users can delete their own notifications" on public.community_notifications;

create policy "Users can view their visible notifications"
on public.community_notifications for select to authenticated
using (
  recipient_id = (select auth.uid())
  and public.can_view_community_user(actor_id)
);

create policy "Users can update their own notifications"
on public.community_notifications for update to authenticated
using (recipient_id = (select auth.uid()))
with check (recipient_id = (select auth.uid()));

create policy "Users can delete their own notifications"
on public.community_notifications for delete to authenticated
using (recipient_id = (select auth.uid()));

create or replace function public.create_community_follow_notification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.community_notifications (recipient_id, actor_id, type)
  values (new.following_id, new.follower_id, 'follow');
  return new;
end;
$$;

create or replace function public.create_community_post_like_notification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  recipient uuid;
begin
  select author_id into recipient from public.community_posts where id = new.post_id;
  if recipient is not null and recipient <> new.user_id then
    insert into public.community_notifications (recipient_id, actor_id, type, post_id)
    values (recipient, new.user_id, 'post_like', new.post_id);
  end if;
  return new;
end;
$$;

create or replace function public.remove_community_post_like_notification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.community_notifications
  where actor_id = old.user_id and type = 'post_like' and post_id = old.post_id;
  return old;
end;
$$;

create or replace function public.create_community_post_comment_notification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  recipient uuid;
begin
  select author_id into recipient from public.community_posts where id = new.post_id;
  if recipient is not null and recipient <> new.author_id then
    insert into public.community_notifications (recipient_id, actor_id, type, post_id)
    values (recipient, new.author_id, 'post_comment', new.post_id);
  end if;
  return new;
end;
$$;

drop trigger if exists community_follow_notification_after_insert on public.community_follows;
create trigger community_follow_notification_after_insert
after insert on public.community_follows
for each row execute procedure public.create_community_follow_notification();

drop trigger if exists community_post_like_notification_after_insert on public.community_post_likes;
create trigger community_post_like_notification_after_insert
after insert on public.community_post_likes
for each row execute procedure public.create_community_post_like_notification();

drop trigger if exists community_post_like_notification_after_delete on public.community_post_likes;
create trigger community_post_like_notification_after_delete
after delete on public.community_post_likes
for each row execute procedure public.remove_community_post_like_notification();

drop trigger if exists community_post_comment_notification_after_insert on public.community_comments;
create trigger community_post_comment_notification_after_insert
after insert on public.community_comments
for each row execute procedure public.create_community_post_comment_notification();

revoke all on function public.create_community_follow_notification() from public;
revoke all on function public.create_community_post_like_notification() from public;
revoke all on function public.remove_community_post_like_notification() from public;
revoke all on function public.create_community_post_comment_notification() from public;
