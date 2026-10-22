-- Behaviour tests for the schema, RLS and RPCs. Run with supabase/tests/run.sh.
\set ON_ERROR_STOP on
set client_min_messages = warning;

create schema test;
grant usage on schema test to anon, authenticated;

create function test.ok(cond boolean, what text) returns void language plpgsql as $$
begin
  if cond is not true then raise exception 'FAIL: %', what; end if;
  raise notice 'ok - %', what;
end $$;

-- Runs sql and expects an error whose message matches pattern.
create function test.throws(sql text, pattern text, what text) returns void language plpgsql as $$
begin
  begin
    execute sql;
  exception when others then
    if sqlerrm ~* pattern then raise notice 'ok - %', what; return; end if;
    raise exception 'FAIL: % (wrong error: %)', what, sqlerrm;
  end;
  raise exception 'FAIL: % (no error)', what;
end $$;

create function test.as_user(uid uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(uid::text, ''), false)
$$;
grant execute on all functions in schema test to anon, authenticated;
set client_min_messages = notice;

-- ------------------------------------------------------------ fixtures
insert into auth.users (id, phone, raw_user_meta_data) values
  ('aaaaaaaa-0000-4000-8000-000000000001', '+919876543210', '{"name":"Vashudev"}'),
  ('aaaaaaaa-0000-4000-8000-000000000002', '+919876500000', '{"name":"Asha Rao"}'),
  ('bbbbbbbb-0000-4000-8000-000000000001', '+919800000001', '{"name":"Owner Agrahara"}'),
  ('bbbbbbbb-0000-4000-8000-000000000002', '+919800000002', '{"name":"Staff Agrahara"}'),
  ('bbbbbbbb-0000-4000-8000-000000000003', '+919800000003', '{"name":"Staff Kaapi"}');
insert into public.cafe_staff (cafe_id, user_id, role) values
  ('00000000-0000-4000-8000-000000000001', 'bbbbbbbb-0000-4000-8000-000000000001', 'owner'),
  ('00000000-0000-4000-8000-000000000001', 'bbbbbbbb-0000-4000-8000-000000000002', 'staff'),
  ('00000000-0000-4000-8000-000000000002', 'bbbbbbbb-0000-4000-8000-000000000003', 'staff');
-- an unlisted cafe that customers must not see
insert into public.cafes (id, slug, name, area, city, lat, lng, listed)
values ('00000000-0000-4000-8000-000000000099', 'hidden', 'Hidden Cafe', 'Gokulam', 'Mysuru', 12.33, 76.63, false);

select test.ok((select name from public.profiles where id = 'aaaaaaaa-0000-4000-8000-000000000001') = 'Vashudev',
               'sign-up creates a profile with the name from the OTP form');
select test.ok((select phone from public.profiles where id = 'aaaaaaaa-0000-4000-8000-000000000001') = '+919876543210',
               'profile phone copied from auth');

-- ------------------------------------------------------- signed out
set role anon;
select test.as_user(null);
select test.ok((select count(*) from public.cafes) = 5, 'signed out: sees the 5 listed cafes, not the unlisted one');
select test.ok((select count(*) from public.offers) = 5, 'signed out: sees live offers');
select test.ok((select name from public.nearby_cafes(12.3105, 76.6300, 5000) limit 1) = 'Agrahara Roasters',
               'nearby_cafes puts the closest cafe first');
select test.ok((select count(*) from public.nearby_cafes(12.3105, 76.6300, 100)) = 1, 'nearby_cafes respects the radius');
select test.throws($$select public.join_cafe('00000000-0000-4000-8000-000000000001')$$, 'permission denied',
                   'signed out: cannot join');
select test.throws($$select * from public.profiles$$, 'permission denied', 'signed out: cannot read profiles');
reset role;

-- --------------------------------------------------------- customer
set role authenticated;
select test.as_user('aaaaaaaa-0000-4000-8000-000000000001');

select test.ok((select count(*) from public.profiles) = 1, 'customer sees only their own profile');
update public.profiles set birthday = '1995-10-23', email = 'v@example.com' where id = auth.uid();
select test.throws($$update public.profiles set phone = '+910000000000' where id = auth.uid()$$, 'permission denied',
                   'customer cannot change their verified phone');

select test.ok((select stamps from public.join_cafe('00000000-0000-4000-8000-000000000001', true)) = 0, 'join_cafe creates a card');
select test.ok((select member_code ~ '^[A-Z0-9]{4}-[A-Z0-9]{4}$' from public.cards limit 1), 'member code has the XXXX-XXXX shape');
select test.ok((select count(*) from public.join_cafe('00000000-0000-4000-8000-000000000001')) = 1
               and (select count(*) from public.cards) = 1, 'joining twice returns the same card');
select public.join_cafe('00000000-0000-4000-8000-000000000002');
select test.ok((select array_agg(wallet_pos order by wallet_pos) from public.cards) = '{0,1}', 'new cards go to the back of the wallet');
select test.throws($$select public.join_cafe('00000000-0000-4000-8000-000000000099')$$, 'cafe_unavailable',
                   'cannot join an unlisted cafe');

select test.throws($$update public.cards set stamps = 8$$, 'permission denied', 'customer cannot edit stamps');
select test.throws($$insert into public.stamp_events (card_id, kind, delta) select id, 'stamp', 5 from public.cards$$,
                   'permission denied', 'customer cannot write stamp history');
update public.cards set offers_opt_in = false where cafe_id = '00000000-0000-4000-8000-000000000001';
select test.ok(not (select offers_opt_in from public.cards where cafe_id = '00000000-0000-4000-8000-000000000001'),
               'customer can switch offers off per cafe');
select test.throws($$select public.add_stamps((select member_code from public.cards limit 1))$$, 'not_staff',
                   'customer cannot stamp their own card');

-- special days: max 5
insert into public.special_days (user_id, label, day)
select auth.uid(), 'Day ' || g, date '2020-01-01' + g from generate_series(1, 5) g;
select test.throws($$insert into public.special_days (user_id, day) values (auth.uid(), '2020-02-02')$$,
                   'special_days_limit', 'at most 5 special days');
select test.throws($$insert into public.special_days (user_id, day) values ('aaaaaaaa-0000-4000-8000-000000000002', '2020-02-02')$$,
                   'row-level security', 'cannot add special days for someone else');

-- second customer can't see the first one's data
select test.as_user('aaaaaaaa-0000-4000-8000-000000000002');
select test.ok((select count(*) from public.cards) = 0, 'other customers cannot see my cards');
select test.ok((select count(*) from public.profiles) = 1, 'other customers cannot see my profile');
select test.ok((select count(*) from public.stamp_events) = 0, 'other customers cannot see my history');
select public.join_cafe('00000000-0000-4000-8000-000000000002');
reset role;

-- -------------------------------------------------------------- staff
create temp table codes as
select p.name, k.cafe_id, k.member_code from public.cards k join public.profiles p on p.id = k.user_id;
grant select on codes to authenticated;

set role authenticated;
select test.as_user('bbbbbbbb-0000-4000-8000-000000000002');   -- staff at Agrahara

select test.ok((select first_name from public.lookup_card(
                 (select member_code from codes where name = 'Vashudev' and cafe_id = '00000000-0000-4000-8000-000000000001'))) = 'Vashudev',
               'staff scan shows the first name');
select test.ok((select count(*) from public.lookup_card(
                 (select member_code from codes where name = 'Vashudev' and cafe_id = '00000000-0000-4000-8000-000000000002'))) = 0,
               'staff cannot look up cards at another cafe');
select test.throws($$select public.add_stamps((select member_code from codes where name = 'Vashudev' and cafe_id = '00000000-0000-4000-8000-000000000002'))$$,
                   'not_staff', 'staff cannot stamp cards at another cafe');
select test.ok((select count(*) from public.cards) = 1, 'staff see only their cafe''s cards');

select test.ok((select stamps from public.add_stamps(
                 (select member_code from codes where name = 'Vashudev' and cafe_id = '00000000-0000-4000-8000-000000000001'))) = 1,
               'staff add a stamp');
select test.ok((select stamps from public.add_stamps(
                 (select lower(member_code) from codes where name = 'Vashudev' and cafe_id = '00000000-0000-4000-8000-000000000001'), 5)) = 6,
               'member code is case-insensitive, 5 at once');
select test.ok((select stamps from public.add_stamps(
                 (select member_code from codes where name = 'Vashudev' and cafe_id = '00000000-0000-4000-8000-000000000001'), 5)) = 8,
               'stamps stop at the goal');
select test.throws($$select public.add_stamps((select member_code from codes where name = 'Vashudev' and cafe_id = '00000000-0000-4000-8000-000000000001'))$$,
                   'reward_pending', 'no stamps past the goal until the reward is redeemed');
select test.throws($$select public.add_stamps((select member_code from codes where name = 'Vashudev' and cafe_id = '00000000-0000-4000-8000-000000000001'), 9)$$,
                   'invalid_count', 'stamp count is bounded');
select test.ok((select stamps = 0 and rewards_redeemed = 1 from public.redeem_reward(
                 (select member_code from codes where name = 'Vashudev' and cafe_id = '00000000-0000-4000-8000-000000000001'))),
               'redeem resets the card');
select test.throws($$select public.redeem_reward((select member_code from codes where name = 'Vashudev' and cafe_id = '00000000-0000-4000-8000-000000000001'))$$,
                   'reward_not_ready', 'cannot redeem an empty card');
select test.throws($$select * from public.cafe_members('00000000-0000-4000-8000-000000000001')$$, 'not_allowed',
                   'plain staff cannot export the member list');
select test.throws($$update public.cafes set listed = true where id = '00000000-0000-4000-8000-000000000001'$$, 'permission denied',
                   'cafes cannot list themselves (billing decides)');

-- Kaapi Kutir runs "double stamps before 11 am". Pin the window so the
-- tests don't depend on the clock: first outside it, then inside it.
reset role;
update public.offers set
  daily_from = case when (now() at time zone 'Asia/Kolkata')::time < '12:00' then '13:00'::time else '01:00'::time end,
  daily_to   = case when (now() at time zone 'Asia/Kolkata')::time < '12:00' then '14:00'::time else '02:00'::time end
where cafe_id = '00000000-0000-4000-8000-000000000002' and stamp_multiplier = 2;
set role authenticated;
select test.as_user('bbbbbbbb-0000-4000-8000-000000000003');
select test.ok((select stamps from public.add_stamps(
                 (select member_code from codes where name = 'Asha Rao' and cafe_id = '00000000-0000-4000-8000-000000000002'))) = 1,
               'outside the offer''s daily window a stamp counts once');
reset role;
update public.offers set daily_from = null, daily_to = null
where cafe_id = '00000000-0000-4000-8000-000000000002' and stamp_multiplier = 2;
set role authenticated;
select test.as_user('bbbbbbbb-0000-4000-8000-000000000003');
select test.ok((select stamps from public.add_stamps(
                 (select member_code from codes where name = 'Asha Rao' and cafe_id = '00000000-0000-4000-8000-000000000002'))) = 3,
               'inside the window a double-stamps offer adds 2');
select test.ok((select note from public.stamp_events where kind = 'stamp' order by id desc limit 1) = '+2 stamps (offer)',
               'history notes the offer');

-- owner
select test.as_user('bbbbbbbb-0000-4000-8000-000000000001');
select test.ok((select count(*) from public.cafe_members('00000000-0000-4000-8000-000000000001')) = 1, 'owner sees their members');
select test.ok((select not offers_opt_in and birthday_md = '10-23' from public.cafe_members('00000000-0000-4000-8000-000000000001')),
               'member list respects the offers switch and shows birthday as day-month');
update public.cafes set brand_bg = '#111111' where id = '00000000-0000-4000-8000-000000000001';
select test.ok((select brand_bg from public.cafes where id = '00000000-0000-4000-8000-000000000001') = '#111111', 'owner can restyle the card');
update public.cafes set brand_bg = '#222222' where id = '00000000-0000-4000-8000-000000000002';
select test.ok((select count(*) from public.cafes where brand_bg = '#222222') = 0, 'owner cannot restyle another cafe');
insert into public.offers (cafe_id, title) values ('00000000-0000-4000-8000-000000000001', 'Owner offer');
select test.throws($$insert into public.offers (cafe_id, title) values ('00000000-0000-4000-8000-000000000002', 'Sneaky')$$,
                   'row-level security', 'owner cannot post offers for another cafe');
reset role;

-- ------------------------------------------------------- nearby alerts
set role authenticated;
select test.as_user('aaaaaaaa-0000-4000-8000-000000000001');
select test.ok(public.record_geo_alert('00000000-0000-4000-8000-000000000001'), 'first nearby alert of the day is allowed');
select test.ok(not public.record_geo_alert('00000000-0000-4000-8000-000000000001'), 'same cafe does not alert twice a day');
select test.ok(public.record_geo_alert('00000000-0000-4000-8000-000000000002'), 'second alert is allowed');
select test.ok(not public.record_geo_alert('00000000-0000-4000-8000-000000000003'), 'third alert is blocked (2 a day)');
select test.as_user('aaaaaaaa-0000-4000-8000-000000000002');
update public.profiles set geo_alerts = false where id = auth.uid();
select test.ok(not public.record_geo_alert('00000000-0000-4000-8000-000000000001'), 'no alerts when switched off');
reset role;

-- ------------------------------------------------------------- storage
set role authenticated;
select test.as_user('aaaaaaaa-0000-4000-8000-000000000001');
insert into storage.objects (bucket_id, name) values ('avatars', 'aaaaaaaa-0000-4000-8000-000000000001/me.jpg');
select test.throws($$insert into storage.objects (bucket_id, name) values ('avatars', 'aaaaaaaa-0000-4000-8000-000000000002/me.jpg')$$,
                   'row-level security', 'cannot upload into another user''s avatar folder');
select test.throws($$insert into storage.objects (bucket_id, name) values ('cafe-media', '00000000-0000-4000-8000-000000000001/logo.png')$$,
                   'row-level security', 'customers cannot upload cafe media');
select test.throws($$insert into storage.objects (bucket_id, name) values ('cafe-media', 'not-a-uuid/logo.png')$$,
                   'row-level security', 'malformed cafe folder is rejected, not an error');
select test.as_user('bbbbbbbb-0000-4000-8000-000000000001');
insert into storage.objects (bucket_id, name) values ('cafe-media', '00000000-0000-4000-8000-000000000001/logo.png');
select test.ok(true, 'owner uploads cafe media');
reset role;

-- ------------------------------------------------------------ push tokens
set role authenticated;
select test.as_user('aaaaaaaa-0000-4000-8000-000000000001');
select public.register_push_token('tok-1', 'customer', 'android');
select test.as_user('aaaaaaaa-0000-4000-8000-000000000002');
select public.register_push_token('tok-1', 'customer', 'android');
select test.ok((select count(*) from public.push_tokens) = 1, 'a shared phone''s token moves to the new account');
select test.as_user('aaaaaaaa-0000-4000-8000-000000000001');
select test.ok((select count(*) from public.push_tokens) = 0, 'old account no longer receives pushes');
reset role;

-- ----------------------------------------------------------- delete data
set role authenticated;
select test.as_user('aaaaaaaa-0000-4000-8000-000000000001');
select public.delete_my_account();
reset role;
select test.ok(not exists (select 1 from public.profiles where id = 'aaaaaaaa-0000-4000-8000-000000000001')
               and not exists (select 1 from public.cards where user_id = 'aaaaaaaa-0000-4000-8000-000000000001')
               and not exists (select 1 from public.special_days where user_id = 'aaaaaaaa-0000-4000-8000-000000000001'),
               'delete my data removes profile, cards and special days');

\echo 'ALL TESTS PASSED'
