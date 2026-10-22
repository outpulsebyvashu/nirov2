import 'models.dart';

/// Thrown with a message that can be shown to the customer as is.
class AppError implements Exception {
  const AppError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Everything the customer app reads and writes. SupabaseRepository talks to
/// the backend; DemoRepository serves the mock's example data.
abstract class Repository {
  /// Signed-in user id, or null.
  String? get userId;

  /// Fires whenever the user signs in or out.
  Stream<String?> get authChanges;

  /// Sends the SMS code. [name] is stored as the profile name on first sign-up.
  Future<void> sendOtp({required String phone, required String name});
  Future<void> verifyOtp({required String phone, required String code});
  Future<void> signOut();
  Future<void> deleteAccount();
  Future<Map<String, dynamic>> exportMyData();

  Future<List<City>> cities();
  Future<List<Cafe>> nearbyCafes(double lat, double lng, {int radiusM = 5000});
  Future<List<Cafe>> searchCafes(String query);
  Future<List<Offer>> offers(List<String> cafeIds);
  Future<Set<String>> savedOfferIds();
  Future<void> setOfferSaved(String offerId, bool saved);

  Future<List<LoyaltyCard>> myCards();
  Future<LoyaltyCard> joinCafe(String cafeId, {required bool offersOptIn});
  Future<void> setCardOffers(String cardId, bool on);
  Future<List<StampEvent>> history(String cardId);

  /// Calls [onChange] with (cardId, stamps) when staff stamp one of my cards.
  /// Returns a function that stops listening.
  void Function() watchCards(void Function(String cardId, int stamps) onChange);

  Future<Profile> profile();
  Future<Profile> saveProfile(Profile current, ProfileEdit edit);
  Future<void> setPrefs({bool? stamps, bool? offers, bool? treats, bool? geoAlerts});

  /// Number of nearby popups shown today (India time).
  Future<int> geoAlertsToday();

  /// Asks the server whether a nearby popup may be shown; counts it if so.
  Future<bool> recordGeoAlert(String cafeId);

  Future<void> registerPushToken(String token, String platform);
}
