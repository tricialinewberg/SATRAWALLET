import 'package:calculadora/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('isBreezConfigured reflects the compile-time key', () {
    expect(AppConfig.isBreezConfigured, AppConfig.breezApiKey.isNotEmpty);
  });

  test('requireBreezApiKey throws when the key is empty', () {
    if (AppConfig.isBreezConfigured) {
      expect(AppConfig.requireBreezApiKey(), isNotEmpty);
      return;
    }
    expect(
      AppConfig.requireBreezApiKey,
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('BREEZ_API_KEY'),
        ),
      ),
    );
  });
}
