import 'package:customer_app/data/demo_repository.dart';
import 'package:customer_app/data/models.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

Cafe cafe({List<OpeningHours> hours = const []}) => Cafe(
  id: 'c',
  name: 'Crumb & Co',
  kind: 'Cafe',
  area: 'Kuvempunagar',
  city: 'Mysuru',
  lat: 12.29,
  lng: 76.625,
  stampGoal: 8,
  rewardLabel: 'a free filter coffee',
  brand: const Brand(Color(0xFF000000), Color(0xFFFFFFFF), Color(0xFFFF0000), CardPattern.dots),
  hours: hours,
);

void main() {
  test('distance and walking time read like the mock', () {
    expect(fmtDistance(4), '10 m');
    expect(fmtDistance(644), '640 m');
    expect(fmtDistance(1234), '1.2 km');
    expect(walkMinutes(650), 8);
    expect(walkMinutes(10), 1);
    // Agrahara Roasters to Waffle Lane is a few kilometres across Mysuru
    expect(distanceM(12.3105, 76.6300, 12.3330, 76.6380), closeTo(2650, 100));
  });

  test('initials skip symbols', () {
    expect(initials('Crumb & Co'), 'CC');
    expect(initials('Agrahara Roasters'), 'AR');
  });

  test('clock times', () {
    expect(clock(22 * 60), '10 pm');
    expect(clock(21 * 60 + 30), '9:30 pm');
    expect(clock(7 * 60), '7 am');
    expect(clock(12 * 60), '12 pm');
  });

  test('open now uses the weekly hours', () {
    final c = cafe(hours: [for (var d = 0; d < 7; d++) OpeningHours(d, 9 * 60, 23 * 60)]);
    final wed10am = DateTime(2026, 10, 21, 10);
    final wed8am = DateTime(2026, 10, 21, 8);
    expect(c.openAt(wed10am), isTrue);
    expect(c.openAt(wed8am), isFalse);
  });

  test('phone numbers and diets map to the database', () {
    expect(Diet.nonVegetarian.dbName, 'non_vegetarian');
    expect(Diet.fromDb('non_vegetarian'), Diet.nonVegetarian);
    expect(Diet.fromDb(null), isNull);
  });

  group('demo repository', () {
    test('nearby alerts: two a day, never the same cafe twice', () async {
      final r = DemoRepository();
      await r.sendOtp(phone: '9876543210', name: 'Vashudev');
      await r.verifyOtp(phone: '9876543210', code: '123456');
      expect(await r.recordGeoAlert('agr'), isTrue);
      expect(await r.recordGeoAlert('agr'), isFalse);
      expect(await r.recordGeoAlert('kaa'), isTrue);
      expect(await r.recordGeoAlert('cru'), isFalse);
      expect(await r.geoAlertsToday(), 2);
    });

    test('alerts switched off: no popup', () async {
      final r = DemoRepository();
      await r.verifyOtp(phone: '9876543210', code: '123456');
      await r.setPrefs(geoAlerts: false);
      expect(await r.recordGeoAlert('agr'), isFalse);
    });

    test('sign-in gives the mock cards; joining twice keeps one card', () async {
      final r = DemoRepository();
      await r.verifyOtp(phone: '9876543210', code: '123456');
      expect((await r.myCards()).map((c) => c.stamps), [7, 3, 8, 1]);
      await r.joinCafe('waf', offersOptIn: false);
      await r.joinCafe('waf', offersOptIn: false);
      expect((await r.myCards()).length, 5);
    });

    test('a wrong code is rejected', () async {
      expect(() => DemoRepository().verifyOtp(phone: '9876543210', code: '12'), throwsA(anything));
    });
  });
}
