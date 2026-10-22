-- Helpers and RPCs. Anything that changes stamps goes through a
-- security-definer function, so customers can never edit their own count.

-- ------------------------------------------------------------------ helpers

create or replace function public.local_today() returns date
language sql stable as $$ select (now() at time zone 'Asia/Kolkata')::date $$;

create or replace function public.is_cafe_staff(p_cafe uuid, p_roles public.staff_role[] default null)
returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.cafe_staff s
    where s.cafe_id = p_cafe and s.user_id = auth.uid()
      and (p_roles is null or s.role = any (p_roles))
  )
$$;

-- A cafe is shown to customers while it is listed and its billing is current.
create or replace function public.cafe_is_live(p_cafe uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.cafes c
    join public.cafe_subscriptions s on s.cafe_id = c.id
    where c.id = p_cafe and c.listed
      and s.status in ('trialing', 'active', 'past_due')
  )
$$;

create or replace function public.new_member_code() returns text
language plpgsql volatile set search_path = '' as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';  -- no 0/O, 1/I
  code text;
  i int;
begin
  loop
    code := '';
    for i in 1..8 loop
      code := code || substr(alphabet, 1 + floor(random() * 32)::int, 1);
      if i = 4 then code := code || '-'; end if;
    end loop;
    exit when not exists (select 1 from public.cards where member_code = code);
  end loop;
  return code;
end $$;

-- Great-circle distance in metres.
create or replace function public.distance_m(lat1 float8, lng1 float8, lat2 float8, lng2 float8)
returns float8
language sql immutable as $$
  select 2 * 6371000 * asin(sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2) +
    cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2)
  ))
$$;

-- ------------------------------------------------- new user → profile row

-- The sign-up form sends the name as user metadata with the OTP request.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, name, phone)
  values (
    new.id,
    coalesce(nullif(btrim(new.raw_user_meta_data ->> 'name'), ''), 'Friend'),
    new.phone
  )
  on conflict (id) do nothing;
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- --------------------------------------------------------- customer RPCs

create or replace function public.cafe_open_now(p_cafe uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.cafe_hours h
    where h.cafe_id = p_cafe
      and h.weekday = extract(dow from now() at time zone 'Asia/Kolkata')
      and (now() at time zone 'Asia/Kolkata')::time >= h.opens
      and (now() at time zone 'Asia/Kolkata')::time <  h.closes
  )
$$;

-- Map and Home: live cafes near a point, nearest first.
create or replace function public.nearby_cafes(p_lat float8, p_lng float8, p_radius_m int default 5000, p_limit int default 50)
returns table (
  id uuid, slug text, name text, kind text, area text, city text, lat float8, lng float8,
  distance_m float8, stamp_goal int, reward_label text,
  brand_bg text, brand_ink text, brand_acc text, brand_pat public.card_pattern,
  logo_path text, photo_paths text[], is_open boolean
)
language sql stable security definer set search_path = '' as $$
  select c.id, c.slug, c.name, c.kind, c.area, c.city, c.lat, c.lng,
         public.distance_m(p_lat, p_lng, c.lat, c.lng) as distance_m,
         c.stamp_goal, c.reward_label, c.brand_bg, c.brand_ink, c.brand_acc, c.brand_pat,
         c.logo_path, c.photo_paths, public.cafe_open_now(c.id)
  from public.cafes c
  where public.cafe_is_live(c.id)
    -- cheap bounding box before the exact distance
    and c.lat between p_lat - p_radius_m / 111320.0 and p_lat + p_radius_m / 111320.0
    and c.lng between p_lng - p_radius_m / (111320.0 * cos(radians(p_lat)))
                  and p_lng + p_radius_m / (111320.0 * cos(radians(p_lat)))
    and public.distance_m(p_lat, p_lng, c.lat, c.lng) <= p_radius_m
  order by distance_m
  limit least(p_limit, 200)
$$;

-- "Join Loyalty". Idempotent: joining twice returns the existing card.
create or replace function public.join_cafe(p_cafe uuid, p_offers_opt_in boolean default false)
returns public.cards
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  card public.cards;
begin
  if uid is null then raise exception 'not_signed_in' using errcode = '28000'; end if;
  if not public.cafe_is_live(p_cafe) then raise exception 'cafe_unavailable'; end if;

  select * into card from public.cards where user_id = uid and cafe_id = p_cafe;
  if found then return card; end if;

  insert into public.cards (user_id, cafe_id, member_code, offers_opt_in, wallet_pos)
  values (uid, p_cafe, public.new_member_code(), coalesce(p_offers_opt_in, false),
          coalesce((select max(wallet_pos) + 1 from public.cards where user_id = uid), 0))
  returning * into card;

  insert into public.stamp_events (card_id, kind, delta, note)
  values (card.id, 'join', 0, 'Joined');
  return card;
end $$;

-- Ask before showing a nearby popup. Returns false when alerts are off,
-- the cafe was already shown today, or the daily cap (2) is used up.
create or replace function public.record_geo_alert(p_cafe uuid)
returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  today date := public.local_today();
begin
  if uid is null then return false; end if;
  if not coalesce((select geo_alerts from public.profiles where id = uid), false) then return false; end if;
  if not public.cafe_is_live(p_cafe) then return false; end if;

  -- serialise concurrent geofence events for the same user
  perform pg_advisory_xact_lock(hashtextextended(uid::text || today::text, 0));

  if exists (select 1 from public.geo_alerts where user_id = uid and local_day = today and cafe_id = p_cafe)
     or (select count(*) from public.geo_alerts where user_id = uid and local_day = today) >= 2 then
    return false;
  end if;

  insert into public.geo_alerts (user_id, cafe_id, local_day) values (uid, p_cafe, today);
  return true;
end $$;

-- ------------------------------------------------------------ staff RPCs

-- Staff scan the member QR and add stamps. A running stamp offer multiplies
-- the count. Returns the updated card.
create or replace function public.add_stamps(p_member_code text, p_count int default 1)
returns public.cards
language plpgsql security definer set search_path = '' as $$
declare
  card public.cards;
  goal int;
  mult int := 1;
  boost uuid;
  added int;
begin
  if p_count not between 1 and 5 then raise exception 'invalid_count'; end if;

  select * into card from public.cards where member_code = upper(btrim(p_member_code)) for update;
  if not found then raise exception 'card_not_found'; end if;
  if not public.is_cafe_staff(card.cafe_id) then raise exception 'not_staff' using errcode = '42501'; end if;

  select o.id, o.stamp_multiplier into boost, mult from public.offers o
  where o.cafe_id = card.cafe_id and o.active and o.stamp_multiplier > 1
    and now() >= o.starts_at and (o.ends_at is null or now() < o.ends_at)
    and (o.daily_from is null
         or (now() at time zone 'Asia/Kolkata')::time between o.daily_from and o.daily_to)
  order by o.stamp_multiplier desc limit 1;
  mult := coalesce(mult, 1);

  select stamp_goal into goal from public.cafes where id = card.cafe_id;
  -- stamps stop at the goal; the reward has to be redeemed before earning more
  added := least(p_count * mult, greatest(goal - card.stamps, 0));
  if added = 0 then raise exception 'reward_pending' using hint = 'Redeem the reward first'; end if;

  update public.cards set stamps = stamps + added, last_visit_at = now()
  where id = card.id returning * into card;

  insert into public.stamp_events (card_id, kind, delta, note, staff_id, offer_id)
  values (card.id, 'stamp', added,
          case when mult > 1 then '+' || added || ' stamps (offer)'
               when added = 1 then '+1 stamp' else '+' || added || ' stamps' end,
          auth.uid(), case when mult > 1 then boost end);
  return card;
end $$;

create or replace function public.redeem_reward(p_member_code text)
returns public.cards
language plpgsql security definer set search_path = '' as $$
declare
  card public.cards;
  goal int;
begin
  select * into card from public.cards where member_code = upper(btrim(p_member_code)) for update;
  if not found then raise exception 'card_not_found'; end if;
  if not public.is_cafe_staff(card.cafe_id) then raise exception 'not_staff' using errcode = '42501'; end if;

  select stamp_goal into goal from public.cafes where id = card.cafe_id;
  if card.stamps < goal then raise exception 'reward_not_ready'; end if;

  update public.cards set stamps = stamps - goal, rewards_redeemed = rewards_redeemed + 1, last_visit_at = now()
  where id = card.id returning * into card;

  insert into public.stamp_events (card_id, kind, delta, note, staff_id)
  values (card.id, 'redeem', -goal, 'Reward redeemed', auth.uid());
  return card;
end $$;

-- What staff see after scanning: no phone number, first name only.
create or replace function public.lookup_card(p_member_code text)
returns table (card_id uuid, cafe_id uuid, first_name text, stamps int, stamp_goal int,
               rewards_redeemed int, joined_at timestamptz, last_visit_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select k.id, k.cafe_id, split_part(p.name, ' ', 1), k.stamps, c.stamp_goal,
         k.rewards_redeemed, k.joined_at, k.last_visit_at
  from public.cards k
  join public.cafes c on c.id = k.cafe_id
  join public.profiles p on p.id = k.user_id
  where k.member_code = upper(btrim(p_member_code))
    and public.is_cafe_staff(k.cafe_id)
$$;

-- ------------------------------------------------------------ cafe owner

-- Members list for the cafe app. Birthday and special days only for
-- customers who allow treats, and only as day and month.
create or replace function public.cafe_members(p_cafe uuid)
returns table (card_id uuid, first_name text, stamps int, rewards_redeemed int,
               offers_opt_in boolean, joined_at timestamptz, last_visit_at timestamptz,
               birthday_md text)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_cafe_staff(p_cafe, array['owner', 'manager']::public.staff_role[]) then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  return query
  select k.id, split_part(p.name, ' ', 1), k.stamps, k.rewards_redeemed,
         k.offers_opt_in and p.notify_offers, k.joined_at, k.last_visit_at,
         case when p.notify_treats and p.birthday is not null then to_char(p.birthday, 'MM-DD') end
  from public.cards k join public.profiles p on p.id = k.user_id
  where k.cafe_id = p_cafe
  order by k.last_visit_at desc nulls last;
end $$;

-- "Delete my data": removes the auth user, which cascades to everything.
create or replace function public.delete_my_account() returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  delete from auth.users where id = auth.uid();
end $$;
