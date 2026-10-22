-- Example data for local development only: the five Mysuru cafes from
-- docs/customer-mock.html. Coordinates are approximate.

insert into public.cities (name, active, sort, lat, lng) values
  ('Mysuru',    true,  0, 12.2958, 76.6394),
  ('Bengaluru', false, 1, 12.9716, 77.5946),
  ('Raipur',    false, 2, 21.2514, 81.6296),
  ('Bhilai',    false, 3, 21.1938, 81.3509),
  ('Jaipur',    false, 4, 26.9124, 75.7873)
on conflict (name) do nothing;

insert into public.cafes (id, slug, name, kind, area, city, lat, lng, brand_bg, brand_ink, brand_acc, brand_pat, listed) values
  ('00000000-0000-4000-8000-000000000001', 'agrahara-roasters', 'Agrahara Roasters', 'Cafe', 'Saraswathipuram',  'Mysuru', 12.3105, 76.6300, '#3b2418', '#f6e7d4', '#d9a066', 'rings',   true),
  ('00000000-0000-4000-8000-000000000002', 'kaapi-kutir',       'Kaapi Kutir',       'Cafe', 'Vijayanagar',      'Mysuru', 12.3290, 76.6100, '#1f4d3a', '#f3ecd9', '#e7b84a', 'stripes', true),
  ('00000000-0000-4000-8000-000000000003', 'crumb-and-co',      'Crumb & Co',        'Cafe', 'Kuvempunagar',     'Mysuru', 12.2900, 76.6250, '#f4e3c3', '#4a2c14', '#c8553d', 'dots',    true),
  ('00000000-0000-4000-8000-000000000004', 'chamundi-chai-bar', 'Chamundi Chai Bar', 'Cafe', 'Jayalakshmipuram', 'Mysuru', 12.3300, 76.6330, '#c2410c', '#fff4e6', '#ffd8a8', 'rings',   true),
  ('00000000-0000-4000-8000-000000000005', 'waffle-lane',       'Waffle Lane',       'Cafe', 'Gokulam',          'Mysuru', 12.3330, 76.6380, '#2b2f6b', '#ffe9f1', '#ff8fb3', 'grid',    true)
on conflict (id) do nothing;

insert into public.cafe_subscriptions (cafe_id, plan, status)
select id, 'starter', 'trialing' from public.cafes
on conflict (cafe_id) do nothing;

-- Every day: Agrahara 8–22, Kaapi 7–21:30, Crumb 9–23, Chai 7–20, Waffle 11–22.
insert into public.cafe_hours (cafe_id, weekday, opens, closes)
select c.id, d, h.opens, h.closes
from (values
  ('00000000-0000-4000-8000-000000000001'::uuid, '08:00'::time, '22:00'::time),
  ('00000000-0000-4000-8000-000000000002', '07:00', '21:30'),
  ('00000000-0000-4000-8000-000000000003', '09:00', '23:00'),
  ('00000000-0000-4000-8000-000000000004', '07:00', '20:00'),
  ('00000000-0000-4000-8000-000000000005', '11:00', '22:00')
) as h (cafe, opens, closes)
join public.cafes c on c.id = h.cafe
cross join generate_series(0, 6) as d
on conflict do nothing;

insert into public.offers (cafe_id, title, stamp_multiplier, members_only, daily_from, daily_to, ends_at) values
  ('00000000-0000-4000-8000-000000000001', 'Free pastry with any 2 coffees',   1, false, null,    null,    now() + interval '5 days'),
  ('00000000-0000-4000-8000-000000000002', 'Double stamps before 11 am',       2, true,  '07:00', '11:00', now() + interval '3 days'),
  ('00000000-0000-4000-8000-000000000003', 'Second slice at half price',       1, false, null,    null,    now() + interval '1 day'),
  ('00000000-0000-4000-8000-000000000004', 'Masala chai at ₹49 for members',   1, true,  null,    null,    now() + interval '7 days'),
  ('00000000-0000-4000-8000-000000000005', 'Free topping on your first visit', 1, false, null,    null,    null);
