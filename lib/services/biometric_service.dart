import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Optional biometric unlock preference and native authentication boundary.
///
/// No biometric data is stored by Satra. Android/iOS perform the check and
/// return only success, cancellation, or an error. The preference is kept in
/// secure storage so a fresh installation never enables biometrics by itself.
class BiometricService {
  BiometricService({
    FlutterSecureStorage? storage,
    LocalAuthentication? localAuthentication,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _localAuthentication = localAuthentication ?? LocalAuthentication();

  static const _enabledKey = 'satra_biometric_unlock_enabled';

  final FlutterSecureStorage _storage;
  final LocalAuthentication _localAuthentication;

  Future<bool> isEnabled() async =>
      await _storage.read(key: _enabledKey) == 'true';

  /// Biometrics are offered only when the OS reports at least one enrolled
  /// biometric. A device merely having a sensor is not enough.
  Future<bool> isAvailable() async {
    try {
      if (!await _localAuthentication.isDeviceSupported()) return false;
      return (await _localAuthentication.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Enabling requires a successful biometric check, preventing the user
  /// from activating a method that has not actually been enrolled/tested.
  Future<bool> enable() async {
    if (!await isAvailable()) return false;
    final authenticated = await authenticate(
      reason: 'Confirme sua biometria para ativar o desbloqueio',
    );
    if (!authenticated) return false;
    await _storage.write(key: _enabledKey, value: 'true');
    return true;
  }

  Future<void> disable() => _storage.write(key: _enabledKey, value: 'false');

  Future<bool> authenticate({
    String reason = 'Use sua biometria para abrir a carteira',
  }) async {
    try {
      return await _localAuthentication.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        sensitiveTransaction: true,
        persistAcrossBackgrounding: true,
      );
    } on LocalAuthException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
