-- Inbox controls are private to the authenticated member. Removing a
-- conversation hides only its summary and never deletes messages needed for
-- an existing safety report or the documented retention process.
--
-- This table was originally introduced by the conversation-preferences
-- migration. Create it here as well so a database that has the direct-message
-- foundation but not that earlier migration can safely adopt inbox controls.
create table if not exists public.community_conversation_preferences (
  conversation_id uuid not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  is_muted boolean not null default false,
  is_restricted boolean not null default false,
  background_style text not null default 'plain' check (background_style in ('plain', 'dots', 'grid')),
  bubble_color text not null default 'teal' check (bubble_color in ('teal', 'blue', 'purple', 'neutral')),
  updated_at timestamptz not null default now(),
  primary key (conversation_id, user_id),
  foreign key (conversation_id, user_id)
    references public.community_conversation_members(conversation_id, user_id)
    on delete cascade
);

alter table public.community_conversation_preferences enable row level security;

drop policy if exists "Members read their own conversation preferences"
  on public.community_conversation_preferences;
create policy "Members read their own conversation preferences"
on public.community_conversation_preferences for select to authenticated
using (
  user_id = (select auth.uid())
  and public.can_access_community_conversation(conversation_id)
);

revoke all on public.community_conversation_preferences from anon, authenticated;
grant select on public.community_conversation_preferences to authenticated;

alter table public.community_conversation_preferences
  add column if not exists is_pinned boolean not null default false,
  add column if not exists is_hidden boolean not null default false;

create index if not exists community_conversation_preferences_inbox_idx
  on public.community_conversation_preferences (user_id, is_hidden, is_pinned desc, updated_at desc);

create or replace function public.update_community_conversation_inbox_preferences(
  target_conversation_id uuid,
  muted boolean,
  pinned boolean,
  hidden boolean,
  restricted boolean,
  background text,
  bubble text
) returns void language plpgsql security definer set search_path = '' as $$
begin
  if (select auth.uid()) is null
     or not public.can_access_community_conversation(target_conversation_id) then
    raise exception 'conversation unavailable';
  end if;
  if muted is null or pinned is null or hidden is null or restricted is null
     or background is null or bubble is null
     or background not in ('plain', 'dots', 'grid')
     or bubble not in ('teal', 'blue', 'purple', 'neutral') then
    raise exception 'invalid conversation preference';
  end if;

  insert into public.community_conversation_preferences (
    conversation_id, user_id, is_muted, is_pinned, is_hidden,
    is_restricted, background_style, bubble_color
  ) values (
    target_conversation_id, (select auth.uid()), muted, pinned, hidden,
    restricted, background, bubble
  ) on conflict (conversation_id, user_id) do update set
    is_muted = excluded.is_muted,
    is_pinned = excluded.is_pinned,
    is_hidden = excluded.is_hidden,
    is_restricted = excluded.is_restricted,
    background_style = excluded.background_style,
    bubble_color = excluded.bubble_color,
    updated_at = now();
end;
$$;

revoke all on function public.update_community_conversation_inbox_preferences(uuid, boolean, boolean, boolean, boolean, text, text) from public;
grant execute on function public.update_community_conversation_inbox_preferences(uuid, boolean, boolean, boolean, boolean, text, text) to authenticated;

-- The conversation itself stays intact; a hidden row is simply excluded from
-- this member's inbox at the database boundary.
create or replace function public.list_community_direct_conversations()
returns table (
  conversation_id uuid,
  status text,
  requested_by_id uuid,
  created_at timestamptz,
  updated_at timestamptz,
  other_user_id uuid,
  display_name text,
  username text,
  avatar_path text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    conversation.id,
    conversation.status,
    conversation.requested_by_id,
    conversation.created_at,
    conversation.updated_at,
    profile.user_id,
    profile.display_name,
    profile.username,
    profile.avatar_path
  from public.community_conversations as conversation
  join public.community_conversation_members as member
    on member.conversation_id = conversation.id
  join public.community_profiles as profile
    on profile.user_id = case
      when conversation.participant_one_id = (select auth.uid()) then conversation.participant_two_id
      else conversation.participant_one_id
    end
  left join public.community_conversation_preferences as preference
    on preference.conversation_id = conversation.id
   and preference.user_id = (select auth.uid())
  where member.user_id = (select auth.uid())
    and member.status in ('pending', 'active')
    and conversation.status in ('pending', 'active')
    and not coalesce(preference.is_hidden, false)
    and public.can_view_community_user(profile.user_id)
  order by coalesce(preference.is_pinned, false) desc, conversation.updated_at desc;
$$;

revoke all on function public.list_community_direct_conversations() from public;
grant execute on function public.list_community_direct_conversations() to authenticated;
