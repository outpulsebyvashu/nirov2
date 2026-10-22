# Cafe Loyalty

Digital loyalty cards and marketing for partner cafes. See `CLAUDE.md` for the brief
and `docs/customer-mock.html` for the approved customer-app design.

## Layout

```
docs/customer-mock.html   approved customer-app design (open in a browser)
supabase/migrations/      schema, RPCs, row level security, storage buckets
supabase/seed.sql         example Mysuru cafes from the mock (local dev only)
supabase/tests/           local test harness for the schema and RLS
customer_app/             Flutter customer app (see its README)
```

Coming next, in order: `cafe_app/`, `staff_app/` (Flutter), then the Next.js site with
the Razorpay webhook.

## Data model

| Table | What it holds |
| --- | --- |
| `profiles` | Customer name, phone, photo, birthday, email, food preference, usual order, notification and nearby-alert switches |
| `special_days` | Up to 5 extra dates per customer (anniversaries etc.) |
| `cafes`, `cafe_hours` | Partner cafes, location, loyalty rules (stamp goal, reward), brand colours and card pattern, weekly hours |
| `cafe_staff` | Who works at which cafe, as owner, manager or staff |
| `offers`, `saved_offers` | Cafe offers, optional stamp multiplier and daily time window; offers a customer saved |
| `cards`, `stamp_events` | One loyalty card per customer per cafe with its member code (the QR), and the stamp history |
| `geo_alerts` | Nearby popups shown, for the 2-a-day cap |
| `push_tokens` | FCM tokens per device and app |
| `cafe_subscriptions`, `billing_events` | Razorpay billing state, written by the webhook only |

## RPCs

| Function | Who | Does |
| --- | --- | --- |
| `nearby_cafes(lat, lng, radius_m, limit)` | anyone | Live cafes nearest first, with brand and open-now |
| `join_cafe(cafe_id, offers_opt_in)` | customer | Creates the card (idempotent) |
| `record_geo_alert(cafe_id)` | customer | Call when an OS geofence fires; `true` means show the popup |
| `register_push_token(token, app, platform)` | signed in | Saves an FCM token, moving it off any previous account |
| `export_my_data()` | customer | Everything held about the customer, as JSON ("Download my data") |
| `delete_my_account()` | customer | Deletes the account and everything attached |
| `lookup_card(member_code)` | staff | What the scanner shows: first name, stamps, goal |
| `add_stamps(member_code, count)` | staff | Adds stamps, applying any running multiplier offer, stops at the goal |
| `redeem_reward(member_code)` | staff | Uses a full card's reward |
| `cafe_members(cafe_id)` | owner, manager | Member list for marketing; respects opt-outs, birthday as day-month only |

## Testing the schema

```sh
supabase/tests/run.sh
```

Needs Postgres 15+ binaries. It starts a temporary server, applies the stubs,
migrations and seed, runs the tests, and removes the server.

To apply to a Supabase project: `supabase link` then `supabase db push`.
