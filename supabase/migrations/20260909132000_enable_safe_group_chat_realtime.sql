-- Realtime carries only an insert signal. The iOS client reloads messages
-- through the authorized RPC before rendering any user-generated content.

drop policy if exists "Group members can receive group chat change signals" on public.community_group_chat_messages;
create policy "Group members can receive group chat change signals"
on public.community_group_chat_messages for select to authenticated
using (
  public.can_access_community_group_chat(group_id)
  and moderation_state = 'active'
  and deleted_at is null
  and public.can_view_community_user(sender_id)
  and not exists (
    select 1 from public.community_group_chat_message_member_hides hidden
    where hidden.message_id = community_group_chat_messages.id
      and hidden.user_id = (select auth.uid())
  )
);

grant select on public.community_group_chat_messages to authenticated;

do $$
begin
  alter publication supabase_realtime add table public.community_group_chat_messages;
exception when duplicate_object then null;
end $$;
