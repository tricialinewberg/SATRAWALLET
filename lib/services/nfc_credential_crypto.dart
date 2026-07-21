import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Versioned, encrypted envelope written to the physical NFC recovery key,
/// replacing what used to be the wallet's mnemonic written to the tag in
/// plaintext. A tag can be lost, found, or read by anyone with an
/// NFC-capable phone, so its content is protected by:
///
/// - **AES-256-GCM** (authenticated encryption) — tampering is detected,
///   not just decrypted into garbage.
/// - **Argon2id** (memory-hard key derivation) — brute-forcing a lost tag
///   is expensive even for a weak password, per OWASP's recommended
///   parameters (19 MiB memory, 2+ iterations).
///
/// Never rolls its own crypto primitives — both come from `package:cryptography`
/// (actively maintained, ~2M pub.dev downloads), used here only to combine
/// them into the envelope format and drive them correctly.
class NfcCredentialCrypto {
  NfcCredentialCrypto._();

  static const currentVersion = 1;
  static const walletType = 'breez-spark';
  static const network = 'mainnet';
  static const _kdfName = 'argon2id';

  /// Minimum password length enforced when the user sets a physical-key
  /// password (see `NfcKeyPasswordService`). Not a hard cryptographic
  /// requirement on its own — Argon2id's memory cost already makes
  /// brute-forcing expensive — but a very short password is still weak.
  static const minPasswordLength = 8;

  static const _saltLength = 16;
  static const _macLength = 16; // AES-GCM auth tag length
  static const _defaultKdfMemory = 19456; // ~19 MiB, OWASP's suggested minimum
  static const _defaultKdfIterations = 3;
  static const _defaultKdfParallelism = 1;
  static const _keyLength = 32; // AES-256

  static final AesGcm _cipher = AesGcm.with256bits();

  /// Encrypts [mnemonic] with [password], returning the JSON envelope
  /// ready to be written to the tag as a single NDEF text record.
  static Future<String> encrypt({
    required String mnemonic,
    required String password,
  }) async {
    final salt = _randomBytes(_saltLength);
    final secretKey = await Argon2id(
      parallelism: _defaultKdfParallelism,
      memory: _defaultKdfMemory,
      iterations: _defaultKdfIterations,
      hashLength: _keyLength,
    ).deriveKeyFromPassword(password: password, nonce: salt);

    final secretBox = await _cipher.encrypt(
      utf8.encode(mnemonic),
      secretKey: secretKey,
    );

    // The AEAD's auth tag (mac) is appended to the ciphertext bytes so the
    // envelope only needs one "ciphertext" field — split back off in
    // [decrypt].
    final ciphertextWithTag = Uint8List.fromList([
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ]);

    final envelope = <String, dynamic>{
      'version': currentVersion,
      'walletType': walletType,
      'network': network,
      'kdf': _kdfName,
      'kdfMemory': _defaultKdfMemory,
      'kdfIterations': _defaultKdfIterations,
      'kdfParallelism': _defaultKdfParallelism,
      'salt': base64Encode(salt),
      'nonce': base64Encode(secretBox.nonce),
      'ciphertext': base64Encode(ciphertextWithTag),
    };
    return jsonEncode(envelope);
  }

  /// Structural check only — valid JSON, expected version/walletType/
  /// network/kdf, and well-formed field types — performed *before*
  /// prompting for a password or attempting to decrypt anything. Doesn't
  /// touch the ciphertext at all.
  static bool isRecognizedEnvelope(String rawText) {
    try {
      return _decodeEnvelopeMap(rawText) != null;
    } catch (_) {
      return false;
    }
  }

  /// Decrypts a JSON envelope produced by [encrypt]. Throws
  /// [NfcCredentialException] for ANY failure — malformed JSON, an
  /// unrecognized version/walletType/network, or a decryption failure
  /// (wrong password OR tampered/corrupted content) — deliberately not
  /// distinguishing which, so a wrong-password guess can't be told apart
  /// from corrupted data by whoever is trying it.
  static Future<String> decrypt({
    required String envelopeJson,
    required String password,
  }) async {
    try {
      final map = _decodeEnvelopeMap(envelopeJson);
      if (map == null) throw const NfcCredentialException();

      final salt = base64Decode(map['salt'] as String);
      final nonce = base64Decode(map['nonce'] as String);
      final ciphertextWithTag = base64Decode(map['ciphertext'] as String);
      if (ciphertextWithTag.length < _macLength) throw const NfcCredentialException();

      final memory = map['kdfMemory'] as int? ?? _defaultKdfMemory;
      final iterations = map['kdfIterations'] as int? ?? _defaultKdfIterations;
      final parallelism = map['kdfParallelism'] as int? ?? _defaultKdfParallelism;

      final secretKey = await Argon2id(
        parallelism: parallelism,
        memory: memory,
        iterations: iterations,
        hashLength: _keyLength,
      ).deriveKeyFromPassword(password: password, nonce: salt);

      final splitIndex = ciphertextWithTag.length - _macLength;
      final cipherBytes = ciphertextWithTag.sublist(0, splitIndex);
      final macBytes = ciphertextWithTag.sublist(splitIndex);
      final secretBox = SecretBox(cipherBytes, nonce: nonce, mac: Mac(macBytes));

      final clearBytes = await _cipher.decrypt(secretBox, secretKey: secretKey);
      return utf8.decode(clearBytes);
    } on NfcCredentialException {
      rethrow;
    } catch (_) {
      // Covers SecretBoxAuthenticationError (wrong password or tampering),
      // FormatException (bad base64/UTF-8), and anything else — all
      // reported identically so none of them leak which failure occurred.
      throw const NfcCredentialException();
    }
  }

  static Map<String, dynamic>? _decodeEnvelopeMap(String rawText) {
    final decoded = jsonDecode(rawText);
    if (decoded is! Map<String, dynamic>) return null;
    if (decoded['version'] != currentVersion) return null;
    if (decoded['walletType'] != walletType) return null;
    if (decoded['network'] != network) return null;
    if (decoded['kdf'] != _kdfName) return null;
    if (decoded['salt'] is! String) return null;
    if (decoded['nonce'] is! String) return null;
    if (decoded['ciphertext'] is! String) return null;
    return decoded;
  }

  static Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(List<int>.generate(length, (_) => random.nextInt(256)));
  }
}

/// Thrown by [NfcCredentialCrypto.decrypt] for any failure. Deliberately
/// generic — see that method's doc comment on why wrong-password and
/// corrupted-data failures must never be distinguishable.
class NfcCredentialException implements Exception {
  const NfcCredentialException();

  @override
  String toString() => 'Não foi possível decifrar esta chave com a senha informada.';
}
