import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../config.dart';
import '../data/repository.dart';

/// FCM push for stamps, rewards and cafe offers. Needs the Firebase config
/// files (see README); without them push is skipped and the app still works.
class Push {
  static bool _ready = false;

  static Future<void> init() async {
    if (kIsWeb || Config.demo) return;
    try {
      await Firebase.initializeApp();
      _ready = true;
    } catch (e) {
      debugPrint('push disabled: $e');
    }
  }

  /// Registers this phone for the signed-in customer. [onMessage] shows
  /// pushes that arrive while the app is open.
  static Future<void> register(Repository repo, void Function(String text) onMessage) async {
    if (!_ready || repo.userId == null) return;
    final fcm = FirebaseMessaging.instance;
    final perm = await fcm.requestPermission();
    if (perm.authorizationStatus == AuthorizationStatus.denied) return;
    final platform = defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
    // onRegistered gives this install's FCM id now and again whenever it changes
    fcm.onRegistered.listen((id) => repo.registerPushToken(id, platform));
    await fcm.register();
    FirebaseMessaging.onMessage.listen((m) {
      final n = m.notification;
      if (n != null) onMessage([n.title, n.body].whereType<String>().join(' · '));
    });
  }
}
