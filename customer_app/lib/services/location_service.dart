import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../data/demo_repository.dart';

typedef Position2 = ({double lat, double lng});

class LocationService {
  /// Asks for permission while the app is in use, then reads GPS.
  /// Null when the customer says no or location is off.
  Future<Position2?> current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return null;
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 12)),
      );
      return (lat: p.latitude, lng: p.longitude);
    } catch (_) {
      return null;
    }
  }

  /// Town or city name for a point that isn't near a partner city.
  Future<String?> placeName(Position2 p) async {
    if (kIsWeb) return null;
    try {
      final m = (await Geocoding().placemarkFromCoordinates(p.lat, p.lng)).firstOrNull;
      for (final s in [m?.locality, m?.subAdministrativeArea]) {
        if (s != null && s.isNotEmpty) return s;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Whether nearby alerts can run with the app closed.
  Future<bool> hasAlways() async {
    try {
      return await Geolocator.checkPermission() == LocationPermission.always;
    } catch (_) {
      return false;
    }
  }

  /// Asks for "Always" access. Android 11+ and iOS send the customer to
  /// Settings for this, so it may return false the first time.
  Future<bool> requestAlways() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.whileInUse) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.always) return true;
      await Geolocator.openAppSettings();
      return false;
    } catch (_) {
      return false;
    }
  }
}

/// Demo mode: "you" are in Saraswathipuram, Mysuru, as in the mock.
class DemoLocationService extends LocationService {
  @override
  Future<Position2?> current() async {
    await Future.delayed(const Duration(milliseconds: 900));
    return (lat: DemoRepository.home.$1, lng: DemoRepository.home.$2);
  }

  @override
  Future<String?> placeName(Position2 p) async => null;

  @override
  Future<bool> hasAlways() async => true;

  @override
  Future<bool> requestAlways() async => true;
}
