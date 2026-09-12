-- Repair deployments that applied the profile-media RPC while the default
-- function ACL still exposed EXECUTE to anon. Keep the RPC authenticated-only.

revoke all on function public.swap_own_community_profile_media(text, text) from public;
revoke all on function public.swap_own_community_profile_media(text, text) from anon;
grant execute on function public.swap_own_community_profile_media(text, text) to authenticated;
