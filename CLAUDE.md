# Cafe Loyalty

Digital loyalty card + marketing for partner cafes. Cafes pay for the card and marketing.

Stack: Flutter (customer_app, cafe_app, staff_app), Supabase (Postgres + RLS, phone OTP),
Next.js, Cloudflare. FCM for push, Razorpay for billing.

Reference: docs/customer-mock.html is the approved customer-app design.
Open it in a browser to see the flow. Match its layout, spacing and behaviour.

Customer app tabs: Home | Map | Wallet, with Profile from the avatar.
Features in the mock:
- Signed-out greeting, sign-up with name, number and OTP, autofill
- Infinite map with a swipeable cafe card
- Wallet card carousel
- Cafe-branded cards
- Nearby alert popup, max 2 a day, through OS geofences
- Profile with photo, birthday and special days, theme switch

Build order: Supabase schema, then customer_app, then cafe_app, then staff_app.

## Supabase

- Migrations live in `supabase/migrations`, example data in `supabase/seed.sql`.
- Run `supabase/tests/run.sh` after any schema change. It applies everything to a
  throwaway local Postgres (with stubs for Supabase's `auth` and `storage`) and runs
  `supabase/tests/rls_test.sql`. Add a test for every new rule.
- Stamps, rewards, joining and nearby alerts change only through security-definer
  RPCs (`join_cafe`, `add_stamps`, `redeem_reward`, `record_geo_alert`). Clients never
  write `cards.stamps` or `stamp_events` directly.
- Customers' phone numbers never reach cafe or staff apps; they see first names only.
- A cafe is visible to customers only while `listed` and its subscription is
  trialing, active or past_due (`cafe_is_live`). Only the Razorpay webhook
  (service role) writes `cafe_subscriptions` and `billing_events`.
- Local times (opening hours, offer windows, the daily alert cap) are Asia/Kolkata.

## customer_app

- `flutter analyze` and `flutter test` must pass. Widget tests run on demo data
  (`DemoRepository`); add one for each new flow.
- With no `SUPABASE_URL` dart-define the app runs in demo mode on the mock's data.
  Keep `DemoRepository` behaving like the server (same caps and rules).
- Colours and type come from `lib/theme.dart`, which mirrors the mock's CSS tokens.
  Use `Palette.of(context)`, `ts()` and `heading()` rather than raw colours or styles.
- All backend access goes through `Repository`; screens never call Supabase directly.
- Code is formatted at 160 columns (`dart format -l 160`).
