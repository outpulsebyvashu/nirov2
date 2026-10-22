import 'dart:async';

import 'package:flutter/painting.dart';

import 'models.dart';
import 'repository.dart';

/// Runs the app with the example cafes from docs/customer-mock.html and no
/// backend. Any 6-digit code signs in. Nothing leaves the device.
class DemoRepository implements Repository {
  DemoRepository() {
    for (final c in _cafes) {
      c.hours = [for (var d = 0; d < 7; d++) OpeningHours(d, _open[c.id]!.$1, _open[c.id]!.$2)];
    }
  }

  /// Where the demo puts "you": Saraswathipuram, Mysuru.
  static const home = (12.3085, 76.6282);

  static final _cafes = [
    _c(
      'agr',
      'Agrahara Roasters',
      'Saraswathipuram',
      12.3105,
      76.6300,
      const Brand(Color(0xFF3B2418), Color(0xFFF6E7D4), Color(0xFFD9A066), CardPattern.rings),
    ),
    _c('kaa', 'Kaapi Kutir', 'Vijayanagar', 12.3290, 76.6100, const Brand(Color(0xFF1F4D3A), Color(0xFFF3ECD9), Color(0xFFE7B84A), CardPattern.stripes)),
    _c('cru', 'Crumb & Co', 'Kuvempunagar', 12.2900, 76.6250, const Brand(Color(0xFFF4E3C3), Color(0xFF4A2C14), Color(0xFFC8553D), CardPattern.dots)),
    _c(
      'cha',
      'Chamundi Chai Bar',
      'Jayalakshmipuram',
      12.3300,
      76.6330,
      const Brand(Color(0xFFC2410C), Color(0xFFFFF4E6), Color(0xFFFFD8A8), CardPattern.rings),
    ),
    _c('waf', 'Waffle Lane', 'Gokulam', 12.3330, 76.6380, const Brand(Color(0xFF2B2F6B), Color(0xFFFFE9F1), Color(0xFFFF8FB3), CardPattern.grid)),
  ];
  static final _open = {'agr': (480, 1320), 'kaa': (420, 1290), 'cru': (540, 1380), 'cha': (420, 1200), 'waf': (660, 1320)};

  static Cafe _c(String id, String name, String area, double lat, double lng, Brand b) =>
      Cafe(id: id, name: name, kind: 'Cafe', area: area, city: 'Mysuru', lat: lat, lng: lng, stampGoal: 8, rewardLabel: 'a free filter coffee', brand: b);

  static final _offers = [
    ('agr', 'Free pastry with any 2 coffees', 5),
    ('kaa', 'Double stamps before 11 am', 3),
    ('cru', 'Second slice at half price', 0),
    ('cha', 'Masala chai at ₹49 for members', 7),
    ('waf', 'Free topping on your first visit', -1),
  ];

  /// Cards a demo account starts with, as in the mock.
  static const _demoStamps = {'agr': 7, 'kaa': 3, 'cru': 8, 'cha': 1};

  final _auth = StreamController<String?>.broadcast();
  String? _uid;
  Profile? _me;
  final _cards = <LoyaltyCard>[];
  final _saved = <String>{};
  final _alerts = <String, Set<String>>{};

  Cafe _cafe(String id) => _cafes.firstWhere((c) => c.id == id);
  Future<void> _lag() => Future.delayed(const Duration(milliseconds: 250));

  @override
  String? get userId => _uid;

  @override
  Stream<String?> get authChanges => _auth.stream;

  String? _pendingName;

  @override
  Future<void> sendOtp({required String phone, required String name}) async {
    await _lag();
    _pendingName = name;
  }

  @override
  Future<void> verifyOtp({required String phone, required String code}) async {
    await _lag();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) throw const AppError('That code is wrong or has expired.');
    _uid = 'demo-user';
    _me = Profile(id: _uid!, name: _pendingName ?? 'Friend', phone: phone);
    _cards
      ..clear()
      ..addAll([
        for (final e in _demoStamps.entries)
          LoyaltyCard(id: 'card-${e.key}', cafe: _cafe(e.key), memberCode: _codes[e.key]!, stamps: e.value, offersOptIn: true, walletPos: _cards.length),
      ]);
    for (var i = 0; i < _cards.length; i++) {
      _cards[i].walletPos = i;
    }
    _auth.add(_uid);
  }

  static const _codes = {'agr': 'AG4F-71C2', 'kaa': 'KK09-B3E8', 'cru': 'CC52-9D0A', 'cha': 'CH77-3F61', 'waf': 'WL18-A4D5'};

  @override
  Future<void> signOut() async {
    _uid = null;
    _me = null;
    _cards.clear();
    _saved.clear();
    _auth.add(null);
  }

  @override
  Future<void> deleteAccount() => signOut();

  @override
  Future<Map<String, dynamic>> exportMyData() async => {
    'exported_at': DateTime.now().toIso8601String(),
    'profile': {'name': _me?.name, 'phone': _me?.phone},
    'cards': [
      for (final c in _cards) {'cafe': c.cafe.name, 'member_code': c.memberCode, 'stamps': c.stamps},
    ],
    'note': 'Demo mode: example data only',
  };

  @override
  Future<List<City>> cities() async => const [
    City('Mysuru', true, 12.2958, 76.6394),
    City('Bengaluru', false, 12.9716, 77.5946),
    City('Raipur', false, 21.2514, 81.6296),
    City('Bhilai', false, 21.1938, 81.3509),
    City('Jaipur', false, 26.9124, 75.7873),
  ];

  @override
  Future<List<Cafe>> nearbyCafes(double lat, double lng, {int radiusM = 5000}) async {
    await _lag();
    return _cafes.where((c) => distanceM(lat, lng, c.lat, c.lng) <= radiusM).toList()
      ..sort((a, b) => distanceM(lat, lng, a.lat, a.lng).compareTo(distanceM(lat, lng, b.lat, b.lng)));
  }

  @override
  Future<List<Cafe>> searchCafes(String query) async {
    final q = query.trim().toLowerCase();
    return _cafes.where((c) => '${c.name} ${c.area} ${c.kind}'.toLowerCase().contains(q)).toList();
  }

  @override
  Future<List<Offer>> offers(List<String> cafeIds) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 23, 30);
    return [
      for (final (id, title, days) in _offers)
        if (cafeIds.contains(id))
          Offer(
            id: 'offer-$id',
            cafeId: id,
            title: title,
            endsAt: days < 0 ? null : today.add(Duration(days: days)),
            createdAt: now.subtract(const Duration(days: 2)),
          ),
    ];
  }

  @override
  Future<Set<String>> savedOfferIds() async => {..._saved};

  @override
  Future<void> setOfferSaved(String offerId, bool saved) async => saved ? _saved.add(offerId) : _saved.remove(offerId);

  @override
  Future<List<LoyaltyCard>> myCards() async => [..._cards];

  @override
  Future<LoyaltyCard> joinCafe(String cafeId, {required bool offersOptIn}) async {
    await _lag();
    for (final c in _cards) {
      if (c.cafe.id == cafeId) return c;
    }
    final card = LoyaltyCard(
      id: 'card-$cafeId',
      cafe: _cafe(cafeId),
      memberCode: _codes[cafeId] ?? 'DEMO-0000',
      stamps: 0,
      offersOptIn: offersOptIn,
      walletPos: _cards.length,
    );
    _cards.add(card);
    return card;
  }

  @override
  Future<void> setCardOffers(String cardId, bool on) async => _cards.firstWhere((c) => c.id == cardId).offersOptIn = on;

  @override
  Future<List<StampEvent>> history(String cardId) async {
    final card = _cards.firstWhere((c) => c.id == cardId);
    if (card.stamps == 0) return [StampEvent(DateTime.now(), 'Joined')];
    final now = DateTime.now();
    return [
      StampEvent(now.subtract(const Duration(days: 1)), '+1 stamp'),
      StampEvent(now.subtract(const Duration(days: 4)), '+2 stamps (double day)'),
      StampEvent(now.subtract(const Duration(days: 10)), '+1 stamp'),
      StampEvent(now.subtract(const Duration(days: 17)), 'Joined'),
    ];
  }

  @override
  void Function() watchCards(void Function(String cardId, int stamps) onChange) => () {};

  @override
  Future<Profile> profile() async => _me!;

  @override
  Future<Profile> saveProfile(Profile current, ProfileEdit e) async {
    await _lag();
    final me = _me!
      ..name = e.name
      ..birthday = e.birthday
      ..email = e.email
      ..diet = e.diet
      ..usualOrder = e.usualOrder
      ..specialDays = e.specialDays;
    if (e.newPhoto != null) me.photo = MemoryImage(e.newPhoto!);
    if (e.removePhoto) me.photo = null;
    return me;
  }

  @override
  Future<void> setPrefs({bool? stamps, bool? offers, bool? treats, bool? geoAlerts}) async {
    final me = _me!;
    me.notifyStamps = stamps ?? me.notifyStamps;
    me.notifyOffers = offers ?? me.notifyOffers;
    me.notifyTreats = treats ?? me.notifyTreats;
    me.geoAlerts = geoAlerts ?? me.geoAlerts;
  }

  @override
  Future<int> geoAlertsToday() async => _alerts[isoDay(nowIst())]?.length ?? 0;

  @override
  Future<bool> recordGeoAlert(String cafeId) async {
    if (_me != null && !_me!.geoAlerts) return false;
    final today = _alerts.putIfAbsent(isoDay(nowIst()), () => {});
    if (today.contains(cafeId) || today.length >= 2) return false;
    today.add(cafeId);
    return true;
  }

  /// Demo only: the mock's "Reset today's count".
  void resetGeoAlerts() => _alerts.clear();

  @override
  Future<void> registerPushToken(String token, String platform) async {}
}
