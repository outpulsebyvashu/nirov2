-- Cafe Loyalty: core tables.
-- Customers sign in with phone OTP (auth.users). Cafes are partner businesses that
-- pay for the card and marketing. Staff stamp cards by scanning the member QR.

create type public.staff_role as enum ('owner', 'manager', 'staff');
create type public.card_pattern as enum ('dots', 'stripes', 'rings', 'grid');
create type public.stamp_kind as enum ('join', 'stamp', 'redeem', 'adjust');
create type public.subscription_status as enum ('trialing', 'active', 'past_due', 'cancelled', 'expired');
create type public.diet as enum ('vegetarian', 'eggetarian', 'non_vegetarian', 'vegan');

create or replace function public.touch_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- ---------------------------------------------------------------- customers

create table public.profiles (
  id            uuid primary key references auth.users (id) on delete cascade,
  name          text not null check (char_length(btrim(name)) between 1 and 60),
  phone         text,                       -- copied from auth.users, E.164
  photo_path    text,                       -- avatars bucket: <uid>/<file>
  birthday      date check (birthday <= current_date),
  email         text check (email is null or email ~ '^[^\s@]+@[^\s@]+\.[^\s@]+$'),
  diet          public.diet,
  usual_order   text check (char_length(usual_order) <= 40),
  notify_stamps boolean not null default true,
  notify_offers boolean not null default true,
  notify_treats boolean not null default true,
  geo_alerts    boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create trigger profiles_touch before update on public.profiles
  for each row execute function public.touch_updated_at();

-- Birthday lives on profiles; these are the other special days (max 5).
create table public.special_days (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles (id) on delete cascade,
  label      text not null default 'Special day' check (char_length(btrim(label)) between 1 and 24),
  day        date not null,
  created_at timestamptz not null default now()
);
create index special_days_user on public.special_days (user_id);

create or replace function public.special_days_cap() returns trigger
language plpgsql as $$
begin
  if (select count(*) from public.special_days where user_id = new.user_id) >= 5 then
    raise exception 'special_days_limit' using hint = 'At most 5 special days';
  end if;
  return new;
end $$;
create trigger special_days_cap before insert on public.special_days
  for each row execute function public.special_days_cap();

create table public.push_tokens (
  token      text primary key,
  user_id    uuid not null references auth.users (id) on delete cascade,
  app        text not null check (app in ('customer', 'cafe', 'staff')),
  platform   text not null check (platform in ('android', 'ios', 'web')),
  updated_at timestamptz not null default now()
);
create index push_tokens_user on public.push_tokens (user_id);

-- -------------------------------------------------------------------- cafes

create table public.cities (
  name   text primary key,
  active boolean not null default false,       -- has partner cafes
  sort   int not null default 0
);

create table public.cafes (
  id           uuid primary key default gen_random_uuid(),
  slug         text not null unique check (slug ~ '^[a-z0-9-]{2,40}$'),
  name         text not null check (char_length(btrim(name)) between 1 and 60),
  kind         text not null default 'Cafe' check (kind in ('Cafe', 'Restaurant')),
  area         text not null,
  city         text not null references public.cities (name),
  address      text,
  lat          double precision not null check (lat between -90 and 90),
  lng          double precision not null check (lng between -180 and 180),
  -- loyalty rules
  stamp_goal   int not null default 8 check (stamp_goal between 4 and 20),
  reward_label text not null default 'a free filter coffee',
  -- brand: the card, sheet header and storefront art all use these
  brand_bg     text not null default '#2a2a2a' check (brand_bg ~ '^#[0-9a-fA-F]{6}$'),
  brand_ink    text not null default '#fafafa' check (brand_ink ~ '^#[0-9a-fA-F]{6}$'),
  brand_acc    text not null default '#ffd166' check (brand_acc ~ '^#[0-9a-fA-F]{6}$'),
  brand_pat    public.card_pattern not null default 'dots',
  logo_path    text,                          -- cafe-media bucket
  photo_paths  text[] not null default '{}',
  -- visible to customers only while listed and billing is in good standing
  listed       boolean not null default false,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index cafes_city on public.cafes (city) where listed;
create index cafes_latlng on public.cafes (lat, lng) where listed;
create trigger cafes_touch before update on public.cafes
  for each row execute function public.touch_updated_at();

-- Weekly hours; a cafe can have several rows per weekday (split shifts).
-- weekday: 0 = Sunday … 6 = Saturday, times are local (Asia/Kolkata).
create table public.cafe_hours (
  cafe_id uuid not null references public.cafes (id) on delete cascade,
  weekday smallint not null check (weekday between 0 and 6),
  opens   time not null,
  closes  time not null check (closes > opens),
  primary key (cafe_id, weekday, opens)
);

create table public.cafe_staff (
  cafe_id    uuid not null references public.cafes (id) on delete cascade,
  user_id    uuid not null references auth.users (id) on delete cascade,
  role       public.staff_role not null default 'staff',
  created_at timestamptz not null default now(),
  primary key (cafe_id, user_id)
);
create index cafe_staff_user on public.cafe_staff (user_id);

create table public.offers (
  id         uuid primary key default gen_random_uuid(),
  cafe_id    uuid not null references public.cafes (id) on delete cascade,
  title      text not null check (char_length(btrim(title)) between 1 and 80),
  details    text,
  -- multiplies stamps added while the offer runs (e.g. "double stamps before 11 am")
  stamp_multiplier smallint not null default 1 check (stamp_multiplier between 1 and 3),
  members_only boolean not null default false,
  -- optional daily window in local time, e.g. 07:00–11:00 for "before 11 am"
  daily_from time,
  daily_to   time,
  starts_at  timestamptz not null default now(),
  ends_at    timestamptz,
  active     boolean not null default true,
  created_at timestamptz not null default now(),
  check (ends_at is null or ends_at > starts_at),
  check ((daily_from is null) = (daily_to is null) and (daily_to is null or daily_to > daily_from))
);
create index offers_cafe on public.offers (cafe_id) where active;

create table public.saved_offers (
  user_id    uuid not null references auth.users (id) on delete cascade,
  offer_id   uuid not null references public.offers (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, offer_id)
);

-- ------------------------------------------------------------ loyalty cards

-- One card per customer per cafe. member_code is what the QR encodes.
create table public.cards (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users (id) on delete cascade,
  cafe_id       uuid not null references public.cafes (id) on delete cascade,
  member_code   text not null unique check (member_code ~ '^[A-Z0-9]{4}-[A-Z0-9]{4}$'),
  stamps        int not null default 0 check (stamps >= 0),
  rewards_redeemed int not null default 0,
  offers_opt_in boolean not null default false,
  wallet_pos    int not null default 0,       -- customer's own ordering in the wallet
  joined_at     timestamptz not null default now(),
  last_visit_at timestamptz,
  unique (user_id, cafe_id)
);
create index cards_cafe on public.cards (cafe_id);

-- Append-only history shown on the card sheet ("+2 stamps (double day)").
create table public.stamp_events (
  id         bigint generated always as identity primary key,
  card_id    uuid not null references public.cards (id) on delete cascade,
  kind       public.stamp_kind not null,
  delta      int not null,
  note       text,
  staff_id   uuid references auth.users (id) on delete set null,
  offer_id   uuid references public.offers (id) on delete set null,
  created_at timestamptz not null default now()
);
create index stamp_events_card on public.stamp_events (card_id, created_at desc);

-- ------------------------------------------------------------ nearby alerts

-- One row per popup shown. The client asks record_geo_alert() before showing
-- one, which enforces the opt-in and the 2-a-day cap.
create table public.geo_alerts (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references auth.users (id) on delete cascade,
  cafe_id    uuid not null references public.cafes (id) on delete cascade,
  local_day  date not null,                   -- Asia/Kolkata calendar day
  created_at timestamptz not null default now()
);
create index geo_alerts_user_day on public.geo_alerts (user_id, local_day);

-- ------------------------------------------------------------------ billing

-- Written only by the Razorpay webhook (service role) in the Next.js app.
create table public.cafe_subscriptions (
  cafe_id              uuid primary key references public.cafes (id) on delete cascade,
  plan                 text not null,
  status               public.subscription_status not null default 'trialing',
  razorpay_customer_id text,
  razorpay_subscription_id text unique,
  current_period_end   timestamptz,
  updated_at           timestamptz not null default now()
);
create trigger cafe_subscriptions_touch before update on public.cafe_subscriptions
  for each row execute function public.touch_updated_at();

create table public.billing_events (
  id          bigint generated always as identity primary key,
  razorpay_event_id text unique,              -- idempotency for webhook retries
  cafe_id     uuid references public.cafes (id) on delete set null,
  type        text not null,
  payload     jsonb not null,
  received_at timestamptz not null default now()
);
