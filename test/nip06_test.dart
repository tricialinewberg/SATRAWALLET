import 'package:flutter_test/flutter_test.dart';
import 'package:nostr/nostr.dart';

import 'package:calculadora/services/nip06.dart';

void main() {
  // Fixed well-formed 12-word BIP-39 mnemonics used only to exercise
  // determinism/validity properties below — not real wallet seeds.
  const mnemonicA = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
  const mnemonicB = 'legal winner thank year wave sausage worth useful legal winner thank yellow';

  test('same mnemonic derives the same private key every time', () {
    final first = Nip06.deriveNostrPrivateKeyHex(mnemonicA);
    final second = Nip06.deriveNostrPrivateKeyHex(mnemonicA);
    expect(first, second);
  });

  test('different mnemonics derive different private keys', () {
    final a = Nip06.deriveNostrPrivateKeyHex(mnemonicA);
    final b = Nip06.deriveNostrPrivateKeyHex(mnemonicB);
    expect(a, isNot(b));
  });

  test('derived key is a well-formed 64-char hex secp256k1 private key usable by nostr Keys', () {
    final hex = Nip06.deriveNostrPrivateKeyHex(mnemonicA);
    expect(hex, matches(RegExp(r'^[0-9a-f]{64}$')));

    // Keys(hex) internally derives the Schnorr public key — this throws
    // if the private key were malformed or out of range, so a successful
    // construction plus a well-formed npub is a solid sanity check even
    // without official NIP-06 test vectors to compare against.
    final keys = Keys(hex);
    expect(keys.npub, startsWith('npub1'));
  });

  test('different accounts under the same mnemonic derive different keys', () {
    final account0 = Nip06.deriveNostrPrivateKeyHex(mnemonicA);
    final account1 = Nip06.deriveNostrPrivateKeyHex(mnemonicA, account: 1);
    expect(account0, isNot(account1));
  });
}
