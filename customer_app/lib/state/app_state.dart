import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../services/location_service.dart';

enum AppTab { home, map, wallet, profile }

/// One-off things the UI should show: a toast, or the nearby-cafe popup.
sealed class UiEvent {}

class ToastEvent extends UiEvent {
  ToastEvent(this.message);
  final String message;
}

class NearbyEvent extends UiEvent {
  NearbyEvent(this.cafe);
  final Cafe cafe;
}

typedef LatLng2 = ({double lat, double lng});

/// The customer app's state, shared by every screen through [AppScope].
class AppState extends ChangeNotifier {
  AppState(this.repo, this.prefs, this.location);

  final Repository repo;
  final SharedPreferences prefs;
  final LocationService location;
  final _events = StreamController<UiEvent>.broadcast();
  Stream<UiEvent> get events => _events.stream;
  StreamSubscription<String?>? _authSub;
  void Function()? _unwatchCards;

  // navigation, as in the mock's state.tab / state.sel / state.route
  AppTab tab = AppTab.home;
  AppTab _prevTab = AppTab.home;
  String? selectedId;
  String? routeId;
  String query = '';
  int walletIndex = 0;

  bool get signedIn => repo.userId != null;
  Profile? me;
  List<LoyaltyCard> cards = [];
  final Map<String, Cafe> registry = {};
  List<Cafe> nearby = [];
  List<Offer> offers = [];
  Set<String> saved = {};
  int geoToday = 0;

  List<City> cities = [];
  LatLng2? you;
  String? city;
  bool locating = true;
  bool loadingNearby = true;

  String themeKey = 'system';
  ThemeMode get themeMode => switch (themeKey) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  /// Called after a sign-in finishes: join this cafe, or show its card.
  String? pendingCafe;

  // ------------------------------------------------------------- startup

  Future<void> start() async {
    themeKey = prefs.getString('theme') ?? 'system';
    _authSub = repo.authChanges.listen((_) => _onAuth());
    try {
      cities = await repo.cities();
    } catch (_) {}
    if (signedIn) await _onAuth();
    await locate();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _unwatchCards?.call();
    _events.close();
    super.dispose();
  }

  void toast(String msg) => _events.add(ToastEvent(msg));

  Future<void>? _loading;
  String? _loadingFor;

  /// Loads or clears the account when the signed-in user changes. Sign-in and
  /// the auth event both ask for this; it runs once per user.
  Future<void> _onAuth() {
    final uid = repo.userId;
    if (_loading != null && _loadingFor == uid) return _loading!;
    _loadingFor = uid;
    return _loading = _loadAccount();
  }

  Future<void> _loadAccount() async {
    _unwatchCards?.call();
    _unwatchCards = null;
    if (!signedIn) {
      me = null;
      cards = [];
      saved = {};
      geoToday = 0;
      notifyListeners();
      return;
    }
    try {
      me = await repo.profile();
      await refreshCards();
      saved = await repo.savedOfferIds();
      geoToday = await repo.geoAlertsToday();
      _saveAccount();
    } catch (e) {
      toast('Could not load your account. Pull to retry.');
    }
    _unwatchCards = repo.watchCards((id, stamps) {
      for (final c in cards) {
        if (c.id == id) c.stamps = stamps;
      }
      notifyListeners();
    });
    notifyListeners();
  }

  Future<void> refreshCards() async {
    cards = await repo.myCards();
    for (final c in cards) {
      registry.putIfAbsent(c.cafe.id, () => c.cafe);
    }
    notifyListeners();
  }

  // ------------------------------------------------------------ location

  /// Detects the phone's location, then loads the cafes around it.
  Future<void> locate() async {
    locating = true;
    notifyListeners();
    final pos = await location.current();
    if (pos != null) {
      you = pos;
      city = _cityNear(pos) ?? await location.placeName(pos) ?? 'Your area';
    } else {
      // no permission: fall back to the first city with partner cafes
      final c = cities.where((c) => c.active).firstOrNull ?? cities.firstOrNull;
      if (c != null) {
        you = (lat: c.lat, lng: c.lng);
        city = c.name;
      }
    }
    locating = false;
    notifyListeners();
    await refreshNearby();
  }

  String? _cityNear(LatLng2 p) {
    City? best;
    var bd = 40000.0;
    for (final c in cities) {
      final d = distanceM(p.lat, p.lng, c.lat, c.lng);
      if (d < bd) {
        bd = d;
        best = c;
      }
    }
    return best?.name;
  }

  Future<void> chooseCity(City c) async {
    you = (lat: c.lat, lng: c.lng);
    city = c.name;
    selectedId = null;
    routeId = null;
    notifyListeners();
    await refreshNearby();
  }

  Future<void> refreshNearby() async {
    final p = you;
    if (p == null) return;
    loadingNearby = true;
    notifyListeners();
    try {
      nearby = await repo.nearbyCafes(p.lat, p.lng, radiusM: 8000);
      for (final c in nearby) {
        registry[c.id] = c;
      }
      offers = await repo.offers(nearby.map((c) => c.id).toList());
    } catch (_) {
      toast('Could not load cafes. Check your connection.');
    }
    loadingNearby = false;
    notifyListeners();
  }

  /// Map tab: load partner cafes around wherever the map is looking.
  Future<void> loadAround(double lat, double lng, int radiusM) async {
    try {
      final found = await repo.nearbyCafes(lat, lng, radiusM: radiusM.clamp(500, 20000));
      var added = false;
      for (final c in found) {
        added |= !registry.containsKey(c.id);
        registry[c.id] = c;
      }
      if (added) notifyListeners();
    } catch (_) {}
  }

  double distanceTo(Cafe c) => you == null ? 0 : distanceM(you!.lat, you!.lng, c.lat, c.lng);

  /// The 12 places nearest to you, which the map card swipes through.
  List<Cafe> get nearList {
    final all = registry.values.toList()..sort((a, b) => distanceTo(a).compareTo(distanceTo(b)));
    return all.take(12).toList();
  }

  LoyaltyCard? cardFor(String cafeId) => cards.where((c) => c.cafe.id == cafeId).firstOrNull;

  /// Card with the most stamps that isn't full yet, for the Home hero.
  LoyaltyCard? get closestReward {
    final open = cards.where((c) => !c.rewardReady).toList()..sort((a, b) => b.stamps.compareTo(a.stamps));
    return open.firstOrNull;
  }

  bool get noPartnersHere => !loadingNearby && nearby.isEmpty;

  // ---------------------------------------------------------- navigation

  void setTab(AppTab t) {
    if (t == AppTab.profile && tab != AppTab.profile) _prevTab = tab;
    if (t != AppTab.map) query = '';
    tab = t;
    notifyListeners();
  }

  void closeProfile() => setTab(_prevTab);

  void select(String? id) {
    selectedId = id;
    routeId = null;
    query = '';
    if (id != null && tab != AppTab.map) tab = AppTab.map;
    notifyListeners();
  }

  void toggleRoute(String id) {
    routeId = routeId == id ? null : id;
    notifyListeners();
  }

  void setQuery(String q) {
    query = q;
    notifyListeners();
  }

  // ------------------------------------------------------------- account

  Future<void> sendOtp(String name, String phone) => repo.sendOtp(phone: phone, name: name);

  Future<void> verifyOtp(String phone, String code) async {
    await repo.verifyOtp(phone: phone, code: code);
    await _onAuth();
  }

  Future<void> signOut() async {
    await repo.signOut();
    tab = AppTab.home;
    selectedId = routeId = null;
    await _onAuth();
  }

  Future<void> deleteAccount() async {
    await repo.deleteAccount();
    try {
      await prefs.remove('account');
    } catch (_) {}
    tab = AppTab.home;
    await _onAuth();
  }

  /// "Continue as …" on the sign-in sheet remembers the last account here.
  ({String name, String phone})? get savedAccount {
    try {
      final m = jsonDecode(prefs.getString('account') ?? 'null');
      if (m is Map && m['name'] is String && RegExp(r'^\d{10}$').hasMatch('${m['phone']}')) {
        return (name: m['name'] as String, phone: m['phone'] as String);
      }
    } catch (_) {}
    return null;
  }

  void _saveAccount() {
    final m = me;
    if (m == null || m.phone.length != 10) return;
    prefs.setString('account', jsonEncode({'name': m.name, 'phone': m.phone}));
  }

  Future<LoyaltyCard> join(String cafeId, {required String name, required bool offers}) async {
    if (me != null && name != me!.name) {
      me = await repo.saveProfile(
        me!,
        ProfileEdit(name: name, birthday: me!.birthday, email: me!.email, diet: me!.diet, usualOrder: me!.usualOrder, specialDays: me!.specialDays),
      );
    }
    final card = await repo.joinCafe(cafeId, offersOptIn: offers);
    await refreshCards();
    return card;
  }

  Future<void> toggleSaved(Offer o) async {
    final on = !saved.contains(o.id);
    on ? saved.add(o.id) : saved.remove(o.id);
    notifyListeners();
    try {
      await repo.setOfferSaved(o.id, on);
    } catch (_) {
      on ? saved.remove(o.id) : saved.add(o.id);
      notifyListeners();
      toast('Could not save that offer');
    }
  }

  Future<void> saveProfile(ProfileEdit e) async {
    me = await repo.saveProfile(me!, e);
    _saveAccount();
    notifyListeners();
  }

  /// Flips a profile switch straight away and rolls back if saving fails.
  Future<void> setPref(String key, bool on) async {
    final m = me!;
    void apply(bool v) => switch (key) {
      'stamps' => m.notifyStamps = v,
      'offers' => m.notifyOffers = v,
      'treats' => m.notifyTreats = v,
      _ => m.geoAlerts = v,
    };
    apply(on);
    notifyListeners();
    try {
      await repo.setPrefs(
        stamps: key == 'stamps' ? on : null,
        offers: key == 'offers' ? on : null,
        treats: key == 'treats' ? on : null,
        geoAlerts: key == 'geo' ? on : null,
      );
    } catch (_) {
      apply(!on);
      notifyListeners();
      toast('Could not save. Check your connection.');
    }
  }

  Future<void> setCardOffers(LoyaltyCard c, bool on) async {
    c.offersOptIn = on;
    notifyListeners();
    try {
      await repo.setCardOffers(c.id, on);
    } catch (_) {
      c.offersOptIn = !on;
      notifyListeners();
    }
  }

  void setTheme(String key) {
    themeKey = key;
    prefs.setString('theme', key);
    notifyListeners();
  }

  // ------------------------------------------------------- nearby alerts

  /// A geofence fired while the app is running. Shows the popup if the
  /// server allows it (alerts on, under 2 today, not this cafe already).
  Future<void> onGeofence(String cafeId) async {
    final c = registry[cafeId];
    if (c == null) return;
    bool ok;
    try {
      ok = await repo.recordGeoAlert(cafeId);
    } catch (_) {
      return;
    }
    geoToday = await repo.geoAlertsToday();
    notifyListeners();
    if (ok) {
      _events.add(NearbyEvent(c));
    } else if (Config.demo) {
      toast(me != null && !me!.geoAlerts ? 'Nearby alerts are off, so no popup for ${c.name}' : 'Daily limit of 2 reached, so no popup for ${c.name}');
    }
  }

  /// Opening the app from a nearby-alert notification: already counted.
  void showNearby(String cafeId) {
    final c = registry[cafeId];
    if (c != null) _events.add(NearbyEvent(c));
  }

  /// Demo only: move "you" (the blue dot), as the mock's walk simulation does.
  void moveYou(LatLng2 p) {
    you = p;
    notifyListeners();
  }

  void refreshGeoCount() async {
    geoToday = await repo.geoAlertsToday();
    notifyListeners();
  }
}

/// Makes [AppState] available to the widget tree and rebuilds on change.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// Read without subscribing to rebuilds (for callbacks).
  static AppState read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
