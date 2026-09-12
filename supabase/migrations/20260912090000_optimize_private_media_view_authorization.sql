-- Keep private media view authorization and rate limiting in one server-only
-- database boundary. The Worker authenticates the Supabase token first and
-- passes that verified subject here through the service-role connection.

create table if not exists public.community_media_view_rate_limits (
  user_id uuid primary key references auth.users(id) on delete cascade,
  window_started_at timestamptz not null,
  request_count integer not null default 0 check (request_count between 0 and 61),
  updated_at timestamptz not null default now()
);

alter table public.community_media_view_rate_limits enable row level security;
revoke all on public.community_media_view_rate_limits from public, anon, authenticated;

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
    join public.community_conversation_members as other_membership
      on other_membership.conversation_id = conversation.id
     and other_membership.user_id = case
       when conversation.participant_one_id = target_viewer_id then conversation.participant_two_id
       else conversation.participant_one_id
     end
     and other_membership.status = 'active'
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

  -- The counter is intentionally capped at 61 so an abusive burst cannot
  -- grow this row without bound. The upsert serializes concurrent requests
  -- for one viewer while keeping the rate-limit decision in this RPC.
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

revoke all on function public.issue_community_media_view(text, uuid, uuid) from public, anon, authenticated;
grant execute on function public.issue_community_media_view(text, uuid, uuid) to service_role;

comment on function public.issue_community_media_view(text, uuid, uuid) is
  'Server-only authorization and rate-limit boundary for private group/direct media view URL issuance.';
