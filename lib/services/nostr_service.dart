import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
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

  /// How long to wait for a relay's `OK`/`NOTICE` response after
  /// publishing before giving up and closing the socket anyway. Purely for
  /// diagnostics right now (see [_publishToRelay]) — we don't retry or
  /// change behavior based on the response, just log it.
  static const _relayAckTimeout = Duration(seconds: 5);

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
  ///
  /// This is called via `unawaited(...)` from the escape handler, but that
  /// only means the *caller* doesn't wait for it — the returned Future
  /// still runs to completion independently of any Widget's lifecycle.
  /// Nothing here holds a `BuildContext` or is tied to a State object, so
  /// disposing the screen that triggered the escape (which happens almost
  /// immediately, since it's removed from the navigation stack) does not
  /// cancel this work. The only way it wouldn't finish is the OS killing
  /// the process outright, which is outside Flutter's control either way.
  ///
  /// TEMPORARY: logs every step via [debugPrint] for on-device debugging.
  /// Remove these once alert delivery is confirmed reliable.
  Future<void> sendEscapeAlert({
    String message = 'Alerta ativado. Preciso de ajuda.',
  }) async {
    final contacts = await getContacts();
    debugPrint('[NostrService] sendEscapeAlert: ${contacts.length} trusted contact(s) registered');
    if (contacts.isEmpty) {
      debugPrint('[NostrService] sendEscapeAlert: no trusted contacts, nothing to send');
      return;
    }

    final keys = await _getOrCreateKeys();
    debugPrint('[NostrService] sendEscapeAlert: sending from npub=${keys.npub}');

    await Future.wait(
      contacts.map(
        (contact) => _alertContact(keys: keys, contact: contact, message: message),
      ),
    );
    debugPrint('[NostrService] sendEscapeAlert: finished processing all contacts');
  }

  Future<void> _alertContact({
    required Keys keys,
    required TrustedContact contact,
    required String message,
  }) async {
    final label = contact.label;
    try {
      debugPrint('[NostrService] "$label": decoding npub ${contact.npub}');
      final decoded = Bech32Entity.decode(payload: contact.npub);
      if (decoded.prefix != Nip19Prefix.npub) {
        debugPrint('[NostrService] "$label": FAILED — decoded prefix is ${decoded.prefix}, not npub');
        return;
      }
      final recipientPubkey = decoded.data;
      debugPrint('[NostrService] "$label": decoded pubkey=$recipientPubkey');

      final giftWrap = await Nip17.create(
        message: message,
        authorSecretKey: keys.secret,
        recipientPubkey: recipientPubkey,
      );
      debugPrint('[NostrService] "$label": gift wrap created id=${giftWrap.id} kind=${giftWrap.kind}');

      await _publishToAllRelays(label, giftWrap);
      debugPrint('[NostrService] "$label": done publishing to all relays');
    } catch (e, st) {
      // Best-effort: one bad contact must not stop alerts to the rest.
      debugPrint('[NostrService] "$label": FAILED — $e');
      debugPrint('[NostrService] "$label": $st');
    }
  }

  Future<void> _publishToAllRelays(String contactLabel, Event event) async {
    final frame = event.serialize();
    debugPrint(
      '[NostrService] "$contactLabel": publishing event id=${event.id} to ${_relays.length} relay(s)',
    );
    await Future.wait(_relays.map((relay) => _publishToRelay(contactLabel, relay, frame)));
  }

  /// Connects to [relayUrl], publishes [frame], and — unlike before — waits
  /// briefly for the relay's `["OK", id, accepted, message]` (or `NOTICE`)
  /// response before closing, logging whatever comes back (or the absence
  /// of a response). Previously this closed the socket immediately after
  /// `add()`, which gave zero visibility into whether a relay actually
  /// accepted the event (e.g. rejected for a bad signature, an
  /// unsupported/rate-limited kind, or some other policy reason) — this is
  /// the most likely explanation for alerts silently not arriving.
  Future<void> _publishToRelay(String contactLabel, String relayUrl, String frame) async {
    WebSocket? socket;
    try {
      debugPrint('[NostrService] "$contactLabel" -> $relayUrl: connecting');
      socket = await WebSocket.connect(relayUrl).timeout(_relayConnectTimeout);
      debugPrint('[NostrService] "$contactLabel" -> $relayUrl: connected, sending event');

      final response = Completer<String?>();
      final subscription = socket.listen(
        (data) {
          if (!response.isCompleted) response.complete(data.toString());
        },
        onError: (Object e) {
          if (!response.isCompleted) response.complete(null);
        },
        onDone: () {
          if (!response.isCompleted) response.complete(null);
        },
      );

      socket.add(frame);

      final raw = await response.future.timeout(_relayAckTimeout, onTimeout: () => null);
      await subscription.cancel();

      if (raw == null) {
        debugPrint('[NostrService] "$contactLabel" -> $relayUrl: no OK/NOTICE response within timeout');
      } else {
        debugPrint('[NostrService] "$contactLabel" -> $relayUrl: response=$raw');
      }
    } catch (e) {
      // Best-effort broadcast — a slow/unreachable relay must not block or
      // fail the others; redundancy across relays is the whole point.
      debugPrint('[NostrService] "$contactLabel" -> $relayUrl: FAILED — $e');
    } finally {
      try {
        await socket?.close();
      } catch (_) {
        // Already closed/broken — nothing left to clean up.
      }
    }
  }
}
