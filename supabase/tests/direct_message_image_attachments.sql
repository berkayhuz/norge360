-- Run against a disposable, fully migrated database as its owner.
-- This verifies that attachment authorization is enforced by the message RPC,
-- rather than trusting a client-supplied attachment or conversation ID.
begin;

insert into auth.users(id) values
 ('11000000-0000-4000-8000-000000000001'),
 ('11000000-0000-4000-8000-000000000002'),
 ('11000000-0000-4000-8000-000000000003');
insert into public.community_profiles(user_id, display_name, preferred_locale, norway_status, username) values
 ('11000000-0000-4000-8000-000000000001','Image One','en','resident','image_chat_one'),
 ('11000000-0000-4000-8000-000000000002','Image Two','en','resident','image_chat_two'),
 ('11000000-0000-4000-8000-000000000003','Image Three','en','resident','image_chat_three');
insert into public.community_conversations(id, participant_one_id, participant_two_id, requested_by_id, status) values
 ('22000000-0000-4000-8000-000000000001','11000000-0000-4000-8000-000000000001','11000000-0000-4000-8000-000000000002','11000000-0000-4000-8000-000000000001','active');
insert into public.community_conversation_members(conversation_id,user_id,status) values
 ('22000000-0000-4000-8000-000000000001','11000000-0000-4000-8000-000000000001','active'),
 ('22000000-0000-4000-8000-000000000001','11000000-0000-4000-8000-000000000002','active');
insert into public.community_direct_message_attachments(
 id, conversation_id, uploader_id, storage_reference, mime_type, byte_size,
 provider_asset_id, status, scan_status, reviewed_at
) values
 ('33000000-0000-4000-8000-000000000001','22000000-0000-4000-8000-000000000001','11000000-0000-4000-8000-000000000001',
  '22000000-0000-4000-8000-000000000001/11000000-0000-4000-8000-000000000001/33000000-0000-4000-8000-000000000001',
  'image/jpeg', 2048, 'private-image-one', 'ready', 'passed', now());

set local role authenticated;
select set_config('request.jwt.claim.sub','11000000-0000-4000-8000-000000000001',true);
select public.send_community_message_with_attachment(
 '22000000-0000-4000-8000-000000000001', '', '33000000-0000-4000-8000-000000000001'
);
do $$ begin
 if not exists (
   select 1 from public.list_community_conversation_messages('22000000-0000-4000-8000-000000000001')
   where attachment_id = '33000000-0000-4000-8000-000000000001'
     and attachment_mime_type = 'image/jpeg'
 ) then raise exception 'ready attachment was not delivered through the authorized message list'; end if;
 begin
   perform 1 from public.community_direct_message_attachments;
   raise exception 'client read private attachment rows';
 exception when insufficient_privilege then null;
 end;
end $$;

select set_config('request.jwt.claim.sub','11000000-0000-4000-8000-000000000003',true);
do $$ begin
 begin
   perform public.send_community_message_with_attachment(
     '22000000-0000-4000-8000-000000000001', '', '33000000-0000-4000-8000-000000000001'
   );
   raise exception 'third party attached a private image';
 exception when others then if sqlerrm = 'third party attached a private image' then raise; end if; end;
end $$;

reset role;
insert into public.user_blocks(blocker_id,blocked_user_id)
values ('11000000-0000-4000-8000-000000000002','11000000-0000-4000-8000-000000000001');
set local role authenticated;
select set_config('request.jwt.claim.sub','11000000-0000-4000-8000-000000000001',true);
do $$ begin
 begin
   perform * from public.list_community_conversation_messages('22000000-0000-4000-8000-000000000001');
   raise exception 'blocked member read an image message';
 exception when others then if sqlerrm = 'blocked member read an image message' then raise; end if; end;
end $$;

rollback;
