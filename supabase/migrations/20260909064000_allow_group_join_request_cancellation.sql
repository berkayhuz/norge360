-- A pending request is user-controlled data. A reviewed decision remains retained
-- for the moderation audit; only the requester can withdraw a pending request.
drop policy if exists "Users can cancel their own pending group join requests" on public.community_group_join_requests;
create policy "Users can cancel their own pending group join requests"
on public.community_group_join_requests for delete to authenticated
using (user_id = (select auth.uid()) and status = 'pending');
