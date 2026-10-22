-- "Download my data" in the customer app, and live card updates: when staff
-- stamp a card, the open card sheet updates without a refresh.

create or replace function public.export_my_data() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'exported_at', now(),
    'profile', (select to_jsonb(p) from public.profiles p where p.id = auth.uid()),
    'special_days', coalesce((select jsonb_agg(jsonb_build_object('label', d.label, 'day', d.day))
                              from public.special_days d where d.user_id = auth.uid()), '[]'),
    'cards', coalesce((select jsonb_agg(jsonb_build_object(
                 'cafe', c.name, 'member_code', k.member_code, 'stamps', k.stamps,
                 'rewards_redeemed', k.rewards_redeemed, 'offers_opt_in', k.offers_opt_in,
                 'joined_at', k.joined_at,
                 'history', coalesce((select jsonb_agg(jsonb_build_object('at', e.created_at, 'kind', e.kind, 'delta', e.delta, 'note', e.note) order by e.created_at)
                                      from public.stamp_events e where e.card_id = k.id), '[]')))
               from public.cards k join public.cafes c on c.id = k.cafe_id
               where k.user_id = auth.uid()), '[]'),
    'saved_offers', coalesce((select jsonb_agg(o.title) from public.saved_offers s
                              join public.offers o on o.id = s.offer_id where s.user_id = auth.uid()), '[]'),
    'nearby_alerts', coalesce((select jsonb_agg(jsonb_build_object('cafe', c.name, 'at', g.created_at))
                               from public.geo_alerts g join public.cafes c on c.id = g.cafe_id
                               where g.user_id = auth.uid()), '[]')
  )
  where auth.uid() is not null
$$;
revoke execute on function public.export_my_data() from public, anon;
grant execute on function public.export_my_data() to authenticated;

alter publication supabase_realtime add table public.cards;
