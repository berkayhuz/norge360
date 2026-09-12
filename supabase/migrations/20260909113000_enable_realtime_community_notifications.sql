-- Enables only the notification table for the iOS foreground toast stream.
-- The existing RLS select policy remains the authorization boundary.
do $$
begin
  alter publication supabase_realtime add table public.community_notifications;
exception
  when duplicate_object then null;
end $$;
