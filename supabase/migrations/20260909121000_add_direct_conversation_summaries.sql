-- A security-definer summary prevents private-profile RLS from hiding the
-- other participant's deliberately minimal identity inside an authorized DM.

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
  where member.user_id = (select auth.uid())
    and member.status in ('pending', 'active')
    and conversation.status in ('pending', 'active')
    and public.can_view_community_user(profile.user_id)
  order by conversation.updated_at desc;
$$;

revoke all on function public.list_community_direct_conversations() from public;
grant execute on function public.list_community_direct_conversations() to authenticated;
