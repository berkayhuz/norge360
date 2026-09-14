-- Keep the data-subject export boundary and moderation retention policy
-- server-owned. The iOS client never receives service-role access.

create or replace function public.export_community_account_data(account_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  account_record jsonb;
begin
  if coalesce(current_setting('request.jwt.claim.role', true), '') <> 'service_role' then
    raise exception 'service role required';
  end if;
  if account_user_id is null then
    raise exception 'target user required';
  end if;

  -- Keep a pathological export from monopolizing a database connection. The
  -- Worker returns a retryable/unavailable response rather than allowing an
  -- unbounded aggregation to run indefinitely.
  perform set_config('statement_timeout', '15000', true);

  select jsonb_build_object(
    'id', id,
    'email', email,
    'created_at', created_at,
    'updated_at', updated_at,
    'last_sign_in_at', last_sign_in_at
  )
  into account_record
  from auth.users
  where id = account_user_id;

  if account_record is null then
    raise exception 'target user not found';
  end if;

  return jsonb_build_object(
    'schema_version', 1,
    'generated_at', now(),
    'account', account_record,
    'profile', coalesce((
      select to_jsonb(profile)
      from public.community_profiles as profile
      where profile.user_id = account_user_id
    ), '{}'::jsonb),
    'account_profile', coalesce((
      select to_jsonb(profile)
      from public.user_account_profiles as profile
      where profile.user_id = account_user_id
    ), '{}'::jsonb),
    'relocation_plan', coalesce((
      select to_jsonb(plan)
      from public.user_relocation_plans as plan
      where plan.user_id = account_user_id
    ), '{}'::jsonb),
    'posts', coalesce((
      select jsonb_agg(to_jsonb(export_row) order by export_row.created_at)
      from (
        select post.*
        from public.community_posts as post
        where post.author_id = account_user_id
      ) as export_row
    ), '[]'::jsonb),
    'post_media', coalesce((
      select jsonb_agg(to_jsonb(export_row) order by export_row.created_at)
      from (
        select media.*
        from public.community_post_media as media
        join public.community_posts as post on post.id = media.post_id
        where post.author_id = account_user_id
      ) as export_row
    ), '[]'::jsonb),
    'post_edit_history', coalesce((
      select jsonb_agg(to_jsonb(export_row) order by export_row.edited_at)
      from (
        select history.*
        from public.community_post_edit_history as history
        join public.community_posts as post on post.id = history.post_id
        where post.author_id = account_user_id
      ) as export_row
    ), '[]'::jsonb),
    'post_hashtags', coalesce((
      select jsonb_agg(to_jsonb(export_row) order by export_row.post_id, export_row.tag)
      from (
        select hashtags.*
        from public.community_post_hashtags as hashtags
        join public.community_posts as post on post.id = hashtags.post_id
        where post.author_id = account_user_id
      ) as export_row
    ), '[]'::jsonb),
    'comments', coalesce((
      select jsonb_agg(to_jsonb(export_row) order by export_row.created_at)
      from (
        select comment.*
        from public.community_comments as comment
        where comment.author_id = account_user_id
      ) as export_row
    ), '[]'::jsonb),
    'comment_hashtags', coalesce((
      select jsonb_agg(to_jsonb(export_row) order by export_row.comment_id, export_row.tag)
      from (
        select hashtags.*
        from public.community_comment_hashtags as hashtags
        join public.community_comments as comment on comment.id = hashtags.comment_id
        where comment.author_id = account_user_id
      ) as export_row
    ), '[]'::jsonb),
    'events', coalesce((
      select jsonb_agg(to_jsonb(export_row) order by export_row.created_at)
      from (
        select event.*
        from public.community_events as event
        where event.host_id = account_user_id
      ) as export_row
    ), '[]'::jsonb),
    'event_rsvps', coalesce((
      select jsonb_agg(to_jsonb(export_row) order by export_row.created_at)
      from (
        select rsvp.*
        from public.community_event_rsvps as rsvp
        where rsvp.user_id = account_user_id
      ) as export_row
    ), '[]'::jsonb),
    'event_likes', coalesce((
      select jsonb_agg(to_jsonb(export_row) order by export_row.created_at)
      from (
        select liked.*
        from public.community_event_likes as liked
        where liked.user_id = account_user_id
      ) as export_row
    ), '[]'::jsonb),
    'post_likes', coalesce((
      select jsonb_agg(to_jsonb(export_row) order by export_row.created_at)
      from (
        select liked.*
        from public.community_post_likes as liked
        where liked.user_id = account_user_id
      ) as export_row
    ), '[]'::jsonb),
    'follows', coalesce((
      select jsonb_agg(to_jsonb(export_row) order by export_row.created_at)
      from (
        select follow.*
        from public.community_follows as follow
        where follow.follower_id = account_user_id or follow.following_id = account_user_id
      ) as export_row
    ), '[]'::jsonb),
    'blocks', coalesce((
      select jsonb_agg(to_jsonb(export_row) order by export_row.created_at)
      from (
        select block.*
        from public.user_blocks as block
        where block.blocker_id = account_user_id
      ) as export_row
    ), '[]'::jsonb),
    'group_memberships', coalesce((
      select jsonb_agg(to_jsonb(export_row) order by export_row.created_at)
      from (
        select membership.*
        from public.community_group_memberships as membership
        where membership.user_id = account_user_id
      ) as export_row
    ), '[]'::jsonb),
    'group_join_requests', coalesce((
      select jsonb_agg(to_jsonb(export_row) order by export_row.requested_at)
      from (
        select request.*
        from public.community_group_join_requests as request
        where request.user_id = account_user_id
      ) as export_row
    ), '[]'::jsonb),
    'group_invitations', coalesce((
      select jsonb_agg(to_jsonb(export_row) order by export_row.created_at)
      from (
        select invitation.*
        from public.community_group_invitations as invitation
        where invitation.target_user_id = account_user_id or invitation.invited_by = account_user_id
      ) as export_row
    ), '[]'::jsonb),
    'event_invitations', coalesce((
      select jsonb_agg(to_jsonb(export_row) order by export_row.created_at)
      from (
        select invitation.*
        from public.community_event_invitations as invitation
        where invitation.target_user_id = account_user_id or invitation.invited_by = account_user_id
      ) as export_row
    ), '[]'::jsonb),
    'notifications', coalesce((
      select jsonb_agg(to_jsonb(export_row) order by export_row.created_at)
      from (
        select notification.*
        from public.community_notifications as notification
        where notification.recipient_id = account_user_id
      ) as export_row
    ), '[]'::jsonb),
    'conversations', coalesce((
      select jsonb_agg(to_jsonb(export_row) order by export_row.created_at)
      from (
        select conversation.*
        from public.community_conversations as conversation
        where conversation.participant_one_id = account_user_id
           or conversation.participant_two_id = account_user_id
      ) as export_row
    ), '[]'::jsonb),
    'conversation_memberships', coalesce((
      select jsonb_agg(to_jsonb(export_row) order by export_row.created_at)
      from (
        select member.*
        from public.community_conversation_members as member
        where member.user_id = account_user_id
      ) as export_row
    ), '[]'::jsonb),
    'messages_authored', coalesce((
      select jsonb_agg(to_jsonb(export_row) order by export_row.created_at)
      from (
        select message.*
        from public.community_messages as message
        where message.sender_id = account_user_id
      ) as export_row
    ), '[]'::jsonb),
    'message_preferences', coalesce((
      select jsonb_agg(to_jsonb(export_row) order by export_row.updated_at)
      from (
        select preference.*
        from public.community_message_preferences as preference
        where preference.user_id = account_user_id
      ) as export_row
    ), '[]'::jsonb),
    'message_hides', coalesce((
      select jsonb_agg(to_jsonb(export_row) order by export_row.hidden_at)
      from (
        select hidden.*
        from public.community_message_member_hides as hidden
        where hidden.user_id = account_user_id
      ) as export_row
    ), '[]'::jsonb),
    'conversation_preferences', coalesce((
      select jsonb_agg(to_jsonb(export_row) order by export_row.updated_at)
      from (
        select preference.*
        from public.community_conversation_preferences as preference
        where preference.user_id = account_user_id
      ) as export_row
    ), '[]'::jsonb),
    'group_chat_messages_authored', coalesce((
      select jsonb_agg(to_jsonb(export_row) order by export_row.created_at)
      from (
        select message.*
        from public.community_group_chat_messages as message
        where message.sender_id = account_user_id
      ) as export_row
    ), '[]'::jsonb),
    'group_chat_message_hides', coalesce((
      select jsonb_agg(to_jsonb(export_row) order by export_row.hidden_at)
      from (
        select hidden.*
        from public.community_group_chat_message_member_hides as hidden
        where hidden.user_id = account_user_id
      ) as export_row
    ), '[]'::jsonb),
    'group_chat_reads', coalesce((
      select jsonb_agg(to_jsonb(export_row) order by export_row.updated_at)
      from (
        select reads.*
        from public.community_group_chat_member_reads as reads
        where reads.user_id = account_user_id
      ) as export_row
    ), '[]'::jsonb),
    'group_chat_preferences', coalesce((
      select jsonb_agg(to_jsonb(export_row) order by export_row.updated_at)
      from (
        select preference.*
        from public.community_group_chat_preferences as preference
        where preference.user_id = account_user_id
      ) as export_row
    ), '[]'::jsonb),
    'direct_media_metadata', coalesce((
      select jsonb_agg(to_jsonb(export_row) order by export_row.created_at)
      from (
        select attachment.id, attachment.conversation_id, attachment.message_id,
          attachment.uploader_id, attachment.mime_type, attachment.byte_size,
          attachment.storage_provider, attachment.status, attachment.scan_provider,
          attachment.scan_status, attachment.scan_summary, attachment.scanned_at,
          attachment.reviewed_at, attachment.deleted_at, attachment.created_at
        from public.community_direct_message_attachments as attachment
        where attachment.uploader_id = account_user_id
      ) as export_row
    ), '[]'::jsonb),
    'group_chat_media_metadata', coalesce((
      select jsonb_agg(to_jsonb(export_row) order by export_row.created_at)
      from (
        select attachment.id, attachment.group_id, attachment.message_id,
          attachment.uploader_id, attachment.mime_type, attachment.byte_size,
          attachment.status, attachment.expires_at, attachment.created_at,
          attachment.reviewed_at, attachment.deleted_at
        from public.community_group_chat_attachments as attachment
        where attachment.uploader_id = account_user_id
      ) as export_row
    ), '[]'::jsonb),
    'reports_submitted', coalesce((
      select jsonb_agg(to_jsonb(export_row) order by export_row.created_at)
      from (
        select report.*
        from public.community_reports as report
        where report.reporter_id = account_user_id
      ) as export_row
    ), '[]'::jsonb),
    'group_moderation_activity', coalesce((
      select jsonb_agg(to_jsonb(export_row) order by export_row.created_at)
      from (
        select audit.*
        from public.community_group_moderation_audit as audit
        where audit.actor_id = account_user_id or audit.target_user_id = account_user_id
      ) as export_row
    ), '[]'::jsonb),
    'push_devices', coalesce((
      select jsonb_agg(to_jsonb(export_row) order by export_row.created_at)
      from (
        select device.id, device.user_id, device.environment, device.is_active,
          device.last_registered_at, device.last_delivery_at,
          device.deactivated_at, device.created_at, device.updated_at
        from public.community_push_devices as device
        where device.user_id = account_user_id
      ) as export_row
    ), '[]'::jsonb),
    'push_preferences', coalesce((
      select jsonb_agg(to_jsonb(export_row) order by export_row.updated_at)
      from (
        select preference.*
        from public.community_push_preferences as preference
        where preference.user_id = account_user_id
      ) as export_row
    ), '[]'::jsonb),
    'follow_visibility', coalesce((
      select to_jsonb(preference)
      from public.community_follow_visibility as preference
      where preference.user_id = account_user_id
    ), '{}'::jsonb)
  );
end;
$$;

revoke all on function public.export_community_account_data(uuid) from public, anon, authenticated;
grant execute on function public.export_community_account_data(uuid) to service_role;

create or replace function public.purge_community_moderation_retention(target_batch_size integer default 500)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  removed bigint := 0;
  deleted_count bigint;
begin
  if coalesce(current_setting('request.jwt.claim.role', true), '') <> 'service_role' then
    raise exception 'service role required';
  end if;
  if target_batch_size is null or target_batch_size < 1 or target_batch_size > 5000 then
    raise exception 'invalid retention batch size';
  end if;

  -- Closed moderation cases remain available for twelve months after review.
  -- Open cases are retained until a moderator closes them. Delete dependent
  -- audit rows first because action audits intentionally restrict report delete.
  with eligible_reports as (
    select report.id
    from public.community_reports as report
    where report.review_status in ('resolved', 'dismissed')
      and report.reviewed_at <= now() - interval '12 months'
    order by report.reviewed_at asc, report.id
    limit target_batch_size
  )
  delete from public.community_moderation_action_audit as audit
  using eligible_reports
  where audit.report_id = eligible_reports.id;
  get diagnostics deleted_count = row_count;
  removed := removed + deleted_count;

  with eligible_reports as (
    select report.id
    from public.community_reports as report
    where report.review_status in ('resolved', 'dismissed')
      and report.reviewed_at <= now() - interval '12 months'
    order by report.reviewed_at asc, report.id
    limit target_batch_size
  )
  delete from public.community_moderation_review_audit as audit
  using eligible_reports
  where audit.report_id = eligible_reports.id;
  get diagnostics deleted_count = row_count;
  removed := removed + deleted_count;

  with eligible_reports as (
    select report.id
    from public.community_reports as report
    where report.review_status in ('resolved', 'dismissed')
      and report.reviewed_at <= now() - interval '12 months'
    order by report.reviewed_at asc, report.id
    limit target_batch_size
  )
  delete from public.community_reports as report
  using eligible_reports
  where report.id = eligible_reports.id;
  get diagnostics deleted_count = row_count;
  removed := removed + deleted_count;

  -- Group moderation history is independent from the current ban state. An
  -- active ban is deliberately not purged because it remains an authorization
  -- input until the ban is lifted.
  with expired_group_audits as (
    select audit.id
    from public.community_group_moderation_audit as audit
    where audit.created_at <= now() - interval '12 months'
    order by audit.created_at asc, audit.id
    limit target_batch_size
  )
  delete from public.community_group_moderation_audit as audit
  using expired_group_audits
  where audit.id = expired_group_audits.id;
  get diagnostics deleted_count = row_count;
  removed := removed + deleted_count;

  return removed;
end;
$$;

revoke all on function public.purge_community_moderation_retention(integer) from public, anon, authenticated;
grant execute on function public.purge_community_moderation_retention(integer) to service_role;

comment on function public.export_community_account_data(uuid) is
  'Returns an authenticated member export without APNs tokens, storage paths, provider asset IDs, or service credentials.';
comment on function public.purge_community_moderation_retention(integer) is
  'Deletes closed moderation reports and dependent audits after twelve months; open reports and active group bans are retained.';
