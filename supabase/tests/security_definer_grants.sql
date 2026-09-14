-- SECURITY DEFINER contract test. Run against a disposable migrated database.
begin;

do $$
declare
  invalid_search_path_count integer;
  anon_execute_count integer;
begin
  select count(*)
  into invalid_search_path_count
  from pg_proc as p
  join pg_namespace as n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.prosecdef
    and not (p.proconfig @> array['search_path=""']);

  if invalid_search_path_count <> 0 then
    raise exception '% public SECURITY DEFINER functions do not pin search_path to empty', invalid_search_path_count;
  end if;

  select count(*)
  into anon_execute_count
  from pg_proc as p
  join pg_namespace as n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.prosecdef
    and has_function_privilege('anon', p.oid, 'EXECUTE');

  if anon_execute_count <> 0 then
    raise exception '% public SECURITY DEFINER functions remain executable by anon', anon_execute_count;
  end if;
end;
$$;

do $$
declare
  signature text;
  routine_oid oid;
  invoker_routines constant text[] := array[
    'public.list_community_feed_page(text, integer)',
    'public.list_community_member_media_posts_page(uuid, text, integer)',
    'public.list_community_post_comments(uuid, text, integer)',
    'public.search_community_hashtag_posts(text)',
    'public.search_community_hashtags(text)',
    'public.search_community_post_results(text)'
  ];
begin
  foreach signature in array invoker_routines
  loop
    routine_oid := to_regprocedure(signature);
    if routine_oid is not null
       and (select p.prosecdef from pg_proc as p where p.oid = routine_oid)
    then
      raise exception 'read-only projection must remain SECURITY INVOKER: %', signature;
    end if;
  end loop;
end;
$$;

do $$
declare
  signature text;
  routine_oid oid;
  authenticated_routines constant text[] := array[
    'public.acknowledge_community_group_post_media_cleanup(uuid, text[])',
    'public.ban_community_group_member(uuid, uuid)',
    'public.can_access_community_conversation(uuid)',
    'public.can_access_community_group_chat(uuid)',
    'public.can_manage_community_group(uuid)',
    'public.can_post_to_community_group(uuid)',
    'public.can_view_community_group(uuid)',
    'public.can_view_community_user(uuid)',
    'public.community_follow_state(uuid)',
    'public.consume_community_request_rate_limit(text, integer, integer, uuid)',
    'public.create_community_event(text, text, text, timestamp with time zone, integer)',
    'public.create_community_event(text, text, text, timestamp with time zone, integer, text)',
    'public.create_community_group(text, text, text, text, text, text)',
    'public.create_community_group_event(uuid, text, text, text, timestamp with time zone, integer)',
    'public.create_community_group_event(uuid, text, text, text, timestamp with time zone, integer, text)',
    'public.create_direct_conversation(uuid)',
    'public.deactivate_community_push_device(text)',
    'public.delete_community_event(uuid)',
    'public.get_community_follow_visibility()',
    'public.get_community_group_chat_message_read_receipt(uuid)',
    'public.get_community_group_chat_notification_preference(uuid)',
    'public.get_community_liked_posts_visibility()',
    'public.get_community_message_read_receipt(uuid)',
    'public.get_my_community_profile()',
    'public.hide_community_group_chat_message_for_member(uuid)',
    'public.hide_community_message_for_member(uuid)',
    'public.invite_community_event_member(uuid, uuid)',
    'public.invite_community_group_member(uuid, uuid)',
    'public.is_community_group_member(uuid)',
    'public.is_community_member_posting_restricted(uuid)',
    'public.is_community_username_available(text)',
    'public.list_community_conversation_messages(uuid)',
    'public.list_community_conversation_messages_after(uuid, timestamp with time zone, uuid)',
    'public.list_community_conversation_messages_page(uuid, integer, timestamp with time zone, uuid)',
    'public.list_community_direct_conversations()',
    'public.list_community_direct_conversations_page(integer, boolean, timestamp with time zone, uuid)',
    'public.list_community_feed_page(text, integer)',
    'public.list_community_follow_profiles(uuid, text)',
    'public.list_community_group_bans(uuid)',
    'public.list_community_group_chat_messages(uuid)',
    'public.list_community_group_chat_messages_after(uuid, timestamp with time zone, uuid)',
    'public.list_community_group_chat_messages_page(uuid, integer, timestamp with time zone, uuid)',
    'public.list_community_group_join_requests(uuid)',
    'public.list_community_liked_post_ids(uuid)',
    'public.list_community_member_media_posts_page(uuid, text, integer)',
    'public.list_community_post_comments(uuid, text, integer)',
    'public.list_own_community_saved_post_ids()',
    'public.list_own_community_blocks()',
    'public.manage_community_group_member(uuid, uuid, text, text)',
    'public.mark_community_conversation_read(uuid)',
    'public.mark_community_group_chat_read(uuid)',
    'public.register_community_push_device(text, text)',
    'public.remove_community_group_post(uuid)',
    'public.report_community_group_chat_message(uuid, text, text)',
    'public.report_community_message(uuid, text, text)',
    'public.request_community_group_join(uuid)',
    'public.respond_to_direct_conversation(uuid, boolean)',
    'public.restore_community_message_for_member(uuid)',
    'public.review_community_group_join_request(uuid, uuid, text)',
    'public.search_community_groups(text)',
    'public.search_community_hashtag_posts(text)',
    'public.search_community_hashtags(text)',
    'public.search_community_posts(text)',
    'public.search_community_post_results(text)',
    'public.search_community_profiles(text)',
    'public.send_community_group_chat_message(uuid, text)',
    'public.send_community_group_chat_message_with_attachment(uuid, text, uuid)',
    'public.send_community_message(uuid, text)',
    'public.send_community_message_with_attachment(uuid, text, uuid)',
    'public.set_community_event_like(uuid, boolean)',
    'public.set_community_event_rsvp(uuid, text)',
    'public.set_community_group_photo(uuid, text)',
    'public.swap_own_community_profile_media(text, text)',
    'public.toggle_community_follow(uuid)',
    'public.toggle_community_post_like(uuid)',
    'public.toggle_community_post_save(uuid)',
    'public.transfer_community_group_ownership(uuid, uuid)',
    'public.unban_community_group_member(uuid, uuid)',
    'public.update_community_conversation_inbox_preferences(uuid, boolean, boolean, boolean, boolean, text, text)',
    'public.update_community_conversation_preferences(uuid, boolean, boolean, text, text)',
    'public.update_community_follow_visibility(text, text)',
    'public.update_community_group_chat_notification_preference(uuid, boolean)',
    'public.update_community_group_details(uuid, text, text, text)',
    'public.update_community_group_posting_permission(uuid, text)',
    'public.update_community_group_visibility(uuid, text)',
    'public.update_community_liked_posts_visibility(text)',
    'public.update_community_message_push_enabled(boolean)',
    'public.update_community_message_read_receipts(boolean)',
    'public.upsert_own_community_profile(text, text, text, text, text, text[], text[], boolean)'
  ];
begin
  foreach signature in array authenticated_routines
  loop
    routine_oid := to_regprocedure(signature);
    if routine_oid is not null
       and (select p.prosecdef from pg_proc as p where p.oid = routine_oid)
       and not has_function_privilege('authenticated', routine_oid, 'EXECUTE')
    then
      raise exception 'authenticated execute grant missing for %', signature;
    end if;
  end loop;

  for routine_oid in
    select p.oid
    from pg_proc as p
    join pg_namespace as n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not exists (
        select 1
        from unnest(authenticated_routines) as expected(signature)
        where to_regprocedure(expected.signature) = p.oid
      )
  loop
    raise exception 'unexpected authenticated execute grant on %', routine_oid::regprocedure;
  end loop;
end;
$$;

do $$
declare
  signature text;
  routine_oid oid;
  worker_routines constant text[] := array[
    'public.apply_community_group_chat_moderation_action(uuid, uuid, text, text, integer, text)',
    'public.apply_community_moderation_action(uuid, uuid, text, text, integer, text)',
    'public.can_deliver_community_group_chat_signal(uuid)',
    'public.can_deliver_community_message_signal(uuid)',
    'public.claim_community_media_scan(text, uuid)',
    'public.claim_community_push_deliveries(text, uuid, uuid[], integer)',
    'public.claim_expired_community_media_attachments(text, integer)',
    'public.finalize_community_media_cleanup(text, uuid)',
    'public.finalize_community_push_deliveries(jsonb)',
    'public.finish_community_media_scan(text, uuid, text, text, text)',
    'public.get_community_media_scan_status(text, uuid, uuid)',
    'public.issue_community_media_view(text, uuid, uuid)',
    'public.process_community_group_chat_push_fanout(uuid, integer)',
    'public.prune_community_group_chat_signals()',
    'public.prune_community_message_signals(integer)',
    'public.requeue_expired_community_push_deliveries(integer)',
    'public.queue_community_event_reminders()',
    'public.queue_community_media_scan(text, uuid, uuid)',
    'public.resolve_community_report(uuid, uuid, text, text, text)',
    'public.export_community_account_metadata(uuid)',
    'public.export_community_account_section(uuid, text, integer, integer)',
    'public.purge_community_storage_cleanup_outbox(integer)',
    'public.purge_community_transport_retention(integer)',
    'public.stage_community_direct_message_attachment(uuid, uuid, text, integer)',
    'public.stage_community_group_chat_attachment(uuid, uuid, text, integer)'
  ];
begin
  foreach signature in array worker_routines
  loop
    routine_oid := to_regprocedure(signature);
    if routine_oid is null then
      raise exception 'worker SECURITY DEFINER routine is missing: %', signature;
    end if;
    if has_function_privilege('anon', routine_oid, 'EXECUTE')
       or has_function_privilege('authenticated', routine_oid, 'EXECUTE')
       or not has_function_privilege('service_role', routine_oid, 'EXECUTE')
    then
      raise exception 'worker-only execute boundary is invalid for %', signature;
    end if;
  end loop;
end;
$$;

rollback;
