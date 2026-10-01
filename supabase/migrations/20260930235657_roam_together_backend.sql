
create schema if not exists roam_private;
revoke all on schema roam_private from public, anon;
grant usage on schema roam_private to authenticated;

create table public.travel_styles (
  id text primary key, label text not null, position integer not null
);
insert into public.travel_styles values
 ('solo','Solo & independent',1),('chill','Beach & relaxation',2),
 ('adventure','Adventure & outdoors',3),('luxury','Luxury travel',4),
 ('budget','Budget & backpacking',5),('food','Food & culture',6);
alter table public.travel_styles enable row level security;
grant select on public.travel_styles to anon, authenticated;
create policy styles_read on public.travel_styles for select to anon, authenticated using (true);

create table public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 name text not null check(length(trim(name)) between 1 and 80),
 bio text not null default '' check(length(bio)<=1000),
 style text not null default 'solo' references public.travel_styles(id),
 verified boolean not null default false,
 created_at timestamptz not null default now()
);
create table public.trips (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references public.profiles(id) on delete cascade,
 title text not null check(length(trim(title)) between 1 and 120),
 country text not null check(length(trim(country)) between 1 and 80),
 city text not null check(length(trim(city)) between 1 and 80),
 start date not null, "end" date not null check("end">=start),
 style text not null references public.travel_styles(id),
 description text not null default '' check(length(description)<=2000),
 created_at timestamptz not null default now()
);
create table public.connections (
 id uuid primary key default gen_random_uuid(),
 sender_id uuid not null references public.profiles(id) on delete cascade,
 recipient_id uuid not null references public.profiles(id) on delete cascade,
 status text not null default 'pending' check(status in ('pending','accepted','declined')),
 created_at timestamptz not null default now(),
 check(sender_id<>recipient_id)
);
create unique index connections_pair on public.connections(least(sender_id,recipient_id),greatest(sender_id,recipient_id));
create table public.messages (
 id bigint generated always as identity primary key,
 connection_id uuid not null references public.connections(id) on delete cascade,
 sender_id uuid not null references public.profiles(id) on delete cascade,
 body text not null check(length(trim(body)) between 1 and 4000),
 created_at timestamptz not null default now()
);
create table public.blocks (
 user_id uuid not null references public.profiles(id) on delete cascade,
 blocked_id uuid not null references public.profiles(id) on delete cascade,
 primary key(user_id,blocked_id), check(user_id<>blocked_id)
);
create table public.reports (
 id uuid primary key default gen_random_uuid(),
 reporter_id uuid not null references public.profiles(id) on delete cascade,
 reported_id uuid not null references public.profiles(id) on delete cascade,
 reason text not null check(length(trim(reason)) between 1 and 2000),
 created_at timestamptz not null default now(), check(reporter_id<>reported_id)
);

-- Internal policy helpers avoid recursive RLS lookups. Every call needs a user.
-- They are outside the exposed public schema and cannot return private row data.
create function roam_private.is_verified(who uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.profiles where id=who and verified)
$$;
create function roam_private.is_blocked(first_id uuid, second_id uuid) returns boolean
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or auth.uid() not in (first_id,second_id) then
   return true;
 end if;
 return exists(select 1 from public.blocks where
  (user_id=first_id and blocked_id=second_id) or (user_id=second_id and blocked_id=first_id));
end $$;
create function roam_private.can_chat(cid uuid) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare c public.connections;
begin
 if auth.uid() is null then return false; end if;
 select * into c from public.connections where id=cid and auth.uid() in (sender_id,recipient_id);
 if not found then return false; end if;
 return c.status='accepted' and roam_private.is_verified(c.sender_id)
  and roam_private.is_verified(c.recipient_id)
  and not roam_private.is_blocked(c.sender_id,c.recipient_id);
end $$;
revoke all on all functions in schema roam_private from public, anon;
grant execute on all functions in schema roam_private to authenticated;

alter table public.profiles enable row level security;
alter table public.trips enable row level security;
alter table public.connections enable row level security;
alter table public.messages enable row level security;
alter table public.blocks enable row level security;
alter table public.reports enable row level security;
revoke all on public.profiles, public.trips, public.connections, public.messages, public.blocks, public.reports from anon, authenticated;
grant select on public.profiles, public.trips, public.connections, public.messages, public.blocks, public.reports to authenticated;
grant insert(id,name,bio,style) on public.profiles to authenticated;
grant update(name,bio,style) on public.profiles to authenticated;
grant insert(owner_id,title,country,city,start,"end",style,description) on public.trips to authenticated;
grant delete on public.trips to authenticated;
grant insert(sender_id,recipient_id) on public.connections to authenticated;
grant update(status) on public.connections to authenticated;
grant insert(connection_id,sender_id,body) on public.messages to authenticated;
grant usage on sequence public.messages_id_seq to authenticated;
grant insert(user_id,blocked_id) on public.blocks to authenticated;
grant insert(reporter_id,reported_id,reason) on public.reports to authenticated;

create policy profiles_read on public.profiles for select to authenticated using (
 id=(select auth.uid()) or (verified and not roam_private.is_blocked((select auth.uid()),id)));
create policy profiles_insert on public.profiles for insert to authenticated with check(id=(select auth.uid()) and not verified);
create policy profiles_update on public.profiles for update to authenticated
 using(id=(select auth.uid())) with check(id=(select auth.uid()));
create policy trips_read on public.trips for select to authenticated using (
 owner_id=(select auth.uid()) or (roam_private.is_verified(owner_id) and not roam_private.is_blocked((select auth.uid()),owner_id)));
create policy trips_insert on public.trips for insert to authenticated with check(owner_id=(select auth.uid()) and start>=current_date);
create policy trips_delete on public.trips for delete to authenticated using(owner_id=(select auth.uid()));
create policy connections_read on public.connections for select to authenticated using (
 (select auth.uid()) in(sender_id,recipient_id) and not roam_private.is_blocked(sender_id,recipient_id));
create policy connections_insert on public.connections for insert to authenticated with check (
 sender_id=(select auth.uid()) and status='pending' and roam_private.is_verified(sender_id)
 and roam_private.is_verified(recipient_id) and not roam_private.is_blocked(sender_id,recipient_id));
create policy connections_respond on public.connections for update to authenticated using (
 recipient_id=(select auth.uid()) and status='pending' and roam_private.is_verified(sender_id)
 and roam_private.is_verified(recipient_id) and not roam_private.is_blocked(sender_id,recipient_id))
 with check(recipient_id=(select auth.uid()) and status in('accepted','declined')
 and roam_private.is_verified(sender_id) and roam_private.is_verified(recipient_id)
 and not roam_private.is_blocked(sender_id,recipient_id));
create policy messages_read on public.messages for select to authenticated using(roam_private.can_chat(connection_id));
create policy messages_insert on public.messages for insert to authenticated with check (
 sender_id=(select auth.uid()) and roam_private.can_chat(connection_id));
create policy blocks_read on public.blocks for select to authenticated using(user_id=(select auth.uid()));
create policy blocks_insert on public.blocks for insert to authenticated with check(user_id=(select auth.uid()));
create policy reports_read on public.reports for select to authenticated using(reporter_id=(select auth.uid()));
create policy reports_insert on public.reports for insert to authenticated with check(reporter_id=(select auth.uid()));

create index profiles_style on public.profiles(style);
create index trips_owner on public.trips(owner_id);
create index trips_style on public.trips(style);
create index trips_destination on public.trips(lower(country),lower(city),start,"end");
create index connections_sender on public.connections(sender_id);
create index connections_recipient on public.connections(recipient_id);
create index messages_connection on public.messages(connection_id,id);
create index messages_sender on public.messages(sender_id);
create index blocks_target on public.blocks(blocked_id);
create index reports_reporter on public.reports(reporter_id);
create index reports_target on public.reports(reported_id);

create function public.find_travel_matches(trip_id uuid, page_offset integer default 0)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare own public.trips; result jsonb;
begin
 if auth.uid() is null or not roam_private.is_verified(auth.uid()) then
  raise insufficient_privilege using message='Verification is required to discover matches';
 end if;
 if page_offset<0 or page_offset>1000000000 then raise exception 'Invalid offset' using errcode='22023'; end if;
 select * into own from public.trips where id=trip_id and owner_id=auth.uid();
 if not found then raise exception 'Your trip was not found' using errcode='P0002'; end if;
 select coalesce(jsonb_agg(to_jsonb(r)),'[]'::jsonb) into result from (
  select t.*,p.name as owner_name,p.verified,(t.style=own.style) as same_style
  from public.trips t join public.profiles p on p.id=t.owner_id
  where t.owner_id<>auth.uid() and p.verified and lower(t.country)=lower(own.country)
   and lower(t.city)=lower(own.city) and t.start<=own."end" and t."end">=own.start and t."end">=current_date
  order by (t.style=own.style) desc,t.start,t.id limit 21 offset page_offset
 ) r;
 return jsonb_build_object('items',case when jsonb_array_length(result)>20 then result-20 else result end,
  'next_offset',case when jsonb_array_length(result)>20 then page_offset+20 else null end);
end $$;
revoke all on function public.find_travel_matches(uuid,integer) from public, anon;
grant execute on function public.find_travel_matches(uuid,integer) to authenticated;
