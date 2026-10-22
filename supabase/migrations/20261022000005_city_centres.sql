-- The location picker in the customer app moves the map to a city's centre.

alter table public.cities
  add column lat double precision check (lat between -90 and 90),
  add column lng double precision check (lng between -180 and 180);
