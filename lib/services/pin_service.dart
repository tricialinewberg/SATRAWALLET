import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores the user's personal PIN in encrypted local storage
/// (Android Keystore / iOS Keychain) — never in plain files or memory-only state.
class PinService {
  PinService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _pinKey = 'satra_user_pin';

  final FlutterSecureStorage _storage;

  Future<bool> hasPin() async {
    final pin = await _storage.read(key: _pinKey);
    return pin != null && pin.isNotEmpty;
  }

  Future<void> savePin(String pin) async {
    await _storage.write(key: _pinKey, value: pin);
  }

  Future<bool> verifyPin(String candidate) async {
    final pin = await _storage.read(key: _pinKey);
    return pin != null && pin == candidate;
  }
}
