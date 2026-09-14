-- Run against a disposable, fully migrated database as its owner.
-- The quota is shared by group/direct upload URLs and survives attachment
-- deletion, which covers both the race and create-delete-repeat regressions.
begin;

insert into auth.users(id)
values
  ('a1000000-0000-4000-8000-000000000001'),
  ('a1000000-0000-4000-8000-000000000002');

select set_config('request.jwt.claim.sub', 'a1000000-0000-4000-8000-000000000001', true);

insert into public.community_profiles(user_id, display_name, preferred_locale, norway_status, username)
values
  ('a1000000-0000-4000-8000-000000000001', 'Upload One', 'en', 'resident', 'upload_quota_one'),
  ('a1000000-0000-4000-8000-000000000002', 'Upload Two', 'en', 'resident', 'upload_quota_two');

insert into public.community_groups(
  id, name, slug, description, scope, created_by
)
values (
  'a2000000-0000-4000-8000-000000000001',
  'Upload quota fixture',
  'upload-quota-fixture',
  'Fixture group for upload quota tests.',
  'interest',
  'a1000000-0000-4000-8000-000000000001'
);

insert into public.community_group_memberships(group_id, user_id, role)
values
  ('a2000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000001', 'owner'),
  ('a2000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000002', 'member');

insert into public.community_conversations(
  id, participant_one_id, participant_two_id, requested_by_id, status
)
values (
  'a3000000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-8000-000000000002',
  'a1000000-0000-4000-8000-000000000001',
  'active'
);

insert into public.community_conversation_members(conversation_id, user_id, status)
values
  ('a3000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000001', 'active'),
  ('a3000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000002', 'active');

set local role service_role;
select set_config('request.jwt.claim.role', 'service_role', true);

do $$
declare
  staged record;
  staged_count integer;
  quota_count integer;
begin
  for attempt in 1..6 loop
    select * into staged
    from public.stage_community_group_chat_attachment(
      'a2000000-0000-4000-8000-000000000001',
      'a1000000-0000-4000-8000-000000000001',
      'image/jpeg',
      2048
    );
    if staged.rate_limited or staged.attachment_id is null then
      raise exception 'group upload attempt % was incorrectly rate limited', attempt;
    end if;
  end loop;

  select count(*) into staged_count
  from public.community_group_chat_attachments
  where uploader_id = 'a1000000-0000-4000-8000-000000000001';
  if staged_count <> 6 then
    raise exception 'expected six staged group attachments, got %', staged_count;
  end if;

  -- Deleting previews must not release the already-consumed upload quota.
  delete from public.community_group_chat_attachments
  where uploader_id = 'a1000000-0000-4000-8000-000000000001';

  select * into staged
  from public.stage_community_direct_message_attachment(
    'a3000000-0000-4000-8000-000000000001',
    'a1000000-0000-4000-8000-000000000001',
    'image/jpeg',
    2048
  );
  if not staged.rate_limited or staged.attachment_id is not null then
    raise exception 'deleted group previews incorrectly restored direct upload capacity';
  end if;

  select request_count into quota_count
  from public.community_media_upload_rate_limits
  where user_id = 'a1000000-0000-4000-8000-000000000001';
  if quota_count <> 7 then
    raise exception 'expected capped quota count of seven, got %', quota_count;
  end if;
end $$;

reset role;
set local role authenticated;
do $$
begin
  begin
    perform public.stage_community_group_chat_attachment(
      'a2000000-0000-4000-8000-000000000001',
      'a1000000-0000-4000-8000-000000000001',
      'image/jpeg',
      2048
    );
    raise exception 'authenticated role can execute the upload staging RPC';
  exception when insufficient_privilege then
    null;
  end;
end $$;

rollback;
