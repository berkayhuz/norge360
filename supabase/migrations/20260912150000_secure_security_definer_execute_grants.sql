-- Keep SECURITY DEFINER RPCs behind an explicit role allow-list.
-- Supabase's default function ACLs can grant anon/authenticated/service_role
-- execute independently of a REVOKE from PUBLIC.

alter default privileges in schema public
  revoke execute on functions from public, anon, authenticated, service_role;

-- This helper is required by authenticated RLS policies and an invoker
-- trigger. Bind its result to the current actor so a direct RPC call cannot
-- inspect another member's moderation restriction.
create or replace function public.is_community_member_posting_restricted(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.community_member_restrictions as restriction
    where target_user_id = (select auth.uid())
      and restriction.user_id = (select auth.uid())
      and restriction.scope = 'posting'
      and restriction.status = 'active'
      and (restriction.expires_at is null or restriction.expires_at > now())
  );
$$;

do $$
declare
  routine record;
  argument_list text;
begin
  for routine in
    select p.oid, n.nspname, p.proname
    from pg_proc as p
    join pg_namespace as n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef
  loop
    argument_list := substring(
      routine.oid::regprocedure::text
      from position('(' in routine.oid::regprocedure::text)
    );

    execute format(
      'revoke all on function %I.%I%s from public, anon, authenticated, service_role',
      routine.nspname,
      routine.proname,
      argument_list
    );
  end loop;
end;
$$;

-- Client-callable RPCs. Keep this list aligned with the existing migration
-- grants; obsolete overloads are ignored after a function is replaced.
do $$
declare
  signature text;
  routine_oid oid;
  client_routines constant text[] := array[
    'public.acknowledge_community_group_post_media_cleanup(uuid, text[])',
    'public.ban_community_group_member(uuid, uuid)',
    'public.can_access_community_conversation(uuid)',
    'public.can_access_community_group_chat(uuid)',
    'public.can_manage_community_group(uuid)',
    'public.can_post_to_community_group(uuid)',
    'public.can_view_community_user(uuid)',
    'public.community_follow_state(uuid)',
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
    'public.list_community_post_comments(uuid)',
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
  foreach signature in array client_routines
  loop
    routine_oid := to_regprocedure(signature);
    if routine_oid is not null
       and (select p.prosecdef from pg_proc as p where p.oid = routine_oid)
    then
      execute format('grant execute on function %s to authenticated', signature);
    end if;
  end loop;
end;
$$;

-- Worker-only RPCs. These functions accept trusted server-side workflow data
-- and must never be callable by anon/authenticated clients.
grant execute on function public.apply_community_group_chat_moderation_action(uuid, uuid, text, text, integer, text) to service_role;
grant execute on function public.apply_community_moderation_action(uuid, uuid, text, text, integer, text) to service_role;
grant execute on function public.can_deliver_community_group_chat_signal(uuid) to service_role;
grant execute on function public.can_deliver_community_message_signal(uuid) to service_role;
grant execute on function public.claim_community_media_scan(text, uuid) to service_role;
grant execute on function public.claim_community_push_deliveries(text, uuid, uuid[], integer) to service_role;
grant execute on function public.claim_expired_community_media_attachments(text, integer) to service_role;
grant execute on function public.finalize_community_media_cleanup(text, uuid) to service_role;
grant execute on function public.finalize_community_push_deliveries(jsonb) to service_role;
grant execute on function public.finish_community_media_scan(text, uuid, text, text, text) to service_role;
grant execute on function public.get_community_media_scan_status(text, uuid, uuid) to service_role;
grant execute on function public.issue_community_media_view(text, uuid, uuid) to service_role;
grant execute on function public.process_community_group_chat_push_fanout(uuid, integer) to service_role;
grant execute on function public.prune_community_group_chat_signals() to service_role;
grant execute on function public.prune_community_message_signals(integer) to service_role;
grant execute on function public.queue_community_event_reminders() to service_role;
grant execute on function public.queue_community_media_scan(text, uuid, uuid) to service_role;
grant execute on function public.resolve_community_report(uuid, uuid, text, text, text) to service_role;
