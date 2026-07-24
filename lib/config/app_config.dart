/// Application configuration backed by compile-time `--dart-define` values.
///
/// The Breez API key is injected at build time via
/// `flutter run --dart-define-from-file=config.json` (or `--dart-define=...`).
/// Like every credential embedded in a mobile app, the resulting value lives
/// in the compiled APK and is not an unextractable secret.
class AppConfig {
  AppConfig._();

  static const _breezApiKey =
      String.fromEnvironment('BREEZ_API_KEY', defaultValue: '');

  static String get breezApiKey => _breezApiKey.trim();

  static bool get isBreezConfigured => breezApiKey.isNotEmpty;

  static String requireBreezApiKey() {
    final key = breezApiKey;
    if (key.isEmpty) {
      throw StateError(
        'BREEZ_API_KEY não configurada. Use '
        '--dart-define-from-file=config.json (copie config.example.json) ou '
        '--dart-define=BREEZ_API_KEY=...',
      );
    }
    return key;
  }
}
