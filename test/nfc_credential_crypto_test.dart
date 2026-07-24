import 'dart:convert';

import 'package:calculadora/services/nfc_credential_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
void main() {
  const mnemonic =
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

  test('encrypted recovery envelope round-trips a valid BIP-39 mnemonic',
      () async {
    final envelope = await NfcCredentialCrypto.encrypt(
      mnemonic: mnemonic,
      password: 'uma senha de teste segura',
    );

    expect(
      await NfcCredentialCrypto.decrypt(
        envelopeJson: envelope,
        password: 'uma senha de teste segura',
      ),
      mnemonic,
    );
  });

  test('rejects hostile Argon2 parameters before expensive derivation',
      () async {
    final envelope = jsonDecode(
      await NfcCredentialCrypto.encrypt(
        mnemonic: mnemonic,
        password: 'uma senha de teste segura',
      ),
    ) as Map<String, dynamic>;
    envelope['kdfMemory'] = 1000000000;
    final hostile = jsonEncode(envelope);

    expect(NfcCredentialCrypto.isRecognizedEnvelope(hostile), isFalse);
    expect(
      () => NfcCredentialCrypto.decrypt(
        envelopeJson: hostile,
        password: 'uma senha de teste segura',
      ),
      throwsA(isA<NfcCredentialException>()),
    );
  });

  test('wrong password throws NfcCredentialException, not raw crypto error',
      () async {
    final envelope = await NfcCredentialCrypto.encrypt(
      mnemonic: mnemonic,
      password: 'senha correta',
    );

    expect(
      () => NfcCredentialCrypto.decrypt(
        envelopeJson: envelope,
        password: 'senha errada',
      ),
      throwsA(isA<NfcCredentialException>()),
    );
  });

  test('corrupted ciphertext throws NfcCredentialException', () async {
    final envelope = await NfcCredentialCrypto.encrypt(
      mnemonic: mnemonic,
      password: 'senha',
    );
    final map = jsonDecode(envelope) as Map<String, dynamic>;
    // Flip a byte in the ciphertext so the GCM auth tag won't match.
    final corrupted = base64Decode(map['ciphertext'] as String);
    corrupted[0] ^= 0xFF;
    map['ciphertext'] = base64Encode(corrupted);

    expect(
      () => NfcCredentialCrypto.decrypt(
        envelopeJson: jsonEncode(map),
        password: 'senha',
      ),
      throwsA(isA<NfcCredentialException>()),
    );
  });

  test('tampered version field is rejected by isRecognizedEnvelope', () async {
    final envelope = await NfcCredentialCrypto.encrypt(
      mnemonic: mnemonic,
      password: 'senha',
    );
    final map = jsonDecode(envelope) as Map<String, dynamic>;
    map['version'] = 999;
    final tampered = jsonEncode(map);

    expect(NfcCredentialCrypto.isRecognizedEnvelope(tampered), isFalse);
  });

  test('each encryption produces a unique salt (non-deterministic)', () async {
    final a = await NfcCredentialCrypto.encrypt(
      mnemonic: mnemonic,
      password: 'senha',
    );
    final b = await NfcCredentialCrypto.encrypt(
      mnemonic: mnemonic,
      password: 'senha',
    );
    final saltA = (jsonDecode(a) as Map<String, dynamic>)['salt'];
    final saltB = (jsonDecode(b) as Map<String, dynamic>)['salt'];
    expect(saltA, isNot(saltB));
  });
}
