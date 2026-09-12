-- Preserve public post text revisions only after the short correction window.
-- The history is written by a database trigger, never trusted client input.
create table if not exists public.community_post_edit_history (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.community_posts(id) on delete cascade,
  previous_body text not null check (char_length(trim(previous_body)) between 1 and 4000),
  edited_at timestamptz not null default now(),
  edited_by uuid not null references auth.users(id) on delete cascade
);

create index if not exists community_post_edit_history_post_edited_at_index
  on public.community_post_edit_history (post_id, edited_at desc);

create or replace function public.capture_community_post_edit_history()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.body is distinct from old.body
     and old.created_at <= now() - interval '120 seconds' then
    insert into public.community_post_edit_history (post_id, previous_body, edited_at, edited_by)
    values (old.id, old.body, now(), old.author_id);
  end if;
  return new;
end;
$$;

revoke all on function public.capture_community_post_edit_history() from public;

drop trigger if exists capture_community_post_edit_history on public.community_posts;
create trigger capture_community_post_edit_history
before update on public.community_posts
for each row execute procedure public.capture_community_post_edit_history();

alter table public.community_post_edit_history enable row level security;

drop policy if exists "Authenticated users can view edit history for visible posts" on public.community_post_edit_history;
create policy "Authenticated users can view edit history for visible posts"
on public.community_post_edit_history for select
to authenticated
using (
  exists (
    select 1
    from public.community_posts as post
    where post.id = post_id
      and public.can_view_community_user(post.author_id)
  )
);
