import 'dart:convert';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:native_geofence/native_geofence.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../data/models.dart';

/// Nearby alerts: the phone's OS watches a circle around each nearby partner
/// cafe and wakes the app when the customer walks into one, even when the app
/// is closed. The server decides whether a popup may be shown (max 2 a day).
class NearbyAlerts {
  /// About the distance the mock uses for its rings.
  static const radiusM = 150.0;

  /// iOS monitors at most 20 regions per app.
  static const maxFences = 20;

  static const _port = 'nearby-alerts';
  static const _cafesKey = 'geo-cafes';
  static final notifications = FlutterLocalNotificationsPlugin();
  static bool get supported => !kIsWeb && !Config.demo && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  final _rx = ReceivePort();

  /// Starts listening for fences while the app runs. [onEnter] gets a cafe id;
  /// [onTap] gets the cafe id of a nearby-alert notification the customer opened.
  Future<void> init({required void Function(String cafeId) onEnter, required void Function(String cafeId) onTap}) async {
    if (!supported) return;
    IsolateNameServer.removePortNameMapping(_port);
    IsolateNameServer.registerPortWithName(_rx.sendPort, _port);
    _rx.listen((m) => onEnter(m as String));

    await initNotifications(
      onTap: (r) {
        if (r.payload != null) onTap(r.payload!);
      },
    );
    final launch = await notifications.getNotificationAppLaunchDetails();
    final payload = launch?.notificationResponse?.payload;
    if (launch?.didNotificationLaunchApp == true && payload != null) onTap(payload);
    await NativeGeofenceManager.instance.initialize();
  }

  static Future<void> initNotifications({DidReceiveNotificationResponseCallback? onTap}) async {
    await notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
      ),
      onDidReceiveNotificationResponse: onTap,
    );
  }

  /// Watches the [cafes] nearest to the customer, replacing the old set.
  /// Call when alerts are switched on, after sign-in, and when the customer
  /// has moved far enough that the nearest cafes changed.
  Future<void> sync(List<Cafe> cafes, Map<String, String> offerByCafe) async {
    if (!supported) return;
    final watch = cafes.take(maxFences).toList();
    final prefs = await SharedPreferences.getInstance();
    // the background callback has no app state, so keep what the notification needs
    await prefs.setString(
      _cafesKey,
      jsonEncode({
        for (final c in watch) c.id: {'name': c.name, 'offer': offerByCafe[c.id]},
      }),
    );
    try {
      await NativeGeofenceManager.instance.removeAllGeofences();
      for (final c in watch) {
        await NativeGeofenceManager.instance.createGeofence(
          Geofence(
            id: c.id,
            location: Location(latitude: c.lat, longitude: c.lng),
            radiusMeters: radiusM,
            triggers: const {GeofenceEvent.enter},
            iosSettings: const IosGeofenceSettings(initialTrigger: false),
            androidSettings: const AndroidGeofenceSettings(initialTriggers: {}, notificationResponsiveness: Duration(minutes: 2)),
          ),
          onGeofenceEvent,
        );
      }
    } on NativeGeofenceException catch (e) {
      debugPrint('nearby alerts: ${e.code} ${e.message}');
    }
  }

  Future<void> stop() async {
    if (!supported) return;
    try {
      await NativeGeofenceManager.instance.removeAllGeofences();
    } on NativeGeofenceException catch (_) {}
  }
}

/// Runs in a background isolate when the OS reports a fence entry.
@pragma('vm:entry-point')
Future<void> onGeofenceEvent(GeofenceCallbackParams params) async {
  if (params.event != GeofenceEvent.enter) return;
  final ids = params.geofences.map((g) => g.id).toList();
  if (ids.isEmpty) return;

  // The app is open: let it ask the server and show the in-app popup.
  final port = IsolateNameServer.lookupPortByName(NearbyAlerts._port);
  if (port != null) {
    port.send(ids.first);
    return;
  }

  // The app is closed: ask the server ourselves and post a notification.
  final prefs = await SharedPreferences.getInstance();
  final cafes = jsonDecode(prefs.getString(NearbyAlerts._cafesKey) ?? '{}') as Map<String, dynamic>;
  await Supabase.initialize(url: Config.supabaseUrl, publishableKey: Config.supabaseAnonKey);
  final db = Supabase.instance.client;
  if (db.auth.currentUser == null) return;

  for (final id in ids) {
    final allowed = await db.rpc('record_geo_alert', params: {'p_cafe': id}).catchError((_) => false) as bool;
    if (!allowed) continue;
    final info = cafes[id] as Map<String, dynamic>? ?? {};
    await NearbyAlerts.initNotifications();
    await NearbyAlerts.notifications.show(
      id: id.hashCode,
      title: '${info['name'] ?? 'A partner cafe'} is nearby',
      body: (info['offer'] as String?) ?? 'Tap to see your card and today’s offers.',
      payload: id,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'nearby',
          'Nearby cafes',
          channelDescription: 'When you pass a partner cafe, up to 2 a day',
          importance: Importance.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
    break; // one popup per walk-by
  }
}
