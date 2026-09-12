-- Keep public profile projections read-only for the client roles. The view
-- definitions own the public/private column boundary; table privileges should
-- expose only the read operation required by authenticated profile screens.
revoke all on public.community_public_profiles from public, anon, authenticated;
grant select on public.community_public_profiles to authenticated;

revoke all on public.community_member_profile_stats from public, anon, authenticated;
grant select on public.community_member_profile_stats to authenticated;
