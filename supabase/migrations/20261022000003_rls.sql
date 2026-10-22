-- Row level security. Default stance: nothing is readable or writable unless a
-- policy below says so. Stamp counts change only through the RPCs.

alter table public.profiles           enable row level security;
alter table public.special_days       enable row level security;
alter table public.push_tokens        enable row level security;
alter table public.cities             enable row level security;
alter table public.cafes              enable row level security;
alter table public.cafe_hours         enable row level security;
alter table public.cafe_staff         enable row level security;
alter table public.offers             enable row level security;
alter table public.saved_offers       enable row level security;
alter table public.cards              enable row level security;
alter table public.stamp_events       enable row level security;
alter table public.geo_alerts         enable row level security;
alter table public.cafe_subscriptions enable row level security;
alter table public.billing_events     enable row level security;

-- Supabase grants everything on public to anon/authenticated by default.
-- Start from nothing and grant only what the apps use.
revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;

-- ---------------------------------------------------------------- profiles

grant select on public.profiles to authenticated;
grant update (name, photo_path, birthday, email, diet, usual_order,
              notify_stamps, notify_offers, notify_treats, geo_alerts)
  on public.profiles to authenticated;

create policy profiles_own_read on public.profiles for select to authenticated
  using (id = auth.uid());
create policy profiles_own_update on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

grant select, insert, update, delete on public.special_days to authenticated;
create policy special_days_own on public.special_days for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Tokens are registered through register_push_token(), which also moves a
-- token that a previous account on the same phone left behind.
grant select, delete on public.push_tokens to authenticated;
create policy push_tokens_own on public.push_tokens for all to authenticated
  using (user_id = auth.uid());

create or replace function public.register_push_token(p_token text, p_app text, p_platform text)
returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  insert into public.push_tokens (token, user_id, app, platform)
  values (p_token, auth.uid(), p_app, p_platform)
  on conflict (token) do update
    set user_id = excluded.user_id, app = excluded.app,
        platform = excluded.platform, updated_at = now();
end $$;

-- ------------------------------------------------------- cafes (browsable
-- signed out: the Home and Map tabs work before sign-up)

grant select on public.cities to anon, authenticated;
create policy cities_read on public.cities for select to anon, authenticated using (true);

grant select on public.cafes to anon, authenticated;
grant update (name, kind, area, address, stamp_goal, reward_label,
              brand_bg, brand_ink, brand_acc, brand_pat, logo_path, photo_paths)
  on public.cafes to authenticated;
create policy cafes_read on public.cafes for select to anon, authenticated
  using (public.cafe_is_live(id) or public.is_cafe_staff(id));
create policy cafes_manage on public.cafes for update to authenticated
  using (public.is_cafe_staff(id, array['owner', 'manager']::public.staff_role[]))
  with check (public.is_cafe_staff(id, array['owner', 'manager']::public.staff_role[]));

grant select on public.cafe_hours to anon, authenticated;
grant insert, update, delete on public.cafe_hours to authenticated;
create policy cafe_hours_read on public.cafe_hours for select to anon, authenticated
  using (public.cafe_is_live(cafe_id) or public.is_cafe_staff(cafe_id));
create policy cafe_hours_manage on public.cafe_hours for all to authenticated
  using (public.is_cafe_staff(cafe_id, array['owner', 'manager']::public.staff_role[]))
  with check (public.is_cafe_staff(cafe_id, array['owner', 'manager']::public.staff_role[]));

grant select on public.offers to anon, authenticated;
grant insert, update, delete on public.offers to authenticated;
create policy offers_read on public.offers for select to anon, authenticated
  using ((active and public.cafe_is_live(cafe_id) and (ends_at is null or ends_at > now()))
         or public.is_cafe_staff(cafe_id));
create policy offers_manage on public.offers for all to authenticated
  using (public.is_cafe_staff(cafe_id, array['owner', 'manager']::public.staff_role[]))
  with check (public.is_cafe_staff(cafe_id, array['owner', 'manager']::public.staff_role[]));

grant select, insert, delete on public.saved_offers to authenticated;
create policy saved_offers_own on public.saved_offers for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Staff see the team of cafes they belong to; owners add and remove people.
grant select, insert, update, delete on public.cafe_staff to authenticated;
create policy cafe_staff_read on public.cafe_staff for select to authenticated
  using (user_id = auth.uid() or public.is_cafe_staff(cafe_id));
create policy cafe_staff_manage on public.cafe_staff for all to authenticated
  using (public.is_cafe_staff(cafe_id, array['owner']::public.staff_role[]))
  with check (public.is_cafe_staff(cafe_id, array['owner']::public.staff_role[]));

-- ------------------------------------------------------------------- cards

-- Customers read their own cards; staff read cards at their cafe. Customers
-- can change only the offers switch and wallet order, and can leave a cafe.
grant select, delete on public.cards to authenticated;
grant update (offers_opt_in, wallet_pos) on public.cards to authenticated;
create policy cards_read on public.cards for select to authenticated
  using (user_id = auth.uid() or public.is_cafe_staff(cafe_id));
create policy cards_own_update on public.cards for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy cards_own_delete on public.cards for delete to authenticated
  using (user_id = auth.uid());

grant select on public.stamp_events to authenticated;
create policy stamp_events_read on public.stamp_events for select to authenticated
  using (exists (
    select 1 from public.cards k
    where k.id = card_id and (k.user_id = auth.uid() or public.is_cafe_staff(k.cafe_id))
  ));

grant select on public.geo_alerts to authenticated;
create policy geo_alerts_own on public.geo_alerts for select to authenticated
  using (user_id = auth.uid());

-- ----------------------------------------------------------------- billing

grant select on public.cafe_subscriptions to authenticated;
create policy subscriptions_owner on public.cafe_subscriptions for select to authenticated
  using (public.is_cafe_staff(cafe_id, array['owner', 'manager']::public.staff_role[]));
-- billing_events: service role only, no policies.

-- --------------------------------------------------------------- functions

revoke execute on all functions in schema public from public, anon, authenticated;
alter default privileges in schema public revoke execute on functions from public, anon, authenticated;

grant execute on function public.local_today() to anon, authenticated;
grant execute on function public.distance_m(float8, float8, float8, float8) to anon, authenticated;
grant execute on function public.is_cafe_staff(uuid, public.staff_role[]) to anon, authenticated;
grant execute on function public.cafe_is_live(uuid) to anon, authenticated;
grant execute on function public.cafe_open_now(uuid) to anon, authenticated;
grant execute on function public.nearby_cafes(float8, float8, int, int) to anon, authenticated;
grant execute on function public.join_cafe(uuid, boolean) to authenticated;
grant execute on function public.record_geo_alert(uuid) to authenticated;
grant execute on function public.register_push_token(text, text, text) to authenticated;
grant execute on function public.add_stamps(text, int) to authenticated;
grant execute on function public.redeem_reward(text) to authenticated;
grant execute on function public.lookup_card(text) to authenticated;
grant execute on function public.cafe_members(uuid) to authenticated;
grant execute on function public.delete_my_account() to authenticated;
