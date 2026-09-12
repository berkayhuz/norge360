-- Run against a disposable migrated database as its owner. Everything rolls back.
begin;
insert into auth.users(id) values
 ('10000000-0000-4000-8000-000000000001'),
 ('10000000-0000-4000-8000-000000000002'),
 ('10000000-0000-4000-8000-000000000003');
insert into public.community_profiles(user_id, display_name, preferred_locale, norway_status, username) values
 ('10000000-0000-4000-8000-000000000001','Test One','en','resident','test_chat_one'),
 ('10000000-0000-4000-8000-000000000002','Test Two','en','resident','test_chat_two'),
 ('10000000-0000-4000-8000-000000000003','Test Three','en','resident','test_chat_three');
insert into public.community_conversations(id, participant_one_id, participant_two_id, requested_by_id, status) values
 ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000001','active');
insert into public.community_conversation_members(conversation_id,user_id,status) values
 ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','active'),
 ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002','active');
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
select public.update_community_conversation_preferences('20000000-0000-4000-8000-000000000001',false,false,'dots','purple');
select public.send_community_message('20000000-0000-4000-8000-000000000001',E'  \t\nHello   Norway!   ');
do $$ begin
 if (select body from public.community_messages limit 1) <> 'Hello Norway!' then raise exception 'whitespace normalization failed'; end if;
 if (select background_style from public.community_conversation_preferences limit 1) <> 'dots' then raise exception 'appearance save failed'; end if;
 if exists(select 1 from public.community_message_signals) then raise exception 'sender received recipient signal'; end if;
 begin
  perform public.update_community_conversation_preferences('20000000-0000-4000-8000-000000000001',false,false,'invalid','blue');
  raise exception 'invalid style accepted';
 exception when others then if sqlerrm = 'invalid style accepted' then raise; end if; end;
end $$;
-- A third party cannot read settings/signals or mutate another conversation.
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000003',true);
do $$ begin
 if exists(select 1 from public.community_conversation_preferences) then raise exception 'third party read preferences'; end if;
 if exists(select 1 from public.community_message_signals) then raise exception 'third party read signal'; end if;
 begin
  perform public.update_community_conversation_preferences('20000000-0000-4000-8000-000000000001',true,true,'plain','teal');
  raise exception 'third party changed preferences';
 exception when others then if sqlerrm = 'third party changed preferences' then raise; end if; end;
 begin
  perform public.send_community_message('20000000-0000-4000-8000-000000000001','unauthorized');
  raise exception 'third party sent message';
 exception when others then if sqlerrm = 'third party sent message' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',true);
do $$ begin
 if (select count(*) from public.community_message_signals) <> 1 then raise exception 'recipient signal missing'; end if;
 if exists(select 1 from public.community_conversation_preferences) then raise exception 'other member read private preference'; end if;
end $$;
reset role;
do $$ begin
 if exists(select 1 from public.community_notifications where type in ('direct_message','message_request')) then raise exception 'message activity persisted'; end if;
 if not public.can_deliver_community_message_signal((select id from public.community_message_signals limit 1)) then raise exception 'normal push suppressed'; end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',true);
select public.update_community_conversation_preferences('20000000-0000-4000-8000-000000000001',true,false,'plain','teal');
reset role;
do $$ begin
 if public.can_deliver_community_message_signal((select id from public.community_message_signals limit 1)) then raise exception 'muted push delivered'; end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',true);
select public.update_community_conversation_preferences('20000000-0000-4000-8000-000000000001',false,true,'plain','teal');
select public.update_community_message_read_receipts(true);
select public.mark_community_conversation_read('20000000-0000-4000-8000-000000000001');
do $$ begin
 if (select last_read_at from public.community_conversation_members where user_id=auth.uid()) is not null then raise exception 'restricted read state recorded'; end if;
 begin
  perform public.send_community_message('20000000-0000-4000-8000-000000000001','restricted reply');
  raise exception 'restricted sender replied';
 exception when others then if sqlerrm = 'restricted sender replied' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
select public.update_community_message_read_receipts(true);
select public.send_community_message('20000000-0000-4000-8000-000000000001','Incoming remains readable');
do $$ begin
 if exists(select 1 from public.get_community_message_read_receipt('20000000-0000-4000-8000-000000000001') where are_read_receipts_enabled or other_last_read_at is not null) then raise exception 'restriction leaked receipt'; end if;
end $$;
reset role;
do $$ begin
 if public.can_deliver_community_message_signal((select id from public.community_message_signals limit 1)) then raise exception 'restricted push delivered'; end if;
end $$;
-- Block in either direction prevents reads, writes and queued delivery.
insert into public.user_blocks(blocker_id,blocked_user_id) values ('10000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000001');
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
do $$ begin
 if exists(select 1 from public.community_messages) then raise exception 'blocked member read message'; end if;
 begin
  perform public.send_community_message('20000000-0000-4000-8000-000000000001','blocked reply');
  raise exception 'blocked sender replied';
 exception when others then if sqlerrm = 'blocked sender replied' then raise; end if; end;
end $$;
reset role;
do $$ begin
 if public.can_deliver_community_message_signal((select id from public.community_message_signals limit 1)) then raise exception 'blocked push delivered'; end if;
end $$;
update public.community_message_signals set expires_at=now()-interval '1 minute';
select public.prune_community_message_signals();
do $$ begin
 if exists(select 1 from public.community_message_signals) then raise exception 'expired transport rows retained'; end if;
 if (select count(*) from public.community_messages) <> 2 then raise exception 'transport cleanup removed messages'; end if;
end $$;
rollback;
