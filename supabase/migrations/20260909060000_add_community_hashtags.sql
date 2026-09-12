create table if not exists public.community_post_hashtags (
  post_id uuid not null references public.community_posts(id) on delete cascade,
  tag text not null check (tag ~ '^[[:alnum:]_]{2,50}$'),
  primary key (post_id, tag)
);

create table if not exists public.community_comment_hashtags (
  comment_id uuid not null references public.community_comments(id) on delete cascade,
  tag text not null check (tag ~ '^[[:alnum:]_]{2,50}$'),
  primary key (comment_id, tag)
);

create index if not exists community_post_hashtags_tag_idx on public.community_post_hashtags (tag);
create index if not exists community_comment_hashtags_tag_idx on public.community_comment_hashtags (tag);

alter table public.community_post_hashtags enable row level security;
alter table public.community_comment_hashtags enable row level security;

create or replace function public.sync_community_post_hashtags()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.community_post_hashtags where post_id = new.id;
  insert into public.community_post_hashtags (post_id, tag)
  select new.id, lower(match[1])
  from regexp_matches(new.body, '#([[:alnum:]_]{2,50})', 'g') as match
  on conflict do nothing;
  return new;
end;
$$;

create or replace function public.sync_community_comment_hashtags()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.community_comment_hashtags where comment_id = new.id;
  insert into public.community_comment_hashtags (comment_id, tag)
  select new.id, lower(match[1])
  from regexp_matches(new.body, '#([[:alnum:]_]{2,50})', 'g') as match
  on conflict do nothing;
  return new;
end;
$$;

drop trigger if exists community_post_hashtags_after_insert_or_update on public.community_posts;
create trigger community_post_hashtags_after_insert_or_update
after insert or update of body on public.community_posts
for each row execute procedure public.sync_community_post_hashtags();

drop trigger if exists community_comment_hashtags_after_insert_or_update on public.community_comments;
create trigger community_comment_hashtags_after_insert_or_update
after insert or update of body on public.community_comments
for each row execute procedure public.sync_community_comment_hashtags();

-- Backfill existing public and private content once. Suggestions below only
-- include tags from content that is currently visible to the requesting user.
insert into public.community_post_hashtags (post_id, tag)
select post.id, lower(match[1])
from public.community_posts as post
cross join lateral regexp_matches(post.body, '#([[:alnum:]_]{2,50})', 'g') as match
on conflict do nothing;

insert into public.community_comment_hashtags (comment_id, tag)
select comment.id, lower(match[1])
from public.community_comments as comment
cross join lateral regexp_matches(comment.body, '#([[:alnum:]_]{2,50})', 'g') as match
on conflict do nothing;

create or replace function public.search_community_hashtags(prefix text)
returns table (tag text, usage_count integer)
language sql
stable
security definer
set search_path = ''
as $$
  with normalized as (
    select lower(trim(prefix)) as value
  ), visible_tags as (
    select post_tag.tag
    from public.community_post_hashtags as post_tag
    join public.community_posts as post on post.id = post_tag.post_id
    join public.community_profiles as author on author.user_id = post.author_id
    where author.is_public and public.can_view_community_user(post.author_id)

    union all

    select comment_tag.tag
    from public.community_comment_hashtags as comment_tag
    join public.community_comments as comment on comment.id = comment_tag.comment_id
    join public.community_posts as post on post.id = comment.post_id
    join public.community_profiles as post_author on post_author.user_id = post.author_id
    join public.community_profiles as comment_author on comment_author.user_id = comment.author_id
    where post_author.is_public
      and comment_author.is_public
      and public.can_view_community_user(post.author_id)
      and public.can_view_community_user(comment.author_id)
  )
  select visible_tags.tag, count(*)::integer as usage_count
  from visible_tags, normalized
  where length(normalized.value) >= 1
    and visible_tags.tag like normalized.value || '%'
  group by visible_tags.tag
  order by usage_count desc, visible_tags.tag asc
  limit 8;
$$;

revoke all on function public.sync_community_post_hashtags() from public;
revoke all on function public.sync_community_comment_hashtags() from public;
revoke all on function public.search_community_hashtags(text) from public;
grant execute on function public.search_community_hashtags(text) to authenticated;
