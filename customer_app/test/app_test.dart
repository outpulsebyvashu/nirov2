import 'package:customer_app/data/demo_repository.dart';
import 'package:customer_app/main.dart';
import 'package:customer_app/services/location_service.dart';
import 'package:customer_app/services/nearby_alerts.dart';
import 'package:customer_app/state/app_state.dart';
import 'package:customer_app/ui/map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FixedLocation extends DemoLocationService {
  @override
  Future<Position2?> current() async => (lat: DemoRepository.home.$1, lng: DemoRepository.home.$2);
}

Future<AppState> pumpApp(WidgetTester tester, {Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  debugTileProvider = NetworkTileProvider(cachingProvider: const DisabledMapCachingProvider(), silenceExceptions: true);
  final app = AppState(DemoRepository(), await SharedPreferences.getInstance(), FixedLocation());
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(CustomerApp(state: app, alerts: NearbyAlerts()));
  await tester.runAsync(app.start);
  await tester.pumpAndSettle();
  return app;
}

/// Lets the 2.4 s toast timer run out before the test ends.
Future<void> settleToasts(WidgetTester tester) => tester.pump(const Duration(seconds: 3));

Future<void> signIn(WidgetTester tester) async {
  await tester.tap(find.text('Sign up or log in').first);
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).at(0), 'Vashudev');
  await tester.enterText(find.byType(TextField).at(1), '9876543210');
  await tester.tap(find.text('Send OTP'));
  await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
  await tester.pumpAndSettle();
  expect(find.text('Enter the code'), findsOneWidget);
  expect(find.textContaining('+91 98765 43210'), findsOneWidget);
  await tester.enterText(find.byType(TextField).last, '482916');
  await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('signed out: greeting, sign-up hero and nearby cafes', (tester) async {
    await pumpApp(tester);
    expect(find.textContaining(RegExp(r'^Good (morning|afternoon|evening)$')), findsOneWidget);
    expect(find.text('Mysuru'), findsOneWidget);
    expect(find.text('Earn a free coffee at partner cafes'), findsOneWidget);
    expect(find.text('Nearby'), findsOneWidget);
    expect(find.text('5 partner cafes'), findsOneWidget);
    expect(find.text('Agrahara Roasters'), findsWidgets);
  });

  testWidgets('sign up with name, number and OTP, then see cards', (tester) async {
    final app = await pumpApp(tester);
    await signIn(tester);
    expect(app.signedIn, isTrue);
    expect(find.text('Hi, Vashudev'), findsOneWidget);
    // closest reward: the card with most stamps that isn't full (Agrahara, 7 of 8)
    expect(find.text('Closest reward'.toUpperCase()), findsOneWidget);
    expect(find.text('1 more stamp to a free filter coffee.'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Wallet'));
    await tester.pumpAndSettle();
    expect(find.text('4 cafes'), findsOneWidget);
    expect(find.text('REWARD READY'), findsOneWidget); // Crumb & Co, 8 of 8
    await settleToasts(tester);
  });

  testWidgets('a bad phone number is caught before sending', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Sign up or log in').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Asha');
    await tester.enterText(find.byType(TextField).at(1), '12345');
    await tester.tap(find.text('Send OTP'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid 10-digit mobile number.'), findsOneWidget);
  });

  testWidgets('join a cafe from the map card', (tester) async {
    final app = await pumpApp(tester);
    await signIn(tester);
    app.select('waf');
    await tester.pumpAndSettle();
    expect(find.text('Waffle Lane'), findsWidgets);
    await tester.tap(find.text('Join Loyalty'));
    await tester.pumpAndSettle();
    expect(find.text('Join Waffle Lane'), findsOneWidget);
    await tester.tap(find.text('Join Loyalty').last);
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 400)));
    await tester.pumpAndSettle();
    expect(find.text('You’re in!'), findsOneWidget);
    expect(app.cardFor('waf'), isNotNull);
    await tester.tap(find.text('Show my card'));
    await tester.pumpAndSettle();
    expect(find.text('MEMBER WL18-A4D5'), findsOneWidget);
    await settleToasts(tester);
  });

  testWidgets('profile shows the theme switch and nearby alerts', (tester) async {
    final app = await pumpApp(tester);
    await signIn(tester);
    app.setTab(AppTab.profile);
    await tester.pumpAndSettle();
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Vashudev'), findsOneWidget);
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(app.themeMode, ThemeMode.dark);
    await tester.scrollUntilVisible(find.text('Popups today'), 300);
    expect(find.text('0 of 2'), findsOneWidget);
    await settleToasts(tester);
  });
}
