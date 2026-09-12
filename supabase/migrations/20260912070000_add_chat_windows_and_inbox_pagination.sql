-- Keep chat reads bounded and keyset-based. The legacy list RPCs remain
-- available for older clients but now return only the newest window.

create index if not exists community_messages_conversation_visible_cursor_idx
  on public.community_messages (conversation_id, created_at desc, id desc)
  where deleted_at is null;

create index if not exists community_group_chat_messages_group_visible_cursor_idx
  on public.community_group_chat_messages (group_id, created_at desc, id desc)
  where deleted_at is null;

create or replace function public.list_community_conversation_messages_page(
  target_conversation_id uuid,
  page_size integer default 50,
  before_created_at timestamptz default null,
  before_message_id uuid default null
)
returns table (
  id uuid,
  conversation_id uuid,
  sender_id uuid,
  body text,
  created_at timestamptz,
  deleted_at timestamptz,
  attachment_id uuid,
  attachment_mime_type text
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if page_size is null or page_size < 1 or page_size > 51
     or (before_created_at is null) <> (before_message_id is null)
     or not public.can_access_community_conversation(target_conversation_id)
     or not exists (
       select 1
       from public.community_conversations conversation
       join public.community_conversation_members member
         on member.conversation_id = conversation.id
       where conversation.id = target_conversation_id
         and conversation.status = 'active'
         and member.user_id = (select auth.uid())
         and member.status = 'active'
     ) then
    raise exception 'conversation unavailable';
  end if;

  return query
  with eligible as materialized (
    select message.id, message.conversation_id, message.sender_id, message.body,
      message.created_at, message.deleted_at, attachment.id as attachment_id,
      attachment.mime_type as attachment_mime_type
    from public.community_messages message
    left join public.community_direct_message_attachments attachment
      on attachment.message_id = message.id
      and attachment.status = 'ready'
      and attachment.scan_status = 'passed'
    where message.conversation_id = target_conversation_id
      and message.deleted_at is null
      and not exists (
        select 1
        from public.community_message_member_hides hidden
        where hidden.message_id = message.id
          and hidden.user_id = (select auth.uid())
      )
      and (
        before_created_at is null
        or (message.created_at, message.id) < (before_created_at, before_message_id)
      )
    order by message.created_at desc, message.id desc
    limit page_size
  )
  select eligible.id, eligible.conversation_id, eligible.sender_id, eligible.body,
    eligible.created_at, eligible.deleted_at, eligible.attachment_id,
    eligible.attachment_mime_type
  from eligible
  order by eligible.created_at asc, eligible.id asc;
end;
$$;

revoke all on function public.list_community_conversation_messages_page(uuid, integer, timestamptz, uuid) from public;
grant execute on function public.list_community_conversation_messages_page(uuid, integer, timestamptz, uuid) to authenticated;

-- Preserve the old RPC contract for older clients while bounding its result.
create or replace function public.list_community_conversation_messages(target_conversation_id uuid)
returns table (
  id uuid,
  conversation_id uuid,
  sender_id uuid,
  body text,
  created_at timestamptz,
  deleted_at timestamptz,
  attachment_id uuid,
  attachment_mime_type text
)
language sql
security definer
set search_path = ''
as $$
  select *
  from public.list_community_conversation_messages_page(target_conversation_id, 50, null, null);
$$;

revoke all on function public.list_community_conversation_messages(uuid) from public;
grant execute on function public.list_community_conversation_messages(uuid) to authenticated;

create or replace function public.list_community_group_chat_messages_page(
  target_group_id uuid,
  page_size integer default 50,
  before_created_at timestamptz default null,
  before_message_id uuid default null
)
returns table (
  id uuid,
  sender_id uuid,
  display_name text,
  username text,
  body text,
  created_at timestamptz,
  attachment_id uuid,
  attachment_mime_type text
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if page_size is null or page_size < 1 or page_size > 51
     or (before_created_at is null) <> (before_message_id is null)
     or not public.can_access_community_group_chat(target_group_id) then
    raise exception 'group chat unavailable';
  end if;

  return query
  with eligible as materialized (
    select message.id, message.sender_id, profile.display_name, profile.username,
      message.body, message.created_at, attachment.id as attachment_id,
      attachment.mime_type as attachment_mime_type
    from public.community_group_chat_messages message
    join public.community_profiles profile on profile.user_id = message.sender_id
    left join public.community_group_chat_attachments attachment
      on attachment.message_id = message.id
      and attachment.status = 'ready'
      and attachment.scan_status = 'passed'
    where message.group_id = target_group_id
      and message.deleted_at is null
      and message.moderation_state = 'active'
      and profile.moderation_state = 'active'
      and public.can_view_community_user(message.sender_id)
      and not exists (
        select 1
        from public.community_group_chat_message_member_hides hidden
        where hidden.message_id = message.id
          and hidden.user_id = (select auth.uid())
      )
      and (
        before_created_at is null
        or (message.created_at, message.id) < (before_created_at, before_message_id)
      )
    order by message.created_at desc, message.id desc
    limit page_size
  )
  select eligible.id, eligible.sender_id, eligible.display_name, eligible.username,
    eligible.body, eligible.created_at, eligible.attachment_id,
    eligible.attachment_mime_type
  from eligible
  order by eligible.created_at asc, eligible.id asc;
end;
$$;

revoke all on function public.list_community_group_chat_messages_page(uuid, integer, timestamptz, uuid) from public;
grant execute on function public.list_community_group_chat_messages_page(uuid, integer, timestamptz, uuid) to authenticated;

-- Preserve the old group-chat RPC contract while bounding its result.
create or replace function public.list_community_group_chat_messages(target_group_id uuid)
returns table (
  id uuid,
  sender_id uuid,
  display_name text,
  username text,
  body text,
  created_at timestamptz,
  attachment_id uuid,
  attachment_mime_type text
)
language sql
security definer
set search_path = ''
as $$
  select *
  from public.list_community_group_chat_messages_page(target_group_id, 50, null, null);
$$;

revoke all on function public.list_community_group_chat_messages(uuid) from public;
grant execute on function public.list_community_group_chat_messages(uuid) to authenticated;

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
      profile.user_id as other_user_id,
      profile.display_name,
      profile.username,
      profile.avatar_path,
      (
        select message.body
        from public.community_messages message
        where message.conversation_id = conversation.id
          and message.deleted_at is null
          and not exists (
            select 1
            from public.community_message_member_hides hidden
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
        from public.community_messages unread
        where unread.conversation_id = conversation.id
          and unread.deleted_at is null
          and unread.sender_id <> (select auth.uid())
          and (
            member.last_read_at is null
            or unread.created_at > member.last_read_at
          )
          and not exists (
            select 1
            from public.community_message_member_hides hidden
            where hidden.message_id = unread.id
              and hidden.user_id = (select auth.uid())
          )
      ) as unread_count
    from public.community_conversations conversation
    join public.community_conversation_members member
      on member.conversation_id = conversation.id
     and member.user_id = (select auth.uid())
    join public.community_profiles profile
      on profile.user_id = case
        when conversation.participant_one_id = (select auth.uid()) then conversation.participant_two_id
        else conversation.participant_one_id
      end
    left join public.community_conversation_preferences preference
      on preference.conversation_id = conversation.id
     and preference.user_id = (select auth.uid())
    where (select auth.uid()) is not null
      and member.status in ('pending', 'active')
      and conversation.status in ('pending', 'active')
      and not coalesce(preference.is_hidden, false)
      and public.can_view_community_user(profile.user_id)
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

revoke all on function public.list_community_direct_conversations_page(integer, boolean, timestamptz, uuid) from public;
grant execute on function public.list_community_direct_conversations_page(integer, boolean, timestamptz, uuid) to authenticated;

-- The original no-argument RPC keeps its response shape for older clients but
-- now returns only the newest 50 conversations from the same secure page.
create or replace function public.list_community_direct_conversations()
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
  last_message text
)
language sql
security definer
set search_path = ''
as $$
  select page.conversation_id, page.status, page.requested_by_id,
    page.created_at, page.updated_at, page.other_user_id,
    page.display_name, page.username, page.avatar_path, page.last_message
  from public.list_community_direct_conversations_page(50, null, null, null) page;
$$;

revoke all on function public.list_community_direct_conversations() from public;
grant execute on function public.list_community_direct_conversations() to authenticated;
