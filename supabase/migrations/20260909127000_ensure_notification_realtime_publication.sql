-- Foreground notification banners rely on an RLS-authorized Realtime INSERT
-- subscription. Keep this idempotent so existing projects that predate the
-- notification migration are repaired safely.
do $$
begin
  alter publication supabase_realtime add table public.community_notifications;
exception
  when duplicate_object then null;
end $$;
