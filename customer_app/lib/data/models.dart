import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/painting.dart';

/// Cafes, offers and the daily alert cap all run on India time, whatever the
/// phone's own time zone is.
DateTime nowIst() => DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));

String isoDay(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

enum CardPattern { dots, stripes, rings, grid }

/// The colours and pattern a cafe picks for its card in the cafe app.
class Brand {
  const Brand(this.bg, this.ink, this.acc, this.pat);
  final Color bg, ink, acc;
  final CardPattern pat;

  static Color hex(String s) => Color(int.parse(s.replaceFirst('#', ''), radix: 16) | 0xFF000000);

  factory Brand.fromRow(Map<String, dynamic> r) =>
      Brand(hex(r['brand_bg'] as String), hex(r['brand_ink'] as String), hex(r['brand_acc'] as String), CardPattern.values.byName(r['brand_pat'] as String));
}

class OpeningHours {
  const OpeningHours(this.weekday, this.opens, this.closes);

  /// 0 = Sunday … 6 = Saturday, as in Postgres.
  final int weekday;

  /// Minutes after local midnight.
  final int opens, closes;

  static int minutes(String hhmm) {
    final p = hhmm.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  factory OpeningHours.fromRow(Map<String, dynamic> r) => OpeningHours(r['weekday'] as int, minutes(r['opens'] as String), minutes(r['closes'] as String));
}

String clock(int minutes) {
  final h = minutes ~/ 60 % 24, m = minutes % 60;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12${m == 0 ? '' : ':${m.toString().padLeft(2, '0')}'} ${h < 12 ? 'am' : 'pm'}';
}

class Cafe {
  Cafe({
    required this.id,
    required this.name,
    required this.kind,
    required this.area,
    required this.city,
    required this.lat,
    required this.lng,
    required this.stampGoal,
    required this.rewardLabel,
    required this.brand,
    this.logoUrl,
    this.photoUrls = const [],
    this.hours = const [],
  });

  final String id, name, kind, area, city, rewardLabel;
  final double lat, lng;
  final int stampGoal;
  final Brand brand;
  final String? logoUrl;
  final List<String> photoUrls;
  List<OpeningHours> hours;

  bool get isRestaurant => kind == 'Restaurant';

  bool openAt(DateTime ist) {
    final dow = ist.weekday % 7, m = ist.hour * 60 + ist.minute;
    return hours.any((h) => h.weekday == dow && m >= h.opens && m < h.closes);
  }

  bool get isOpen => openAt(nowIst());

  /// "Open till 10 pm" or "Opens 7 am", like the badge in the mock.
  String get hoursLabel {
    final ist = nowIst(), dow = ist.weekday % 7, m = ist.hour * 60 + ist.minute;
    for (final h in hours.where((h) => h.weekday == dow)) {
      if (m >= h.opens && m < h.closes) return 'Open till ${clock(h.closes)}';
    }
    final later = hours.where((h) => h.weekday == dow && h.opens > m).toList()..sort((a, b) => a.opens.compareTo(b.opens));
    if (later.isNotEmpty) return 'Opens ${clock(later.first.opens)}';
    for (var d = 1; d <= 7; d++) {
      final next = hours.where((h) => h.weekday == (dow + d) % 7).toList()..sort((a, b) => a.opens.compareTo(b.opens));
      if (next.isNotEmpty) return d == 1 ? 'Opens ${clock(next.first.opens)}' : 'Closed today';
    }
    return 'Closed';
  }

  factory Cafe.fromRow(Map<String, dynamic> r, {String Function(String path)? mediaUrl}) => Cafe(
    id: r['id'] as String,
    name: r['name'] as String,
    kind: r['kind'] as String,
    area: r['area'] as String,
    city: r['city'] as String,
    lat: (r['lat'] as num).toDouble(),
    lng: (r['lng'] as num).toDouble(),
    stampGoal: r['stamp_goal'] as int,
    rewardLabel: r['reward_label'] as String,
    brand: Brand.fromRow(r),
    logoUrl: r['logo_path'] == null || mediaUrl == null ? null : mediaUrl(r['logo_path'] as String),
    photoUrls: [
      for (final p in (r['photo_paths'] as List? ?? const []))
        if (mediaUrl != null) mediaUrl(p as String),
    ],
    hours: [for (final h in (r['cafe_hours'] as List? ?? const [])) OpeningHours.fromRow(h as Map<String, dynamic>)],
  );
}

class Offer {
  Offer({required this.id, required this.cafeId, required this.title, this.endsAt, this.membersOnly = false, this.multiplier = 1, required this.createdAt});

  final String id, cafeId, title;
  final DateTime? endsAt;
  final DateTime createdAt;
  final bool membersOnly;
  final int multiplier;

  /// "Ends today", "Ends Friday", "This week" or "New".
  String get expiryLabel {
    final now = nowIst();
    if (endsAt == null) return now.difference(createdAt).inDays < 14 ? 'New' : 'Ongoing';
    final end = endsAt!.toUtc().add(const Duration(hours: 5, minutes: 30));
    final days = DateTime(end.year, end.month, end.day).difference(DateTime(now.year, now.month, now.day)).inDays;
    if (days <= 0) return 'Ends today';
    if (days == 1) return 'Ends tomorrow';
    if (days < 7) return 'Ends ${const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][end.weekday - 1]}';
    return 'Ends ${end.day} ${months[end.month - 1]}';
  }

  factory Offer.fromRow(Map<String, dynamic> r) => Offer(
    id: r['id'] as String,
    cafeId: r['cafe_id'] as String,
    title: r['title'] as String,
    endsAt: r['ends_at'] == null ? null : DateTime.parse(r['ends_at'] as String),
    membersOnly: r['members_only'] as bool? ?? false,
    multiplier: r['stamp_multiplier'] as int? ?? 1,
    createdAt: DateTime.parse(r['created_at'] as String),
  );
}

class LoyaltyCard {
  LoyaltyCard({
    required this.id,
    required this.cafe,
    required this.memberCode,
    required this.stamps,
    this.rewardsRedeemed = 0,
    this.offersOptIn = false,
    this.walletPos = 0,
  });

  final String id, memberCode;
  final Cafe cafe;
  int stamps, rewardsRedeemed, walletPos;
  bool offersOptIn;

  bool get rewardReady => stamps >= cafe.stampGoal;
  int get toGo => math.max(0, cafe.stampGoal - stamps);
}

class StampEvent {
  const StampEvent(this.at, this.note);
  final DateTime at;
  final String note;
}

class SpecialDay {
  const SpecialDay(this.label, this.day);
  final String label;
  final DateTime day;
}

enum Diet {
  vegetarian('Vegetarian'),
  eggetarian('Eggetarian'),
  nonVegetarian('Non-vegetarian'),
  vegan('Vegan');

  const Diet(this.label);
  final String label;

  String get dbName => name == 'nonVegetarian' ? 'non_vegetarian' : name;
  static Diet? fromDb(String? s) => s == null ? null : Diet.values.firstWhere((d) => d.dbName == s);
}

class Profile {
  Profile({
    required this.id,
    required this.name,
    required this.phone,
    this.photo,
    this.photoPath,
    this.birthday,
    this.email,
    this.diet,
    this.usualOrder,
    this.notifyStamps = true,
    this.notifyOffers = true,
    this.notifyTreats = true,
    this.geoAlerts = true,
    this.specialDays = const [],
  });

  final String id;
  String name;

  /// 10-digit national number, without +91.
  String phone;
  ImageProvider? photo;
  String? photoPath;
  DateTime? birthday;
  String? email, usualOrder;
  Diet? diet;
  bool notifyStamps, notifyOffers, notifyTreats, geoAlerts;
  List<SpecialDay> specialDays;
}

/// What the edit-profile form sends back.
class ProfileEdit {
  ProfileEdit({
    required this.name,
    this.birthday,
    this.email,
    this.diet,
    this.usualOrder,
    this.specialDays = const [],
    this.newPhoto,
    this.removePhoto = false,
  });

  final String name;
  final DateTime? birthday;
  final String? email, usualOrder;
  final Diet? diet;
  final List<SpecialDay> specialDays;
  final Uint8List? newPhoto;
  final bool removePhoto;
}

class City {
  const City(this.name, this.active, this.lat, this.lng);
  final String name;
  final bool active;
  final double lat, lng;
}

const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Metres between two points.
double distanceM(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1), dLng = rad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) + math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(a));
}

/// "650 m" or "1.2 km".
String fmtDistance(double m) => m < 1000 ? '${math.max(10, (m / 10).round() * 10)} m' : '${(m / 1000).toStringAsFixed(1)} km';

/// About 80 m a minute on foot.
int walkMinutes(double m) => math.max(1, (m / 80).round());

String initials(String name) => name.split(RegExp(r'\s+')).where((w) => RegExp(r'^[A-Za-z]').hasMatch(w)).take(2).map((w) => w[0].toUpperCase()).join();
