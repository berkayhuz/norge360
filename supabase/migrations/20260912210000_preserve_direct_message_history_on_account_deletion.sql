-- Preserve the remaining participant's direct-message history when the other
-- account is deleted. The deleted account's UUID remains only as an opaque,
-- non-joinable tombstone reference; profile and Auth records are still removed.

alter table public.community_conversations
  drop constraint if exists community_conversations_participant_one_id_fkey,
  drop constraint if exists community_conversations_participant_two_id_fkey,
  drop constraint if exists community_conversations_requested_by_id_fkey;

alter table public.community_messages
  drop constraint if exists community_messages_sender_id_fkey;

alter table public.community_direct_message_attachments
  drop constraint if exists community_direct_message_attachments_uploader_id_fkey;

create or replace function public.can_access_community_conversation(target_conversation_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  with conversation_context as (
    select
      conversation.id,
      case
        when conversation.participant_one_id = (select auth.uid()) then conversation.participant_two_id
        else conversation.participant_one_id
      end as other_user_id
    from public.community_conversations as conversation
    join public.community_conversation_members as member
      on member.conversation_id = conversation.id
    where conversation.id = target_conversation_id
      and member.user_id = (select auth.uid())
      and member.status in ('pending', 'active')
  )
  select exists (
    select 1
    from conversation_context
    where public.can_view_community_user(other_user_id)
       or not exists (
         select 1
         from auth.users as deleted_member
         where deleted_member.id = conversation_context.other_user_id
       )
  );
$$;

-- The inbox must retain a conversation whose other participant no longer has
-- an Auth/profile row. The fallback label is intentionally generic and never
-- exposes the deleted member's former profile fields.
create or replace function public.list_community_direct_conversations_page(
  page_size integer default 50,
  after_is_pinned boolean default null,
  after_updated_at timestamptz default null,
  after_conversation_id uuid default null
)
returns table (
  conversation_id uuid,
  status text,
  requested_by_id uuid,
  created_at timestamptz,
  updated_at timestamptz,
  other_user_id uuid,
  display_name text,
  username text,
  avatar_path text,
  last_message text,
  is_muted boolean,
  is_pinned boolean,
  is_hidden boolean,
  is_restricted boolean,
  background_style text,
  bubble_color text,
  unread_count integer
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if page_size is null or page_size < 1 or page_size > 51
     or (after_is_pinned is null) <> (after_updated_at is null)
     or (after_is_pinned is null) <> (after_conversation_id is null) then
    raise exception 'invalid inbox page';
  end if;

  return query
  with inbox as materialized (
    select
      conversation.id as conversation_id,
      conversation.status,
      conversation.requested_by_id,
      conversation.created_at,
      conversation.updated_at,
      case
        when conversation.participant_one_id = (select auth.uid()) then conversation.participant_two_id
        else conversation.participant_one_id
      end as other_user_id,
      coalesce(profile.display_name, 'Deleted member') as display_name,
      coalesce(profile.username, 'deleted-member') as username,
      profile.avatar_path,
      (
        select message.body
        from public.community_messages as message
        where message.conversation_id = conversation.id
          and message.deleted_at is null
          and not exists (
            select 1
            from public.community_message_member_hides as hidden
            where hidden.message_id = message.id
              and hidden.user_id = (select auth.uid())
          )
        order by message.created_at desc, message.id desc
        limit 1
      ) as last_message,
      coalesce(preference.is_muted, false) as is_muted,
      coalesce(preference.is_pinned, false) as is_pinned,
      coalesce(preference.is_hidden, false) as is_hidden,
      coalesce(preference.is_restricted, false) as is_restricted,
      coalesce(preference.background_style, 'plain') as background_style,
      coalesce(preference.bubble_color, 'teal') as bubble_color,
      (
        select count(*)::integer
        from public.community_messages as unread
        where unread.conversation_id = conversation.id
          and unread.deleted_at is null
          and unread.sender_id <> (select auth.uid())
          and (
            member.last_read_at is null
            or unread.created_at > member.last_read_at
          )
          and not exists (
            select 1
            from public.community_message_member_hides as hidden
            where hidden.message_id = unread.id
              and hidden.user_id = (select auth.uid())
          )
      ) as unread_count
    from public.community_conversations as conversation
    join public.community_conversation_members as member
      on member.conversation_id = conversation.id
     and member.user_id = (select auth.uid())
    left join public.community_profiles as profile
      on profile.user_id = case
        when conversation.participant_one_id = (select auth.uid()) then conversation.participant_two_id
        else conversation.participant_one_id
      end
    left join public.community_conversation_preferences as preference
      on preference.conversation_id = conversation.id
     and preference.user_id = (select auth.uid())
    where (select auth.uid()) is not null
      and member.status in ('pending', 'active')
      and conversation.status in ('pending', 'active')
      and not coalesce(preference.is_hidden, false)
      and (
        (
          profile.user_id is not null
          and public.can_view_community_user(profile.user_id)
        )
        or (
          profile.user_id is null
          and not exists (
            select 1
            from auth.users as deleted_member
            where deleted_member.id = case
              when conversation.participant_one_id = (select auth.uid()) then conversation.participant_two_id
              else conversation.participant_one_id
            end
          )
        )
      )
  )
  select inbox.conversation_id, inbox.status, inbox.requested_by_id,
    inbox.created_at, inbox.updated_at, inbox.other_user_id,
    inbox.display_name, inbox.username, inbox.avatar_path, inbox.last_message,
    inbox.is_muted, inbox.is_pinned, inbox.is_hidden, inbox.is_restricted,
    inbox.background_style, inbox.bubble_color, inbox.unread_count
  from inbox
  where after_is_pinned is null
     or inbox.is_pinned < after_is_pinned
     or (
       inbox.is_pinned = after_is_pinned
       and (
         inbox.updated_at < after_updated_at
         or (
           inbox.updated_at = after_updated_at
           and inbox.conversation_id < after_conversation_id
         )
       )
     )
  order by inbox.is_pinned desc, inbox.updated_at desc, inbox.conversation_id desc
  limit page_size;
end;
$$;

-- Attached direct media is part of the retained two-party conversation. Only
-- unattached staged media remains eligible for the normal account cleanup.
create or replace function public.issue_community_media_view(
  target_media_type text,
  target_attachment_id uuid,
  target_viewer_id uuid
)
returns table (
  provider_asset_id text,
  rate_limited boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  authorized_asset_id text;
  current_window timestamptz := date_trunc('minute', now());
  current_count integer;
begin
  if target_media_type not in ('group', 'direct')
     or target_attachment_id is null
     or target_viewer_id is null
     or not exists (
       select 1
       from auth.users
       where id = target_viewer_id
     ) then
    return;
  end if;

  if target_media_type = 'group' then
    select attachment.provider_asset_id
    into authorized_asset_id
    from public.community_group_chat_attachments as attachment
    join public.community_group_chat_messages as message
      on message.id = attachment.message_id
     and message.group_id = attachment.group_id
    join public.community_group_memberships as membership
      on membership.group_id = attachment.group_id
     and membership.user_id = target_viewer_id
    where attachment.id = target_attachment_id
      and attachment.status = 'ready'
      and attachment.scan_status = 'passed'
      and attachment.provider_asset_id is not null
      and message.moderation_state = 'active'
      and message.deleted_at is null
      and not exists (
        select 1
        from public.community_group_bans as ban
        where ban.group_id = attachment.group_id
          and ban.user_id = target_viewer_id
      );
  else
    select attachment.provider_asset_id
    into authorized_asset_id
    from public.community_direct_message_attachments as attachment
    join public.community_messages as message
      on message.id = attachment.message_id
     and message.conversation_id = attachment.conversation_id
    join public.community_conversations as conversation
      on conversation.id = attachment.conversation_id
    join public.community_conversation_members as caller_membership
      on caller_membership.conversation_id = conversation.id
     and caller_membership.user_id = target_viewer_id
     and caller_membership.status = 'active'
    left join public.community_conversation_members as other_membership
      on other_membership.conversation_id = conversation.id
     and other_membership.user_id = case
       when conversation.participant_one_id = target_viewer_id then conversation.participant_two_id
       else conversation.participant_one_id
     end
    where attachment.id = target_attachment_id
      and attachment.status = 'ready'
      and attachment.scan_status = 'passed'
      and attachment.provider_asset_id is not null
      and message.deleted_at is null
      and conversation.status = 'active'
      and (
        conversation.participant_one_id = target_viewer_id
        or conversation.participant_two_id = target_viewer_id
      )
      and (
        other_membership.status = 'active'
        or not exists (
          select 1
          from auth.users as deleted_member
          where deleted_member.id = case
            when conversation.participant_one_id = target_viewer_id then conversation.participant_two_id
            else conversation.participant_one_id
          end
        )
      )
      and not exists (
        select 1
        from public.user_blocks as block
        where (block.blocker_id = target_viewer_id and block.blocked_user_id = case
          when conversation.participant_one_id = target_viewer_id then conversation.participant_two_id
          else conversation.participant_one_id
        end)
           or (block.blocked_user_id = target_viewer_id and block.blocker_id = case
          when conversation.participant_one_id = target_viewer_id then conversation.participant_two_id
          else conversation.participant_one_id
        end)
      )
      and not exists (
        select 1
        from public.community_message_member_hides as hidden
        where hidden.message_id = message.id
          and hidden.user_id = target_viewer_id
      );
  end if;

  if authorized_asset_id is null then
    return;
  end if;

  insert into public.community_media_view_rate_limits(
    user_id,
    window_started_at,
    request_count
  )
  values (target_viewer_id, current_window, 1)
  on conflict (user_id) do update
  set window_started_at = case
        when public.community_media_view_rate_limits.window_started_at < excluded.window_started_at
          then excluded.window_started_at
        else public.community_media_view_rate_limits.window_started_at
      end,
      request_count = case
        when public.community_media_view_rate_limits.window_started_at < excluded.window_started_at
          then 1
        else least(public.community_media_view_rate_limits.request_count + 1, 61)
      end,
      updated_at = now()
  returning request_count into current_count;

  if current_count > 60 then
    return query select null::text, true;
    return;
  end if;

  return query select authorized_asset_id, false;
end;
$$;

comment on function public.can_access_community_conversation(uuid) is
  'Members retain access to direct history when the other account has been deleted; deleted identities are not rehydrated.';
comment on function public.issue_community_media_view(text, uuid, uuid) is
  'Server-only authorization and rate-limit boundary for private media, including retained direct history after account deletion.';
