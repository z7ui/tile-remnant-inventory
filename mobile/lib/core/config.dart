/// Static configuration. The server address can be changed at runtime in the
/// app (工地现场往往不是 443 默认域名), so it is only a default value here.
class AppConfig {
  const AppConfig._();

  static const String appVersion = '0.1.0';

  /// Pass at build time: `--dart-define=API_BASE_URL=https://tiles.example.com`
  static const String defaultBaseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: 'https://tiles.example.com');

  static const String inviteScheme = 'tileremnant';

  /// Cleartext HTTP is only tolerated for local development hosts.
  static bool isLocalHost(Uri uri) {
    const allowed = <String>{'localhost', '127.0.0.1', '10.0.2.2', '::1'};
    return allowed.contains(uri.host);
  }
}
