-- Replace the all-at-once account export path with bounded server-owned pages.
-- The existing export RPC remains available for compatibility, while the
-- Worker uses these two RPCs for new downloads.

create or replace function public.export_community_account_metadata(account_user_id uuid)
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

  perform set_config('statement_timeout', '5000', true);

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
    'follow_visibility', coalesce((
      select to_jsonb(preference)
      from public.community_follow_visibility as preference
      where preference.user_id = account_user_id
    ), '{}'::jsonb)
  );
end;
$$;

revoke all on function public.export_community_account_metadata(uuid) from public, anon, authenticated;
grant execute on function public.export_community_account_metadata(uuid) to service_role;

create or replace function public.export_community_account_section(
  account_user_id uuid,
  target_section text,
  page_number integer default 0,
  page_size integer default 100
)
returns table (rows jsonb, has_more boolean)
language plpgsql
security definer
set search_path = ''
as $$
declare
  query_text text;
  page_rows jsonb;
  page_offset integer;
begin
  if coalesce(current_setting('request.jwt.claim.role', true), '') <> 'service_role' then
    raise exception 'service role required';
  end if;
  if account_user_id is null
     or target_section is null
     or page_number is null
     or page_number not between 0 and 100000
     or page_size is null
     or page_size not between 1 and 250 then
    raise exception 'invalid account export page';
  end if;

  page_offset := page_number * page_size;
  query_text := case target_section
    when 'posts' then $sql$
      select coalesce(jsonb_agg(to_jsonb(export_row) order by export_row.created_at, export_row.id), '[]'::jsonb)
      from (
        select post.*
        from public.community_posts as post
        where post.author_id = $1
        order by post.created_at, post.id
        offset $2 limit $3
      ) as export_row
    $sql$
    when 'post_media' then $sql$
      select coalesce(jsonb_agg(to_jsonb(export_row) order by export_row.created_at, export_row.id), '[]'::jsonb)
      from (
        select media.*
        from public.community_post_media as media
        join public.community_posts as post on post.id = media.post_id
        where post.author_id = $1
        order by media.created_at, media.id
        offset $2 limit $3
      ) as export_row
    $sql$
    when 'post_edit_history' then $sql$
      select coalesce(jsonb_agg(to_jsonb(export_row) order by export_row.edited_at, export_row.post_id), '[]'::jsonb)
      from (
        select history.*
        from public.community_post_edit_history as history
        join public.community_posts as post on post.id = history.post_id
        where post.author_id = $1
        order by history.edited_at, history.post_id
        offset $2 limit $3
      ) as export_row
    $sql$
    when 'post_hashtags' then $sql$
      select coalesce(jsonb_agg(to_jsonb(export_row) order by export_row.post_id, export_row.tag), '[]'::jsonb)
      from (
        select hashtags.*
        from public.community_post_hashtags as hashtags
        join public.community_posts as post on post.id = hashtags.post_id
        where post.author_id = $1
        order by hashtags.post_id, hashtags.tag
        offset $2 limit $3
      ) as export_row
    $sql$
    when 'comments' then $sql$
      select coalesce(jsonb_agg(to_jsonb(export_row) order by export_row.created_at, export_row.id), '[]'::jsonb)
      from (
        select comment.*
        from public.community_comments as comment
        where comment.author_id = $1
        order by comment.created_at, comment.id
        offset $2 limit $3
      ) as export_row
    $sql$
    when 'comment_hashtags' then $sql$
      select coalesce(jsonb_agg(to_jsonb(export_row) order by export_row.comment_id, export_row.tag), '[]'::jsonb)
      from (
        select hashtags.*
        from public.community_comment_hashtags as hashtags
        join public.community_comments as comment on comment.id = hashtags.comment_id
        where comment.author_id = $1
        order by hashtags.comment_id, hashtags.tag
        offset $2 limit $3
      ) as export_row
    $sql$
    when 'events' then $sql$
      select coalesce(jsonb_agg(to_jsonb(export_row) order by export_row.created_at, export_row.id), '[]'::jsonb)
      from (
        select event.*
        from public.community_events as event
        where event.host_id = $1
        order by event.created_at, event.id
        offset $2 limit $3
      ) as export_row
    $sql$
    when 'event_rsvps' then $sql$
      select coalesce(jsonb_agg(to_jsonb(export_row) order by export_row.created_at, export_row.event_id, export_row.user_id), '[]'::jsonb)
      from (
        select rsvp.*
        from public.community_event_rsvps as rsvp
        where rsvp.user_id = $1
        order by rsvp.created_at, rsvp.event_id, rsvp.user_id
        offset $2 limit $3
      ) as export_row
    $sql$
    when 'event_likes' then $sql$
      select coalesce(jsonb_agg(to_jsonb(export_row) order by export_row.created_at, export_row.event_id, export_row.user_id), '[]'::jsonb)
      from (
        select liked.*
        from public.community_event_likes as liked
        where liked.user_id = $1
        order by liked.created_at, liked.event_id, liked.user_id
        offset $2 limit $3
      ) as export_row
    $sql$
    when 'post_likes' then $sql$
      select coalesce(jsonb_agg(to_jsonb(export_row) order by export_row.created_at, export_row.post_id, export_row.user_id), '[]'::jsonb)
      from (
        select liked.*
        from public.community_post_likes as liked
        where liked.user_id = $1
        order by liked.created_at, liked.post_id, liked.user_id
        offset $2 limit $3
      ) as export_row
    $sql$
    when 'follows' then $sql$
      select coalesce(jsonb_agg(to_jsonb(export_row) order by export_row.created_at, export_row.follower_id, export_row.following_id), '[]'::jsonb)
      from (
        select follow.*
        from public.community_follows as follow
        where follow.follower_id = $1 or follow.following_id = $1
        order by follow.created_at, follow.follower_id, follow.following_id
        offset $2 limit $3
      ) as export_row
    $sql$
    when 'blocks' then $sql$
      select coalesce(jsonb_agg(to_jsonb(export_row) order by export_row.created_at, export_row.blocker_id, export_row.blocked_user_id), '[]'::jsonb)
      from (
        select block.*
        from public.user_blocks as block
        where block.blocker_id = $1
        order by block.created_at, block.blocker_id, block.blocked_user_id
        offset $2 limit $3
      ) as export_row
    $sql$
    when 'group_memberships' then $sql$
      select coalesce(jsonb_agg(to_jsonb(export_row) order by export_row.created_at, export_row.group_id, export_row.user_id), '[]'::jsonb)
      from (
        select membership.*
        from public.community_group_memberships as membership
        where membership.user_id = $1
        order by membership.created_at, membership.group_id, membership.user_id
        offset $2 limit $3
      ) as export_row
    $sql$
    when 'group_join_requests' then $sql$
      select coalesce(jsonb_agg(to_jsonb(export_row) order by export_row.requested_at, export_row.id), '[]'::jsonb)
      from (
        select request.*
        from public.community_group_join_requests as request
        where request.user_id = $1
        order by request.requested_at, request.id
        offset $2 limit $3
      ) as export_row
    $sql$
    when 'group_invitations' then $sql$
      select coalesce(jsonb_agg(to_jsonb(export_row) order by export_row.created_at, export_row.id), '[]'::jsonb)
      from (
        select invitation.*
        from public.community_group_invitations as invitation
        where invitation.target_user_id = $1 or invitation.invited_by = $1
        order by invitation.created_at, invitation.id
        offset $2 limit $3
      ) as export_row
    $sql$
    when 'event_invitations' then $sql$
      select coalesce(jsonb_agg(to_jsonb(export_row) order by export_row.created_at, export_row.id), '[]'::jsonb)
      from (
        select invitation.*
        from public.community_event_invitations as invitation
        where invitation.target_user_id = $1 or invitation.invited_by = $1
        order by invitation.created_at, invitation.id
        offset $2 limit $3
      ) as export_row
    $sql$
    when 'notifications' then $sql$
      select coalesce(jsonb_agg(to_jsonb(export_row) order by export_row.created_at, export_row.id), '[]'::jsonb)
      from (
        select notification.*
        from public.community_notifications as notification
        where notification.recipient_id = $1
        order by notification.created_at, notification.id
        offset $2 limit $3
      ) as export_row
    $sql$
    when 'conversations' then $sql$
      select coalesce(jsonb_agg(to_jsonb(export_row) order by export_row.created_at, export_row.id), '[]'::jsonb)
      from (
        select conversation.*
        from public.community_conversations as conversation
        where conversation.participant_one_id = $1 or conversation.participant_two_id = $1
        order by conversation.created_at, conversation.id
        offset $2 limit $3
      ) as export_row
    $sql$
    when 'conversation_memberships' then $sql$
      select coalesce(jsonb_agg(to_jsonb(export_row) order by export_row.created_at, export_row.conversation_id, export_row.user_id), '[]'::jsonb)
      from (
        select member.*
        from public.community_conversation_members as member
        where member.user_id = $1
        order by member.created_at, member.conversation_id, member.user_id
        offset $2 limit $3
      ) as export_row
    $sql$
    when 'messages_authored' then $sql$
      select coalesce(jsonb_agg(to_jsonb(export_row) order by export_row.created_at, export_row.id), '[]'::jsonb)
      from (
        select message.*
        from public.community_messages as message
        where message.sender_id = $1
        order by message.created_at, message.id
        offset $2 limit $3
      ) as export_row
    $sql$
    when 'message_preferences' then $sql$
      select coalesce(jsonb_agg(to_jsonb(export_row) order by export_row.updated_at, export_row.user_id), '[]'::jsonb)
      from (
        select preference.*
        from public.community_message_preferences as preference
        where preference.user_id = $1
        order by preference.updated_at, preference.user_id
        offset $2 limit $3
      ) as export_row
    $sql$
    when 'message_hides' then $sql$
      select coalesce(jsonb_agg(to_jsonb(export_row) order by export_row.hidden_at, export_row.message_id, export_row.user_id), '[]'::jsonb)
      from (
        select hidden.*
        from public.community_message_member_hides as hidden
        where hidden.user_id = $1
        order by hidden.hidden_at, hidden.message_id, hidden.user_id
        offset $2 limit $3
      ) as export_row
    $sql$
    when 'conversation_preferences' then $sql$
      select coalesce(jsonb_agg(to_jsonb(export_row) order by export_row.updated_at, export_row.conversation_id, export_row.user_id), '[]'::jsonb)
      from (
        select preference.*
        from public.community_conversation_preferences as preference
        where preference.user_id = $1
        order by preference.updated_at, preference.conversation_id, preference.user_id
        offset $2 limit $3
      ) as export_row
    $sql$
    when 'group_chat_messages_authored' then $sql$
      select coalesce(jsonb_agg(to_jsonb(export_row) order by export_row.created_at, export_row.id), '[]'::jsonb)
      from (
        select message.*
        from public.community_group_chat_messages as message
        where message.sender_id = $1
        order by message.created_at, message.id
        offset $2 limit $3
      ) as export_row
    $sql$
    when 'group_chat_message_hides' then $sql$
      select coalesce(jsonb_agg(to_jsonb(export_row) order by export_row.hidden_at, export_row.message_id, export_row.user_id), '[]'::jsonb)
      from (
        select hidden.*
        from public.community_group_chat_message_member_hides as hidden
        where hidden.user_id = $1
        order by hidden.hidden_at, hidden.message_id, hidden.user_id
        offset $2 limit $3
      ) as export_row
    $sql$
    when 'group_chat_reads' then $sql$
      select coalesce(jsonb_agg(to_jsonb(export_row) order by export_row.updated_at, export_row.group_id, export_row.user_id), '[]'::jsonb)
      from (
        select reads.*
        from public.community_group_chat_member_reads as reads
        where reads.user_id = $1
        order by reads.updated_at, reads.group_id, reads.user_id
        offset $2 limit $3
      ) as export_row
    $sql$
    when 'group_chat_preferences' then $sql$
      select coalesce(jsonb_agg(to_jsonb(export_row) order by export_row.updated_at, export_row.group_id, export_row.user_id), '[]'::jsonb)
      from (
        select preference.*
        from public.community_group_chat_preferences as preference
        where preference.user_id = $1
        order by preference.updated_at, preference.group_id, preference.user_id
        offset $2 limit $3
      ) as export_row
    $sql$
    when 'direct_media_metadata' then $sql$
      select coalesce(jsonb_agg(to_jsonb(export_row) order by export_row.created_at, export_row.id), '[]'::jsonb)
      from (
        select attachment.id, attachment.conversation_id, attachment.message_id,
          attachment.uploader_id, attachment.mime_type, attachment.byte_size,
          attachment.storage_provider, attachment.status, attachment.scan_provider,
          attachment.scan_status, attachment.scan_summary, attachment.scanned_at,
          attachment.reviewed_at, attachment.deleted_at, attachment.created_at
        from public.community_direct_message_attachments as attachment
        where attachment.uploader_id = $1
        order by attachment.created_at, attachment.id
        offset $2 limit $3
      ) as export_row
    $sql$
    when 'group_chat_media_metadata' then $sql$
      select coalesce(jsonb_agg(to_jsonb(export_row) order by export_row.created_at, export_row.id), '[]'::jsonb)
      from (
        select attachment.id, attachment.group_id, attachment.message_id,
          attachment.uploader_id, attachment.mime_type, attachment.byte_size,
          attachment.status, attachment.expires_at, attachment.created_at,
          attachment.reviewed_at, attachment.deleted_at
        from public.community_group_chat_attachments as attachment
        where attachment.uploader_id = $1
        order by attachment.created_at, attachment.id
        offset $2 limit $3
      ) as export_row
    $sql$
    when 'reports_submitted' then $sql$
      select coalesce(jsonb_agg(to_jsonb(export_row) order by export_row.created_at, export_row.id), '[]'::jsonb)
      from (
        select report.*
        from public.community_reports as report
        where report.reporter_id = $1
        order by report.created_at, report.id
        offset $2 limit $3
      ) as export_row
    $sql$
    when 'group_moderation_activity' then $sql$
      select coalesce(jsonb_agg(to_jsonb(export_row) order by export_row.created_at, export_row.id), '[]'::jsonb)
      from (
        select audit.*
        from public.community_group_moderation_audit as audit
        where audit.actor_id = $1 or audit.target_user_id = $1
        order by audit.created_at, audit.id
        offset $2 limit $3
      ) as export_row
    $sql$
    when 'push_devices' then $sql$
      select coalesce(jsonb_agg(to_jsonb(export_row) order by export_row.created_at, export_row.id), '[]'::jsonb)
      from (
        select device.id, device.user_id, device.environment, device.is_active,
          device.last_registered_at, device.last_delivery_at,
          device.deactivated_at, device.created_at, device.updated_at
        from public.community_push_devices as device
        where device.user_id = $1
        order by device.created_at, device.id
        offset $2 limit $3
      ) as export_row
    $sql$
    when 'push_preferences' then $sql$
      select coalesce(jsonb_agg(to_jsonb(export_row) order by export_row.updated_at, export_row.user_id), '[]'::jsonb)
      from (
        select preference.*
        from public.community_push_preferences as preference
        where preference.user_id = $1
        order by preference.updated_at, preference.user_id
        offset $2 limit $3
      ) as export_row
    $sql$
    else null
  end;

  if query_text is null then
    raise exception 'invalid account export section';
  end if;

  execute query_text
  into page_rows
  using account_user_id, page_offset, page_size + 1;

  page_rows := coalesce(page_rows, '[]'::jsonb);
  has_more := jsonb_array_length(page_rows) > page_size;
  if has_more then
    select coalesce(jsonb_agg(value order by ordinal), '[]'::jsonb)
    into page_rows
    from jsonb_array_elements(page_rows) with ordinality as page(value, ordinal)
    where ordinal <= page_size;
  end if;

  return query select page_rows, has_more;
end;
$$;

revoke all on function public.export_community_account_section(uuid, text, integer, integer)
  from public, anon, authenticated;
grant execute on function public.export_community_account_section(uuid, text, integer, integer)
  to service_role;

comment on function public.export_community_account_metadata(uuid) is
  'Returns only bounded scalar account metadata for the paginated export Worker.';
comment on function public.export_community_account_section(uuid, text, integer, integer) is
  'Returns one bounded allowlisted account-export section page without provider secrets or storage paths.';
