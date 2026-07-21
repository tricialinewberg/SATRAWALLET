import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'nfc_credential_crypto.dart';

/// Manages the password used to encrypt whatever gets written to the
/// physical NFC recovery key (see [NfcCredentialCrypto]), entered once in
/// [NfcKeyPasswordSetupScreen] at the same moment the fixed escape wallet
/// is created and its mnemonic written to the tag (see
/// `BreezService.createEscapeWallet`). The escape flow itself never reads
/// this — it doesn't touch NFC at all, since the tag is only ever written
/// once, here, well ahead of any real escape.
///
/// Stored in secure storage under its own key, distinct from the wallet's
/// own mnemonic. This protects the tag from someone who finds/steals it
/// separately from the phone — if someone already has full access to this
/// phone's own secure storage, they already have the wallet mnemonic
/// directly, so this password wouldn't add anything in that scenario.
class NfcKeyPasswordService {
  NfcKeyPasswordService._();
  static final NfcKeyPasswordService instance = NfcKeyPasswordService._();

  static const _passwordKey = 'satra_nfc_key_password';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  Future<bool> hasPassword() async {
    final value = await _secureStorage.read(key: _passwordKey);
    return value != null && value.isNotEmpty;
  }

  Future<String?> getPassword() => _secureStorage.read(key: _passwordKey);

  /// Sets the physical-key password. Throws [ArgumentError] if it's
  /// shorter than [NfcCredentialCrypto.minPasswordLength].
  Future<void> setPassword(String password) async {
    if (password.length < NfcCredentialCrypto.minPasswordLength) {
      throw ArgumentError(
        'A senha precisa ter pelo menos ${NfcCredentialCrypto.minPasswordLength} caracteres.',
      );
    }
    await _secureStorage.write(key: _passwordKey, value: password);
  }

  Future<void> clearPassword() => _secureStorage.delete(key: _passwordKey);
}
