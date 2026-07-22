import 'dart:convert';
import 'dart:typed_data';

import 'package:bip39_plus/bip39_plus.dart' as bip39;
import 'package:crypto/crypto.dart' as crypto;
import 'package:elliptic/elliptic.dart';

/// Derives a Nostr identity deterministically from a BIP-39 mnemonic, per
/// [NIP-06](https://github.com/nostr-protocol/nips/blob/master/06.md):
/// standard BIP-32 derivation over secp256k1, applied to the mnemonic's
/// BIP-39 seed, at path `m/44'/1237'/<account>'/0/0`.
///
/// Implemented from scratch (textbook BIP-32 child key derivation) rather
/// than pulling in a `bip32` package dependency — none was already present
/// in this project, and the algorithm is small, standard, and easy to
/// audit directly against the spec with the crypto primitives already in
/// use here (`elliptic` for secp256k1 point math, `crypto` for HMAC-SHA512).
///
/// NOT verified against the official NIP-06 test vectors (no network
/// access at implementation time to fetch them) — only against the
/// well-known BIP-32 structure itself. Before relying on this for a real
/// wallet's trusted-contacts recovery, cross-check that the derived nsec
/// imported into a reference Nostr client (e.g. Damus, Amethyst) produces
/// the same npub this code computes for the same mnemonic.
class Nip06 {
  Nip06._();

  static const _hardenedOffset = 0x80000000;
  static final Curve _curve = getS256();

  /// Returns the derived Nostr private key as 64-char lowercase hex,
  /// suitable for passing straight into `Keys(hex)`.
  static String deriveNostrPrivateKeyHex(String mnemonic, {int account = 0}) {
    final seed = bip39.mnemonicToSeed(mnemonic);
    var node = _masterKeyFromSeed(seed);
    node = _deriveChild(node, 44 + _hardenedOffset);
    node = _deriveChild(node, 1237 + _hardenedOffset);
    node = _deriveChild(node, account + _hardenedOffset);
    node = _deriveChild(node, 0); // change
    node = _deriveChild(node, 0); // address index
    return _bytesToHex(node.key);
  }

  static _ExtendedKey _masterKeyFromSeed(Uint8List seed) {
    final i = crypto.Hmac(crypto.sha512, utf8.encode('Bitcoin seed')).convert(seed).bytes;
    return _ExtendedKey(
      key: Uint8List.fromList(i.sublist(0, 32)),
      chainCode: Uint8List.fromList(i.sublist(32)),
    );
  }

  static _ExtendedKey _deriveChild(_ExtendedKey parent, int index) {
    final isHardened = index >= _hardenedOffset;
    final data = BytesBuilder();
    if (isHardened) {
      data.addByte(0);
      data.add(parent.key);
    } else {
      final parentPriv = PrivateKey.fromBytes(_curve, parent.key);
      final parentPub = _curve.privateToPublicKey(parentPriv);
      data.add(_hexToBytes(parentPub.toCompressedHex()));
    }
    data.add(_uint32BE(index));

    final i = crypto.Hmac(crypto.sha512, parent.chainCode).convert(data.toBytes()).bytes;
    final il = i.sublist(0, 32);
    final ir = Uint8List.fromList(i.sublist(32));

    final childKeyInt = (_bytesToBigInt(il) + _bytesToBigInt(parent.key)) % _curve.n;
    if (childKeyInt == BigInt.zero) {
      // Per BIP-32, this index would be invalid and derivation should skip
      // to the next one instead — astronomically unlikely (~2^-127) for
      // any real mnemonic, so treated as a hard failure rather than
      // implemented, to keep this small and auditable.
      throw StateError('BIP-32 derivation produced an invalid (zero) child key — retry not implemented.');
    }

    return _ExtendedKey(key: _bigIntToBytes(childKeyInt, 32), chainCode: ir);
  }

  static BigInt _bytesToBigInt(List<int> bytes) {
    var result = BigInt.zero;
    for (final b in bytes) {
      result = (result << 8) | BigInt.from(b);
    }
    return result;
  }

  static Uint8List _bigIntToBytes(BigInt value, int length) {
    var v = value;
    final bytes = Uint8List(length);
    for (var i = length - 1; i >= 0; i--) {
      bytes[i] = (v & BigInt.from(0xff)).toInt();
      v = v >> 8;
    }
    return bytes;
  }

  static Uint8List _uint32BE(int value) {
    final bytes = Uint8List(4);
    bytes[0] = (value >> 24) & 0xff;
    bytes[1] = (value >> 16) & 0xff;
    bytes[2] = (value >> 8) & 0xff;
    bytes[3] = value & 0xff;
    return bytes;
  }

  static String _bytesToHex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List _hexToBytes(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < result.length; i++) {
      result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }
}

class _ExtendedKey {
  final Uint8List key;
  final Uint8List chainCode;
  _ExtendedKey({required this.key, required this.chainCode});
}
