import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'data/demo_repository.dart';
import 'data/repository.dart';
import 'data/supabase_repository.dart';
import 'services/location_service.dart';
import 'services/nearby_alerts.dart';
import 'services/push.dart';
import 'state/app_state.dart';
import 'theme.dart';
import 'ui/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  Repository repo;
  LocationService location;
  if (Config.demo) {
    repo = DemoRepository();
    location = DemoLocationService();
  } else {
    await Supabase.initialize(url: Config.supabaseUrl, publishableKey: Config.supabaseAnonKey);
    repo = SupabaseRepository(Supabase.instance.client);
    location = LocationService();
  }
  await Push.init();

  final app = AppState(repo, prefs, location);
  final alerts = NearbyAlerts();
  runApp(CustomerApp(state: app, alerts: alerts));

  await alerts.init(onEnter: app.onGeofence, onTap: app.showNearby);
  NearbySync(app, alerts.sync, alerts.stop).attach();
  repo.authChanges.listen((uid) {
    if (uid != null) Push.register(repo, app.toast);
  });
  await app.start();
  if (app.signedIn) await Push.register(repo, app.toast);
}

class CustomerApp extends StatelessWidget {
  const CustomerApp({super.key, required this.state, required this.alerts});
  final AppState state;
  final NearbyAlerts alerts;

  /// Switching nearby alerts on asks for "Always" location access, which
  /// geofences need to work with the app closed.
  Future<void> _alertsChanged(bool on) async {
    if (on && !await state.location.hasAlways()) {
      if (!await state.location.requestAlways()) {
        state.toast('Allow location access “Always” in Settings for nearby alerts');
      }
    }
    await state.setPref('geo', on);
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) => MaterialApp(
          title: 'Cafe Loyalty',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: state.themeMode,
          home: Shell(onAlertsChanged: _alertsChanged),
        ),
      ),
    );
  }
}
