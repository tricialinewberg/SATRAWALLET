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

  // -------------------------------------------------------------------
  // Official NIP-06 test vectors, verbatim from the spec:
  // https://github.com/nostr-protocol/nips/blob/master/06.md#test-vectors
  // These pin the implementation to the exact keys the protocol expects,
  // so the wallet's derived Nostr identity matches what every other
  // compliant Nostr client (Damus, Amethyst, ...) would compute for the
  // same mnemonic. This is the property the inheritance feature and the
  // trusted-contacts backup both depend on to survive a wallet restore.
  // -------------------------------------------------------------------
  group('official NIP-06 test vectors', () {
    test('vector 1: 12-word mnemonic matches the spec exactly', () {
      const mnemonic =
          'leader monkey parrot ring guide accident before fence cannon height naive bean';
      const expectedPrivateKeyHex =
          '7f7ff03d123792d6ac594bfa67bf6d0c0ab55b6b1fdb6249303fe861f1ccba9a';
      const expectedNpub =
          'npub1zutzeysacnf9rru6zqwmxd54mud0k44tst6l70ja5mhv8jjumytsd2x7nu';

      final derivedHex = Nip06.deriveNostrPrivateKeyHex(mnemonic);
      expect(derivedHex, expectedPrivateKeyHex);

      final keys = Keys(derivedHex);
      expect(keys.npub, expectedNpub);
    });

    test('vector 2: 24-word mnemonic matches the spec exactly', () {
      const mnemonic =
          'what bleak badge arrange retreat wolf trade produce cricket blur garlic valid proud rude strong choose busy staff weather area salt hollow arm fade';
      const expectedPrivateKeyHex =
          'c15d739894c81a2fcfd3a2df85a0d2c0dbc47a280d092799f144d73d7ae78add';
      const expectedNpub =
          'npub16sdj9zv4f8sl85e45vgq9n7nsgt5qphpvmf7vk8r5hhvmdjxx4es8rq74h';

      final derivedHex = Nip06.deriveNostrPrivateKeyHex(mnemonic);
      expect(derivedHex, expectedPrivateKeyHex);

      final keys = Keys(derivedHex);
      expect(keys.npub, expectedNpub);
    });
  });
}
