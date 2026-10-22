# customer_app

The Cafe Loyalty customer app (Flutter, Android and iOS). It follows
`docs/customer-mock.html`: Home | Map | Wallet with a floating pill nav, and Profile
from the avatar.

## Run it

**Demo mode** needs no backend. It uses the mock's five Mysuru cafes, puts you in
Saraswathipuram, accepts any 6-digit code, and adds the mock's "walk past a cafe"
button to try nearby alerts:

```sh
flutter run                        # phone or emulator
flutter run -d chrome              # quick look in a browser
```

**Against Supabase:**

```sh
flutter run \
  --dart-define=SUPABASE_URL=https://<project>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<publishable key> \
  --dart-define=MAP_TILE_URL='https://api.maptiler.com/maps/streets-v2/{z}/{x}/{y}.png?key=<key>' \
  --dart-define=MAP_TILE_URL_DARK='https://api.maptiler.com/maps/streets-v2-dark/{z}/{x}/{y}.png?key=<key>'
```

| Setting | What it's for |
| --- | --- |
| `SUPABASE_URL`, `SUPABASE_ANON_KEY` | Backend. Leave out for demo mode. |
| `MAP_TILE_URL`, `MAP_TILE_URL_DARK` | OpenStreetMap tiles. The default is tile.openstreetmap.org, which is fine for development but [not allowed for app traffic](https://operations.osmfoundation.org/policies/tiles/). Use a provider such as MapTiler or Stadia for release. Without a dark URL, dark mode recolours the light tiles. |
| `MAP_ATTRIBUTION` | Attribution text for your tile provider. |
| `ROUTING_URL` | Optional OSRM-compatible server for walking routes. Without it, Direction draws a straight line and estimates the walk. |
| `HELP_URL`, `SUPPORT_EMAIL`, `TERMS_URL` | Help rows in Profile. |

## Backend setup

- **Phone OTP:** in Supabase, Authentication → Providers → Phone, connect an SMS
  provider (Twilio, MessageBird, Vonage or Textlocal). The name typed at sign-up goes in
  the user metadata and becomes the profile name.
- **Schema:** apply `../supabase/migrations` (`supabase db push`).
- **Push (FCM):** run `flutterfire configure` to add `google-services.json` and
  `GoogleService-Info.plist`. Without them the app runs without push. The app registers
  its FCM installation with `register_push_token`.

## Nearby alerts

The app registers OS geofences (150 m) around the 20 nearest partner cafes; 20 is the
iOS limit. When the customer walks into one, the OS wakes the app, even when it's closed:

- App open: the in-app popup, as in the mock.
- App closed: a notification. Tapping it opens the same popup.

Either way the app first asks the server (`record_geo_alert`), which allows at most
2 popups a day, never the same cafe twice in a day, and none when the customer has
alerts off. This needs location access set to "Always", which the app asks for when
alerts are switched on.

## Checks

```sh
flutter analyze
flutter test
```

`test/app_test.dart` drives the real screens on demo data: signed-out Home, sign-up with
OTP, joining a cafe from the map card, the wallet and profile.

## Layout

```
lib/config.dart            --dart-define settings
lib/theme.dart             colour tokens and type from the mock
lib/data/                  models, Repository, Supabase and demo implementations
lib/state/app_state.dart   app state (tab, selection, cards, profile, location)
lib/services/              location, nearby alerts (geofences), push
lib/ui/                    shell (header + nav), screens, sheets, brand card art
```
