-- Client write-boundary regression test. Run against a disposable migrated
-- database as its owner. Everything rolls back.
begin;

do $$
begin
  if has_table_privilege('anon', 'public.community_posts', 'INSERT')
     or has_table_privilege('anon', 'public.community_posts', 'UPDATE')
     or has_table_privilege('anon', 'public.community_posts', 'DELETE')
     or has_table_privilege('anon', 'public.community_comments', 'INSERT')
     or has_table_privilege('anon', 'public.community_comments', 'UPDATE')
     or has_table_privilege('anon', 'public.community_comments', 'DELETE')
     or has_table_privilege('anon', 'public.community_notifications', 'INSERT')
     or has_table_privilege('anon', 'public.community_notifications', 'UPDATE')
     or has_table_privilege('anon', 'public.community_notifications', 'DELETE') then
    raise exception 'anonymous clients retain community DML privileges';
  end if;

  if has_table_privilege('authenticated', 'public.community_event_rsvps', 'INSERT')
     or has_table_privilege('authenticated', 'public.community_event_rsvps', 'UPDATE')
     or has_table_privilege('authenticated', 'public.community_event_rsvps', 'DELETE') then
    raise exception 'authenticated clients can mutate event RSVPs outside the RPC';
  end if;

  if has_column_privilege('authenticated', 'public.community_reports', 'review_status', 'INSERT')
     or has_column_privilege('authenticated', 'public.community_reports', 'reviewed_by', 'INSERT')
     or has_column_privilege('authenticated', 'public.community_reports', 'resolution_action', 'INSERT')
     or has_column_privilege('authenticated', 'public.community_reports', 'resolution_note', 'INSERT') then
    raise exception 'authenticated clients can write report moderation state';
  end if;

  if not has_column_privilege('authenticated', 'public.community_reports', 'reporter_id', 'INSERT')
     or not has_column_privilege('authenticated', 'public.community_reports', 'target_type', 'INSERT')
     or not has_column_privilege('authenticated', 'public.community_reports', 'target_id', 'INSERT')
     or not has_column_privilege('authenticated', 'public.community_reports', 'reason', 'INSERT')
     or not has_column_privilege('authenticated', 'public.community_reports', 'details', 'INSERT') then
    raise exception 'authenticated clients lost the supported report submission columns';
  end if;

  if has_column_privilege('authenticated', 'public.community_notifications', 'actor_id', 'UPDATE')
     or has_column_privilege('authenticated', 'public.community_notifications', 'recipient_id', 'UPDATE')
     or has_column_privilege('authenticated', 'public.community_notifications', 'type', 'UPDATE')
     or has_column_privilege('authenticated', 'public.community_notifications', 'event_key', 'UPDATE')
     or not has_column_privilege('authenticated', 'public.community_notifications', 'read_at', 'UPDATE') then
    raise exception 'notification updates are not limited to read_at';
  end if;

  if has_column_privilege('authenticated', 'public.community_posts', 'author_id', 'UPDATE')
     or has_column_privilege('authenticated', 'public.community_posts', 'group_id', 'UPDATE')
     or has_column_privilege('authenticated', 'public.community_posts', 'moderation_state', 'UPDATE')
     or not has_column_privilege('authenticated', 'public.community_posts', 'body', 'UPDATE') then
    raise exception 'post updates expose server-controlled columns';
  end if;

  if has_column_privilege('authenticated', 'public.community_comments', 'author_id', 'UPDATE')
     or has_column_privilege('authenticated', 'public.community_comments', 'post_id', 'UPDATE')
     or has_column_privilege('authenticated', 'public.community_comments', 'moderation_state', 'UPDATE')
     or not has_column_privilege('authenticated', 'public.community_comments', 'body', 'UPDATE') then
    raise exception 'comment updates expose server-controlled columns';
  end if;

  if has_column_privilege('authenticated', 'public.community_group_memberships', 'role', 'UPDATE')
     or has_column_privilege('authenticated', 'public.community_group_memberships', 'user_id', 'UPDATE') then
    raise exception 'group membership identity or role remains client-updatable';
  end if;
end;
$$;

rollback;
