-- Reports remain write-only for ordinary members. Validate that a report
-- points to content the reporter can currently access, rather than accepting
-- arbitrary UUIDs from an untrusted client.

alter table public.community_reports
  drop constraint if exists community_reports_target_type_check;

alter table public.community_reports
  add constraint community_reports_target_type_check
  check (target_type in ('profile', 'post', 'comment', 'event', 'group'));

drop policy if exists "Users can submit their own community reports" on public.community_reports;
create policy "Users can submit their own community reports"
on public.community_reports for insert
to authenticated
with check (
  (select auth.uid()) = reporter_id
  and (
    (target_type = 'profile' and exists (
      select 1 from public.community_profiles as profile where profile.user_id = target_id
    ))
    or (target_type = 'post' and exists (
      select 1 from public.community_posts as post where post.id = target_id
    ))
    or (target_type = 'comment' and exists (
      select 1 from public.community_comments as comment where comment.id = target_id
    ))
    or (target_type = 'event' and exists (
      select 1 from public.community_events as event where event.id = target_id
    ))
    or (target_type = 'group' and exists (
      select 1 from public.community_groups as community_group where community_group.id = target_id
    ))
  )
);
