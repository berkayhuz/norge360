-- The inbox may show the latest message as a local preview. It remains inside
-- the member-authorized security-definer summary and excludes hidden/deleted
-- messages so the preview follows the same privacy boundary as the inbox.
drop function if exists public.list_community_direct_conversations();

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
  avatar_path text,
  last_message text
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
    profile.avatar_path,
    latest_message.body
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
  left join lateral (
    select message.body
    from public.community_messages as message
    where message.conversation_id = conversation.id
      and message.deleted_at is null
      and not exists (
        select 1
        from public.community_message_member_hides as hidden
        where hidden.message_id = message.id
          and hidden.user_id = (select auth.uid())
      )
    order by message.created_at desc
    limit 1
  ) as latest_message on true
  where member.user_id = (select auth.uid())
    and member.status in ('pending', 'active')
    and conversation.status in ('pending', 'active')
    and not coalesce(preference.is_hidden, false)
    and public.can_view_community_user(profile.user_id)
  order by coalesce(preference.is_pinned, false) desc, conversation.updated_at desc;
$$;

revoke all on function public.list_community_direct_conversations() from public;
grant execute on function public.list_community_direct_conversations() to authenticated;
