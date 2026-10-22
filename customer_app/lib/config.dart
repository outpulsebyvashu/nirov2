/// Build-time settings, passed with --dart-define (see README).
/// With no SUPABASE_URL the app runs in demo mode on the mock's example data.
class Config {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get demo => supabaseUrl.isEmpty;

  /// OpenStreetMap raster tiles. Use a provider such as MapTiler or Stadia in
  /// production: the openstreetmap.org servers do not allow app traffic.
  static const tileUrl = String.fromEnvironment('MAP_TILE_URL', defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png');
  static const tileUrlDark = String.fromEnvironment('MAP_TILE_URL_DARK');
  static const tileAttribution = String.fromEnvironment('MAP_ATTRIBUTION', defaultValue: '© OpenStreetMap contributors');

  /// Optional OSRM-compatible routing server for walking directions. Without
  /// one, Direction draws a straight line and estimates the walk.
  static const routingUrl = String.fromEnvironment('ROUTING_URL');

  static const helpUrl = String.fromEnvironment('HELP_URL', defaultValue: 'https://cafeloyalty.in/help');
  static const supportEmail = String.fromEnvironment('SUPPORT_EMAIL', defaultValue: 'support@cafeloyalty.in');
  static const termsUrl = String.fromEnvironment('TERMS_URL', defaultValue: 'https://cafeloyalty.in/terms');

  static const packageName = 'in.cafeloyalty.customer_app';
}
