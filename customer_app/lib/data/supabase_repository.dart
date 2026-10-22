import 'package:flutter/painting.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';
import 'repository.dart';

class SupabaseRepository implements Repository {
  SupabaseRepository(this.db);
  final SupabaseClient db;

  static const _cafeCols = 'id, name, kind, area, city, lat, lng, stamp_goal, reward_label, brand_bg, brand_ink, brand_acc, brand_pat, logo_path, photo_paths';

  String _media(String path) => db.storage.from('cafe-media').getPublicUrl(path);
  Cafe _cafe(Map<String, dynamic> r) => Cafe.fromRow(r, mediaUrl: _media);

  String get _uid {
    final id = userId;
    if (id == null) throw const AppError('Please sign in first.');
    return id;
  }

  @override
  String? get userId => db.auth.currentUser?.id;

  @override
  Stream<String?> get authChanges => db.auth.onAuthStateChange.map((s) => s.session?.user.id).distinct();

  // ------------------------------------------------------------------- auth

  @override
  Future<void> sendOtp({required String phone, required String name}) async {
    try {
      await db.auth.signInWithOtp(phone: '+91$phone', data: {'name': name});
    } on AuthException catch (e) {
      throw AppError(e.statusCode == '429' ? 'Too many codes sent. Try again in a minute.' : 'Could not send the code. ${e.message}');
    }
  }

  @override
  Future<void> verifyOtp({required String phone, required String code}) async {
    try {
      await db.auth.verifyOTP(phone: '+91$phone', token: code, type: OtpType.sms);
    } on AuthException {
      throw const AppError('That code is wrong or has expired.');
    }
  }

  @override
  Future<void> signOut() => db.auth.signOut();

  @override
  Future<void> deleteAccount() async {
    await db.rpc('delete_my_account');
    await db.auth.signOut();
  }

  @override
  Future<Map<String, dynamic>> exportMyData() async => Map<String, dynamic>.from(await db.rpc('export_my_data') as Map);

  // ------------------------------------------------------------------ cafes

  @override
  Future<List<City>> cities() async {
    final rows = await db.from('cities').select('name, active, lat, lng').order('sort');
    return [
      for (final r in rows)
        if (r['lat'] != null) City(r['name'] as String, r['active'] as bool, (r['lat'] as num).toDouble(), (r['lng'] as num).toDouble()),
    ];
  }

  Future<void> _attachHours(List<Cafe> cafes) async {
    if (cafes.isEmpty) return;
    final rows = await db.from('cafe_hours').select().inFilter('cafe_id', cafes.map((c) => c.id).toList());
    for (final c in cafes) {
      c.hours = [
        for (final r in rows)
          if (r['cafe_id'] == c.id) OpeningHours.fromRow(r),
      ];
    }
  }

  @override
  Future<List<Cafe>> nearbyCafes(double lat, double lng, {int radiusM = 5000}) async {
    final rows = await db.rpc('nearby_cafes', params: {'p_lat': lat, 'p_lng': lng, 'p_radius_m': radiusM, 'p_limit': 100}) as List;
    final cafes = [for (final r in rows) _cafe(r as Map<String, dynamic>)];
    await _attachHours(cafes);
    return cafes;
  }

  @override
  Future<List<Cafe>> searchCafes(String query) async {
    final q = query.replaceAll(RegExp(r'[%_,()]'), ' ').trim();
    if (q.isEmpty) return [];
    final rows = await db.from('cafes').select('$_cafeCols, cafe_hours(*)').or('name.ilike.%$q%,area.ilike.%$q%,kind.ilike.%$q%').limit(20);
    return [for (final r in rows) _cafe(r)];
  }

  @override
  Future<List<Offer>> offers(List<String> cafeIds) async {
    if (cafeIds.isEmpty) return [];
    final rows = await db.from('offers').select().inFilter('cafe_id', cafeIds).order('created_at', ascending: false);
    return [for (final r in rows) Offer.fromRow(r)];
  }

  @override
  Future<Set<String>> savedOfferIds() async {
    if (userId == null) return {};
    final rows = await db.from('saved_offers').select('offer_id');
    return {for (final r in rows) r['offer_id'] as String};
  }

  @override
  Future<void> setOfferSaved(String offerId, bool saved) async {
    if (saved) {
      await db.from('saved_offers').upsert({'user_id': _uid, 'offer_id': offerId});
    } else {
      await db.from('saved_offers').delete().eq('offer_id', offerId);
    }
  }

  // ------------------------------------------------------------------ cards

  LoyaltyCard _card(Map<String, dynamic> r, Cafe cafe) => LoyaltyCard(
    id: r['id'] as String,
    cafe: cafe,
    memberCode: r['member_code'] as String,
    stamps: r['stamps'] as int,
    rewardsRedeemed: r['rewards_redeemed'] as int,
    offersOptIn: r['offers_opt_in'] as bool,
    walletPos: r['wallet_pos'] as int,
  );

  @override
  Future<List<LoyaltyCard>> myCards() async {
    if (userId == null) return [];
    final rows = await db.from('cards').select('*, cafes($_cafeCols, cafe_hours(*))').order('wallet_pos');
    return [
      // a cafe that stopped paying drops out of the join; hide its card
      for (final r in rows)
        if (r['cafes'] != null) _card(r, _cafe(r['cafes'] as Map<String, dynamic>)),
    ];
  }

  @override
  Future<LoyaltyCard> joinCafe(String cafeId, {required bool offersOptIn}) async {
    try {
      await db.rpc('join_cafe', params: {'p_cafe': cafeId, 'p_offers_opt_in': offersOptIn});
    } on PostgrestException catch (e) {
      throw AppError(e.message.contains('cafe_unavailable') ? 'This cafe is not taking new members right now.' : 'Could not join. Try again.');
    }
    return (await myCards()).firstWhere((c) => c.cafe.id == cafeId);
  }

  @override
  Future<void> setCardOffers(String cardId, bool on) => db.from('cards').update({'offers_opt_in': on}).eq('id', cardId);

  @override
  Future<List<StampEvent>> history(String cardId) async {
    final rows = await db.from('stamp_events').select('created_at, note, kind, delta').eq('card_id', cardId).order('created_at', ascending: false).limit(20);
    return [for (final r in rows) StampEvent(DateTime.parse(r['created_at'] as String).toLocal(), (r['note'] as String?) ?? (r['kind'] as String))];
  }

  @override
  void Function() watchCards(void Function(String cardId, int stamps) onChange) {
    final uid = userId;
    if (uid == null) return () {};
    final ch = db
        .channel('cards-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'cards',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: uid),
          callback: (p) => onChange(p.newRecord['id'] as String, p.newRecord['stamps'] as int),
        )
        .subscribe();
    return () => db.removeChannel(ch);
  }

  // ---------------------------------------------------------------- profile

  @override
  Future<Profile> profile() async {
    final uid = _uid;
    final r = await db.from('profiles').select().eq('id', uid).single();
    final days = await db.from('special_days').select('label, day').order('created_at');
    final path = r['photo_path'] as String?;
    ImageProvider? photo;
    if (path != null) {
      photo = NetworkImage(await db.storage.from('avatars').createSignedUrl(path, 60 * 60 * 24 * 7));
    }
    final phone = (r['phone'] as String? ?? '').replaceAll(RegExp(r'\D'), '');
    return Profile(
      id: uid,
      name: r['name'] as String,
      phone: phone.length > 10 ? phone.substring(phone.length - 10) : phone,
      photo: photo,
      photoPath: path,
      birthday: r['birthday'] == null ? null : DateTime.parse(r['birthday'] as String),
      email: r['email'] as String?,
      diet: Diet.fromDb(r['diet'] as String?),
      usualOrder: r['usual_order'] as String?,
      notifyStamps: r['notify_stamps'] as bool,
      notifyOffers: r['notify_offers'] as bool,
      notifyTreats: r['notify_treats'] as bool,
      geoAlerts: r['geo_alerts'] as bool,
      specialDays: [for (final d in days) SpecialDay(d['label'] as String, DateTime.parse(d['day'] as String))],
    );
  }

  @override
  Future<Profile> saveProfile(Profile current, ProfileEdit e) async {
    final uid = _uid;
    String? path = current.photoPath;
    if (e.newPhoto != null) {
      final next = '$uid/avatar-${DateTime.now().millisecondsSinceEpoch}.jpg';
      await db.storage.from('avatars').uploadBinary(next, e.newPhoto!, fileOptions: const FileOptions(contentType: 'image/jpeg'));
      if (path != null) await db.storage.from('avatars').remove([path]);
      path = next;
    } else if (e.removePhoto && path != null) {
      await db.storage.from('avatars').remove([path]);
      path = null;
    }
    await db
        .from('profiles')
        .update({
          'name': e.name,
          'photo_path': path,
          'birthday': e.birthday == null ? null : isoDay(e.birthday!),
          'email': e.email,
          'diet': e.diet?.dbName,
          'usual_order': e.usualOrder,
        })
        .eq('id', uid);
    await db.from('special_days').delete().eq('user_id', uid);
    if (e.specialDays.isNotEmpty) {
      await db.from('special_days').insert([
        for (final d in e.specialDays) {'user_id': uid, 'label': d.label, 'day': isoDay(d.day)},
      ]);
    }
    return profile();
  }

  @override
  Future<void> setPrefs({bool? stamps, bool? offers, bool? treats, bool? geoAlerts}) =>
      db.from('profiles').update({'notify_stamps': ?stamps, 'notify_offers': ?offers, 'notify_treats': ?treats, 'geo_alerts': ?geoAlerts}).eq('id', _uid);

  // ---------------------------------------------------------- nearby alerts

  @override
  Future<int> geoAlertsToday() async {
    if (userId == null) return 0;
    final rows = await db.from('geo_alerts').select('id').eq('local_day', isoDay(nowIst()));
    return rows.length;
  }

  @override
  Future<bool> recordGeoAlert(String cafeId) async => await db.rpc('record_geo_alert', params: {'p_cafe': cafeId}) as bool;

  @override
  Future<void> registerPushToken(String token, String platform) =>
      db.rpc('register_push_token', params: {'p_token': token, 'p_app': 'customer', 'p_platform': platform});
}
