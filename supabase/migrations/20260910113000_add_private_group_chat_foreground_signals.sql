-- The iOS foreground banner receives only a recipient-authorized signal. It
-- has a group pointer for safe in-app routing, but no sender, text, media URL,
-- or other message content. APNs remains completely generic.

drop policy if exists "Recipients receive current group chat signals"
  on public.community_group_chat_signals;
create policy "Recipients receive current group chat signals"
on public.community_group_chat_signals for select to authenticated
using (
  recipient_id = (select auth.uid())
  and expires_at > now()
  and public.can_access_community_group_chat(group_id)
);
grant select on public.community_group_chat_signals to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.community_group_chat_signals;
  end if;
exception when duplicate_object then null;
end $$;
