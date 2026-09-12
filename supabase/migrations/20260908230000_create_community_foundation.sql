-- Norge360 community MVP foundation.
-- This migration stores only deliberately public community fields. Account email,
-- Auth credentials, and private relocation data remain outside these tables.

create table if not exists public.community_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(trim(display_name)) between 1 and 80),
  preferred_locale text not null check (preferred_locale in (
    'en', 'nb', 'tr', 'ar', 'fa', 'fr', 'es', 'de', 'uk', 'ru', 'pl', 'so', 'ti', 'am', 'ur', 'fa-AF'
  )),
  norway_status text not null check (norway_status in (
    'planning_move', 'new_to_norway', 'resident', 'visitor'
  )),
  city_or_region text check (city_or_region is null or char_length(trim(city_or_region)) between 1 and 120),
  public_languages text[] not null default '{}',
  interests text[] not null default '{}' check (cardinality(interests) <= 12),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (public_languages <@ array['en', 'nb', 'tr', 'ar', 'fa', 'fr', 'es', 'de', 'uk', 'ru', 'pl', 'so', 'ti', 'am', 'ur', 'fa-AF'])
);

create table if not exists public.community_groups (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 1 and 100),
  slug text not null unique check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  description text not null check (char_length(trim(description)) between 1 and 500),
  scope text not null check (scope in ('city', 'interest')),
  city_or_region text check (city_or_region is null or char_length(trim(city_or_region)) between 1 and 120),
  visibility text not null default 'public' check (visibility in ('public', 'approval_required')),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.community_group_memberships (
  group_id uuid not null references public.community_groups(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('member', 'host', 'moderator')),
  created_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

create table if not exists public.user_blocks (
  blocker_id uuid not null references auth.users(id) on delete cascade,
  blocked_user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_user_id),
  check (blocker_id <> blocked_user_id)
);

create table if not exists public.community_posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references auth.users(id) on delete cascade,
  group_id uuid references public.community_groups(id) on delete set null,
  body text not null check (char_length(trim(body)) between 1 and 4000),
  kind text not null default 'update' check (kind in ('update', 'question', 'recommendation')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.community_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.community_posts(id) on delete cascade,
  author_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(trim(body)) between 1 and 2000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.community_events (
  id uuid primary key default gen_random_uuid(),
  host_id uuid not null references auth.users(id) on delete cascade,
  group_id uuid references public.community_groups(id) on delete set null,
  title text not null check (char_length(trim(title)) between 1 and 120),
  description text not null check (char_length(trim(description)) between 1 and 4000),
  area_label text not null check (char_length(trim(area_label)) between 1 and 160),
  starts_at timestamptz not null,
  capacity integer check (capacity is null or capacity between 1 and 500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.community_event_rsvps (
  event_id uuid not null references public.community_events(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null check (status in ('interested', 'going')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (event_id, user_id)
);

create table if not exists public.community_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users(id) on delete cascade,
  target_type text not null check (target_type in ('profile', 'post', 'comment', 'event')),
  target_id uuid not null,
  reason text not null check (char_length(trim(reason)) between 1 and 120),
  details text check (details is null or char_length(trim(details)) <= 1000),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id) on delete set null
);

create index if not exists community_posts_created_at_index on public.community_posts (created_at desc);
create index if not exists community_posts_group_created_at_index on public.community_posts (group_id, created_at desc);
create index if not exists community_comments_post_created_at_index on public.community_comments (post_id, created_at);
create index if not exists community_events_starts_at_index on public.community_events (starts_at);
create index if not exists community_reports_created_at_index on public.community_reports (created_at desc);

create or replace function public.set_community_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function public.can_view_community_user(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    (select auth.uid()) = target_user_id
    or not exists (
      select 1
      from public.user_blocks as block
      where (block.blocker_id = (select auth.uid()) and block.blocked_user_id = target_user_id)
         or (block.blocker_id = target_user_id and block.blocked_user_id = (select auth.uid()))
    );
$$;

revoke all on function public.can_view_community_user(uuid) from public;
grant execute on function public.can_view_community_user(uuid) to authenticated;

drop trigger if exists set_community_profiles_updated_at on public.community_profiles;
create trigger set_community_profiles_updated_at
before update on public.community_profiles
for each row execute procedure public.set_community_updated_at();

drop trigger if exists set_community_posts_updated_at on public.community_posts;
create trigger set_community_posts_updated_at
before update on public.community_posts
for each row execute procedure public.set_community_updated_at();

drop trigger if exists set_community_comments_updated_at on public.community_comments;
create trigger set_community_comments_updated_at
before update on public.community_comments
for each row execute procedure public.set_community_updated_at();

drop trigger if exists set_community_events_updated_at on public.community_events;
create trigger set_community_events_updated_at
before update on public.community_events
for each row execute procedure public.set_community_updated_at();

drop trigger if exists set_community_event_rsvps_updated_at on public.community_event_rsvps;
create trigger set_community_event_rsvps_updated_at
before update on public.community_event_rsvps
for each row execute procedure public.set_community_updated_at();

alter table public.community_profiles enable row level security;
alter table public.community_groups enable row level security;
alter table public.community_group_memberships enable row level security;
alter table public.user_blocks enable row level security;
alter table public.community_posts enable row level security;
alter table public.community_comments enable row level security;
alter table public.community_events enable row level security;
alter table public.community_event_rsvps enable row level security;
alter table public.community_reports enable row level security;

-- Public community fields are readable by signed-in users, except where either
-- party has blocked the other. Auth email and account data are never selected.
drop policy if exists "Authenticated users can view visible community profiles" on public.community_profiles;
create policy "Authenticated users can view visible community profiles"
on public.community_profiles for select
to authenticated
using (public.can_view_community_user(user_id));

drop policy if exists "Users can create their own community profile" on public.community_profiles;
create policy "Users can create their own community profile"
on public.community_profiles for insert
to authenticated
with check ((select auth.uid()) = user_id);

drop policy if exists "Users can update their own community profile" on public.community_profiles;
create policy "Users can update their own community profile"
on public.community_profiles for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

drop policy if exists "Users can delete their own community profile" on public.community_profiles;
create policy "Users can delete their own community profile"
on public.community_profiles for delete
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "Authenticated users can view community groups" on public.community_groups;
create policy "Authenticated users can view community groups"
on public.community_groups for select
to authenticated
using (true);

-- Curated groups are created by a server-side moderation workflow, not directly
-- by the untrusted iOS client during the MVP.
drop policy if exists "Users can view their own group memberships" on public.community_group_memberships;
create policy "Users can view their own group memberships"
on public.community_group_memberships for select
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "Users can join public groups as members" on public.community_group_memberships;
create policy "Users can join public groups as members"
on public.community_group_memberships for insert
to authenticated
with check (
  (select auth.uid()) = user_id
  and role = 'member'
  and exists (
    select 1
    from public.community_profiles as profile
    where profile.user_id = (select auth.uid())
  )
  and exists (
    select 1
    from public.community_groups as community_group
    where community_group.id = group_id
      and community_group.visibility = 'public'
  )
);

drop policy if exists "Users can leave their own groups" on public.community_group_memberships;
create policy "Users can leave their own groups"
on public.community_group_memberships for delete
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "Users can view their own blocks" on public.user_blocks;
create policy "Users can view their own blocks"
on public.user_blocks for select
to authenticated
using ((select auth.uid()) = blocker_id);

drop policy if exists "Users can block another user" on public.user_blocks;
create policy "Users can block another user"
on public.user_blocks for insert
to authenticated
with check ((select auth.uid()) = blocker_id and blocker_id <> blocked_user_id);

drop policy if exists "Users can remove their own blocks" on public.user_blocks;
create policy "Users can remove their own blocks"
on public.user_blocks for delete
to authenticated
using ((select auth.uid()) = blocker_id);

drop policy if exists "Authenticated users can view visible posts" on public.community_posts;
create policy "Authenticated users can view visible posts"
on public.community_posts for select
to authenticated
using (public.can_view_community_user(author_id));

drop policy if exists "Users can create their own posts" on public.community_posts;
create policy "Users can create their own posts"
on public.community_posts for insert
to authenticated
with check (
  (select auth.uid()) = author_id
  and exists (
    select 1
    from public.community_profiles as profile
    where profile.user_id = (select auth.uid())
  )
  and (
    group_id is null
    or exists (
      select 1
      from public.community_group_memberships as membership
      where membership.group_id = community_posts.group_id
        and membership.user_id = (select auth.uid())
    )
  )
);

drop policy if exists "Users can update their own posts" on public.community_posts;
create policy "Users can update their own posts"
on public.community_posts for update
to authenticated
using ((select auth.uid()) = author_id)
with check ((select auth.uid()) = author_id);

drop policy if exists "Users can delete their own posts" on public.community_posts;
create policy "Users can delete their own posts"
on public.community_posts for delete
to authenticated
using ((select auth.uid()) = author_id);

drop policy if exists "Authenticated users can view visible comments" on public.community_comments;
create policy "Authenticated users can view visible comments"
on public.community_comments for select
to authenticated
using (public.can_view_community_user(author_id));

drop policy if exists "Users can create their own comments" on public.community_comments;
create policy "Users can create their own comments"
on public.community_comments for insert
to authenticated
with check (
  (select auth.uid()) = author_id
  and exists (
    select 1
    from public.community_profiles as profile
    where profile.user_id = (select auth.uid())
  )
  and exists (
    select 1
    from public.community_posts as post
    where post.id = post_id
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

drop policy if exists "Users can update their own comments" on public.community_comments;
create policy "Users can update their own comments"
on public.community_comments for update
to authenticated
using ((select auth.uid()) = author_id)
with check ((select auth.uid()) = author_id);

drop policy if exists "Users can delete their own comments" on public.community_comments;
create policy "Users can delete their own comments"
on public.community_comments for delete
to authenticated
using ((select auth.uid()) = author_id);

drop policy if exists "Authenticated users can view visible events" on public.community_events;
create policy "Authenticated users can view visible events"
on public.community_events for select
to authenticated
using (public.can_view_community_user(host_id));

drop policy if exists "Users can create their own events" on public.community_events;
create policy "Users can create their own events"
on public.community_events for insert
to authenticated
with check (
  (select auth.uid()) = host_id
  and exists (
    select 1
    from public.community_profiles as profile
    where profile.user_id = (select auth.uid())
  )
  and (
    group_id is null
    or exists (
      select 1
      from public.community_group_memberships as membership
      where membership.group_id = community_events.group_id
        and membership.user_id = (select auth.uid())
    )
  )
);

drop policy if exists "Users can update their own events" on public.community_events;
create policy "Users can update their own events"
on public.community_events for update
to authenticated
using ((select auth.uid()) = host_id)
with check ((select auth.uid()) = host_id);

drop policy if exists "Users can delete their own events" on public.community_events;
create policy "Users can delete their own events"
on public.community_events for delete
to authenticated
using ((select auth.uid()) = host_id);

drop policy if exists "Users can view their own event RSVPs" on public.community_event_rsvps;
create policy "Users can view their own event RSVPs"
on public.community_event_rsvps for select
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "Users can create their own event RSVP" on public.community_event_rsvps;
create policy "Users can create their own event RSVP"
on public.community_event_rsvps for insert
to authenticated
with check (
  (select auth.uid()) = user_id
  and exists (
    select 1
    from public.community_profiles as profile
    where profile.user_id = (select auth.uid())
  )
);

drop policy if exists "Users can update their own event RSVP" on public.community_event_rsvps;
create policy "Users can update their own event RSVP"
on public.community_event_rsvps for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

drop policy if exists "Users can delete their own event RSVP" on public.community_event_rsvps;
create policy "Users can delete their own event RSVP"
on public.community_event_rsvps for delete
to authenticated
using ((select auth.uid()) = user_id);

-- Reports are deliberately write-only for ordinary users. Review and moderation
-- must happen through a server-side, audited workflow.
drop policy if exists "Users can submit their own community reports" on public.community_reports;
create policy "Users can submit their own community reports"
on public.community_reports for insert
to authenticated
with check ((select auth.uid()) = reporter_id);

-- Existing private setup profiles are also user-deletable.
drop policy if exists "Users can delete their own account profile" on public.user_account_profiles;
create policy "Users can delete their own account profile"
on public.user_account_profiles for delete
to authenticated
using ((select auth.uid()) = user_id);

-- Initial curated groups. They have no creator because they are product-owned.
insert into public.community_groups (name, slug, description, scope, city_or_region)
values
  ('Oslo Newcomers', 'oslo-newcomers', 'Practical conversations for people getting settled in Oslo.', 'city', 'Oslo'),
  ('Bergen Newcomers', 'bergen-newcomers', 'A welcoming space for people arriving in Bergen.', 'city', 'Bergen'),
  ('Stavanger Newcomers', 'stavanger-newcomers', 'Local questions, connections, and everyday Stavanger tips.', 'city', 'Stavanger'),
  ('Trondheim Newcomers', 'trondheim-newcomers', 'Meet people and share practical Trondheim experiences.', 'city', 'Trondheim'),
  ('Tromso Newcomers', 'tromso-newcomers', 'Community support and local discoveries in Tromso.', 'city', 'Tromso'),
  ('Language Practice', 'language-practice', 'Find language practice opportunities and respectful learning partners.', 'interest', null),
  ('Families in Norway', 'families-in-norway', 'Share everyday experiences for families settling into Norway.', 'interest', null),
  ('Visitors to Norway', 'visitors-to-norway', 'Practical, respectful travel conversations for Norway visitors.', 'interest', null)
on conflict (slug) do nothing;
