-- Keep post-like mutations behind one server-authorized operation. The old
-- client INSERT path rejected visible posts from public groups when the member
-- had not joined that group yet, even though the post itself was readable.
drop policy if exists "Users can like visible posts" on public.community_post_likes;
revoke insert, update, delete on public.community_post_likes from anon, authenticated;
grant select on public.community_post_likes to authenticated;

create or replace function public.toggle_community_post_like(target_post_id uuid)
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

  select * into target_post
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

  insert into public.community_post_likes (post_id, user_id)
  values (target_post_id, actor_id)
  on conflict (post_id, user_id) do nothing;
  if found then
    return true;
  end if;

  delete from public.community_post_likes
  where post_id = target_post_id and user_id = actor_id;
  return false;
end;
$$;

revoke all on function public.toggle_community_post_like(uuid) from public;
grant execute on function public.toggle_community_post_like(uuid) to authenticated;

-- Recreate the direct inbox summary with the complete current return shape.
-- This remains a security-definer read: only rows belonging to auth.uid() are
-- returned, while private participant/profile tables stay out of the client.
drop function if exists public.list_community_direct_conversations();

create function public.list_community_direct_conversations()
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
    (
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
    ) as last_message
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
