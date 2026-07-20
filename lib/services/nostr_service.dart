import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nostr/nostr.dart';

/// A trusted contact who receives the NIP-17 escape alert: a display name
/// the user picks plus the contact's npub.
class TrustedContact {
  final String label;
  final String npub;

  const TrustedContact({required this.label, required this.npub});

  Map<String, dynamic> toMap() => {'label': label, 'npub': npub};

  factory TrustedContact.fromMap(Map<String, dynamic> map) => TrustedContact(
        label: map['label'] as String,
        npub: map['npub'] as String,
      );
}

/// Owns this device's disposable Nostr identity and the trusted-contacts
/// list used for the escape alert (NIP-17).
///
/// Follows the same [FlutterSecureStorage] pattern as `BreezService` for
/// the wallet mnemonic: the private key never touches plain storage, and
/// is generated once on first use, then reloaded on every later app open.
/// The trusted-contacts list is stored the same way — it's small (a
/// handful of entries) and reusing secure storage avoids pulling in a
/// second encrypted-storage dependency for one JSON blob.
class NostrService {
  NostrService._();
  static final NostrService instance = NostrService._();

  static const _privateKeyKey = 'satra_nostr_privkey';
  static const _contactsKey = 'satra_nostr_trusted_contacts';

  /// Well-known public relays the escape alert is broadcast to, for
  /// redundancy — if one is down or slow, the others still get the alert.
  static const _relays = [
    'wss://relay.damus.io',
    'wss://nos.lol',
    'wss://relay.primal.net',
  ];

  static const _relayConnectTimeout = Duration(seconds: 8);

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  Keys? _keys;

  Future<Keys> _getOrCreateKeys() async {
    final cached = _keys;
    if (cached != null) return cached;

    final existing = await _secureStorage.read(key: _privateKeyKey);
    if (existing != null && existing.isNotEmpty) {
      final keys = Keys(existing);
      _keys = keys;
      return keys;
    }

    final keys = Keys.generate();
    await _secureStorage.write(key: _privateKeyKey, value: keys.secret);
    _keys = keys;
    return keys;
  }

  /// The current device's npub. For display/debugging only — never shown
  /// to the end user in any screen.
  Future<String> getNpub() async => (await _getOrCreateKeys()).npub;

  /// Validates that [npub] is a well-formed NIP-19 `npub1...` public key
  /// (correct prefix, bech32 checksum, valid length). Delegates to the
  /// `nostr` package's own decoder rather than a hand-rolled regex, the
  /// same way `BreezService` delegates mnemonic validation to `bip39_plus`.
  static bool isValidNpub(String npub) {
    try {
      final decoded = Bech32Entity.decode(payload: npub);
      return decoded.prefix == Nip19Prefix.npub;
    } catch (_) {
      return false;
    }
  }

  Future<List<TrustedContact>> getContacts() async {
    final raw = await _secureStorage.read(key: _contactsKey);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((e) => TrustedContact.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _saveContacts(List<TrustedContact> contacts) async {
    final encoded = jsonEncode(contacts.map((c) => c.toMap()).toList());
    await _secureStorage.write(key: _contactsKey, value: encoded);
  }

  /// Adds (or replaces, if the npub is already present) a trusted contact.
  /// Throws [ArgumentError] if [npub] isn't a valid npub or [label] is empty.
  Future<void> addContact(String npub, String label) async {
    final trimmedNpub = npub.trim();
    final trimmedLabel = label.trim();
    if (!isValidNpub(trimmedNpub)) {
      throw ArgumentError('npub inválida.');
    }
    if (trimmedLabel.isEmpty) {
      throw ArgumentError('Escolha um nome para o contato.');
    }

    final contacts = await getContacts();
    contacts.removeWhere((c) => c.npub == trimmedNpub);
    contacts.add(TrustedContact(label: trimmedLabel, npub: trimmedNpub));
    await _saveContacts(contacts);
  }

  Future<void> removeContact(String npub) async {
    final contacts = await getContacts();
    contacts.removeWhere((c) => c.npub == npub);
    await _saveContacts(contacts);
  }

  /// Sends a NIP-17 encrypted, NIP-59 gift-wrapped DM to every trusted
  /// contact, publishing each to all [_relays] in parallel for redundancy.
  ///
  /// Never throws: an empty contact list is a silent no-op, and a failure
  /// alerting one contact (bad npub, all its relays unreachable, ...) does
  /// not stop alerts to the rest. This is intentional — the caller (the
  /// escape handler) fires this without awaiting it, so there is nothing
  /// meaningful to show the user if part of it fails.
  Future<void> sendEscapeAlert({
    String message = 'Alerta ativado. Preciso de ajuda.',
  }) async {
    final contacts = await getContacts();
    if (contacts.isEmpty) return;

    final keys = await _getOrCreateKeys();

    await Future.wait(
      contacts.map(
        (contact) => _alertContact(keys: keys, contact: contact, message: message),
      ),
    );
  }

  Future<void> _alertContact({
    required Keys keys,
    required TrustedContact contact,
    required String message,
  }) async {
    try {
      final recipientPubkey = Bech32Entity.decode(payload: contact.npub).data;
      final giftWrap = await Nip17.create(
        message: message,
        authorSecretKey: keys.secret,
        recipientPubkey: recipientPubkey,
      );
      await _publishToAllRelays(giftWrap);
    } catch (_) {
      // Best-effort: one bad contact must not stop alerts to the rest.
    }
  }

  Future<void> _publishToAllRelays(Event event) async {
    final frame = event.serialize();
    await Future.wait(_relays.map((relay) => _publishToRelay(relay, frame)));
  }

  Future<void> _publishToRelay(String relayUrl, String frame) async {
    try {
      final socket = await WebSocket.connect(relayUrl).timeout(_relayConnectTimeout);
      socket.add(frame);
      await socket.close();
    } catch (_) {
      // Best-effort broadcast — a slow/unreachable relay must not block or
      // fail the others; redundancy across relays is the whole point.
    }
  }
}
