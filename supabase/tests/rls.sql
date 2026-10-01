
begin;
select set_config('test.alice',gen_random_uuid()::text,true);
select set_config('test.bob',gen_random_uuid()::text,true);
select set_config('test.mallory',gen_random_uuid()::text,true);
insert into auth.users(id,email) values
 (current_setting('test.alice')::uuid,'rls-alice-'||current_setting('test.alice')||'@example.invalid'),
 (current_setting('test.bob')::uuid,'rls-bob-'||current_setting('test.bob')||'@example.invalid'),
 (current_setting('test.mallory')::uuid,'rls-mallory-'||current_setting('test.mallory')||'@example.invalid');
insert into public.profiles(id,name,style,verified) values
 (current_setting('test.alice')::uuid,'RLS Alice','food',true),
 (current_setting('test.bob')::uuid,'RLS Bob','food',true),
 (current_setting('test.mallory')::uuid,'RLS Mallory','food',false);
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.alice'),true);
do $$
declare trip uuid; connection uuid;
begin
 insert into public.trips(owner_id,title,country,city,start,"end",style)
 values(auth.uid(),'RLS Tokyo','Japan','Tokyo',current_date+30,current_date+35,'food') returning id into trip;
 perform set_config('test.trip',trip::text,true);
 begin
  update public.profiles set verified=true where id=auth.uid();
  raise exception 'FAIL: client can change verification';
 exception when insufficient_privilege then null; end;
 begin
  insert into public.trips(owner_id,title,country,city,start,"end",style)
  values(current_setting('test.bob')::uuid,'Spoof','Japan','Tokyo',current_date+30,current_date+35,'food');
  raise exception 'FAIL: client can spoof trip ownership';
 exception when insufficient_privilege then null; end;
 insert into public.connections(sender_id,recipient_id)
 values(auth.uid(),current_setting('test.bob')::uuid) returning id into connection;
 perform set_config('test.connection',connection::text,true);
 begin
  insert into public.messages(connection_id,sender_id,body) values(connection,auth.uid(),'Before consent');
  raise exception 'FAIL: message sent without consent';
 exception when insufficient_privilege then null; end;
 update public.connections set status='accepted' where id=connection;
 if found then raise exception 'FAIL: sender accepted own request'; end if;
end $$;
select set_config('request.jwt.claim.sub',current_setting('test.bob'),true);
do $$
declare matches jsonb; trip uuid;
begin
 insert into public.trips(owner_id,title,country,city,start,"end",style)
 values(auth.uid(),'RLS Tokyo second','Japan','Tokyo',current_date+32,current_date+38,'food') returning id into trip;
 matches:=public.find_travel_matches(trip,0);
 if jsonb_array_length(matches->'items')<>1 then raise exception 'FAIL: matching overlap'; end if;
 update public.connections set status='accepted' where id=current_setting('test.connection')::uuid;
 if not found then raise exception 'FAIL: recipient cannot accept'; end if;
 insert into public.messages(connection_id,sender_id,body)
 values(current_setting('test.connection')::uuid,auth.uid(),'Accepted message');
 if (select count(*) from public.messages where connection_id=current_setting('test.connection')::uuid)<>1 then
  raise exception 'FAIL: participant cannot read messages'; end if;
 delete from public.trips where id=current_setting('test.trip')::uuid;
 if found then raise exception 'FAIL: another user deleted a trip'; end if;
end $$;
select set_config('request.jwt.claim.sub',current_setting('test.mallory'),true);
do $$
begin
 if exists(select 1 from public.messages where connection_id=current_setting('test.connection')::uuid) then
  raise exception 'FAIL: unrelated user can read messages'; end if;
 if exists(select 1 from public.connections where id=current_setting('test.connection')::uuid) then
  raise exception 'FAIL: unrelated user can see connection'; end if;
 begin
  insert into public.connections(sender_id,recipient_id) values(auth.uid(),current_setting('test.alice')::uuid);
  raise exception 'FAIL: unverified user connected';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub',current_setting('test.alice'),true);
insert into public.blocks(user_id,blocked_id) values(auth.uid(),current_setting('test.bob')::uuid);
insert into public.reports(reporter_id,reported_id,reason)
 values(auth.uid(),current_setting('test.bob')::uuid,'Test report');
do $$
begin
 if exists(select 1 from public.messages where connection_id=current_setting('test.connection')::uuid) then
  raise exception 'FAIL: blocker still sees messages'; end if;
 if exists(select 1 from public.trips where owner_id=current_setting('test.bob')::uuid) then
  raise exception 'FAIL: blocker still sees blocked trips'; end if;
end $$;
select set_config('request.jwt.claim.sub',current_setting('test.bob'),true);
do $$
begin
 if exists(select 1 from public.trips where owner_id=current_setting('test.alice')::uuid) then
  raise exception 'FAIL: block is not bidirectional'; end if;
 if exists(select 1 from public.reports where reporter_id=current_setting('test.alice')::uuid) then
  raise exception 'FAIL: reported user can see private report'; end if;
 begin
  insert into public.messages(connection_id,sender_id,body)
  values(current_setting('test.connection')::uuid,auth.uid(),'Blocked message');
  raise exception 'FAIL: blocked message sent';
 exception when insufficient_privilege then null; end;
end $$;
set local role anon;
select set_config('request.jwt.claim.sub','',true);
do $$
begin
 if (select count(*) from public.travel_styles)<>6 then raise exception 'FAIL: public catalog'; end if;
 begin
  perform * from public.profiles;
  raise exception 'FAIL: anonymous profile access';
 exception when insufficient_privilege then null; end;
 begin
  insert into public.travel_styles values('fake','Fake',7);
  raise exception 'FAIL: anonymous catalog modification';
 exception when insufficient_privilege then null; end;
end $$;
rollback;
select 'PASS: remote writes, matching, ownership, verification, consent, private chat, blocking, reports, anonymous access; all fixtures rolled back' as result;
