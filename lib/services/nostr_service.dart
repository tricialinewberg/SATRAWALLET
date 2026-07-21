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
  /// TEMPORARY: logs every step via [debugPrint] and, if [onStep] is
  /// given, also reports it in plain terms for an on-screen debug panel
  /// (see lib/debug/escape_debug_log.dart). Remove [onStep] and its call
  /// sites once alert delivery is confirmed reliable.
  Future<void> sendEscapeAlert({
    String message = 'Alerta ativado. Preciso de ajuda.',
    void Function(String message)? onStep,
  }) async {
    final contacts = await getContacts();
    debugPrint('[NostrService] sendEscapeAlert: ${contacts.length} trusted contact(s) registered');
    onStep?.call('Nostr: ${contacts.length} contato(s) de confiança cadastrado(s).');
    if (contacts.isEmpty) {
      debugPrint('[NostrService] sendEscapeAlert: no trusted contacts, nothing to send');
      onStep?.call('Nostr: nenhum contato cadastrado — nada a enviar.');
      return;
    }

    final keys = await _getOrCreateKeys();
    debugPrint('[NostrService] sendEscapeAlert: sending from npub=${keys.npub}');

    var succeeded = 0;
    await Future.wait(
      contacts.map((contact) async {
        final accepted = await _alertContact(keys: keys, contact: contact, message: message, onStep: onStep);
        if (accepted) succeeded++;
      }),
    );
    debugPrint('[NostrService] sendEscapeAlert: finished processing all contacts');
    onStep?.call('Nostr: concluído — $succeeded de ${contacts.length} contato(s) confirmado(s) por ao menos um relay.');
  }

  /// Returns whether at least one relay confirmed acceptance (`OK true`)
  /// for this contact — the strongest signal we have that the alert
  /// actually reached the network, as opposed to merely "no exception was
  /// thrown".
  Future<bool> _alertContact({
    required Keys keys,
    required TrustedContact contact,
    required String message,
    void Function(String message)? onStep,
  }) async {
    final label = contact.label;
    try {
      debugPrint('[NostrService] "$label": decoding npub ${contact.npub}');
      final decoded = Bech32Entity.decode(payload: contact.npub);
      if (decoded.prefix != Nip19Prefix.npub) {
        final msg = 'Nostr "$label": FALHA — prefixo decodificado é ${decoded.prefix}, não npub';
        debugPrint('[NostrService] $msg');
        onStep?.call(msg);
        return false;
      }
      final recipientPubkey = decoded.data;
      debugPrint('[NostrService] "$label": decoded pubkey=$recipientPubkey');
      onStep?.call('Nostr "$label": npub decodificada com sucesso.');

      final giftWrap = await Nip17.create(
        message: message,
        authorSecretKey: keys.secret,
        recipientPubkey: recipientPubkey,
      );
      debugPrint('[NostrService] "$label": gift wrap created id=${giftWrap.id} kind=${giftWrap.kind}');
      onStep?.call('Nostr "$label": mensagem cifrada criada com sucesso.');

      final accepted = await _publishToAllRelays(label, giftWrap, onStep: onStep);
      debugPrint('[NostrService] "$label": done publishing to all relays (accepted=$accepted)');
      onStep?.call(
        accepted
            ? 'Nostr "$label": confirmado por ao menos um relay.'
            : 'Nostr "$label": FALHA — nenhum relay confirmou o recebimento.',
      );
      return accepted;
    } catch (e, st) {
      // Best-effort: one bad contact must not stop alerts to the rest.
      debugPrint('[NostrService] "$label": FAILED — $e');
      debugPrint('[NostrService] "$label": $st');
      onStep?.call('Nostr "$label": FALHA — $e');
      return false;
    }
  }

  Future<bool> _publishToAllRelays(
    String contactLabel,
    Event event, {
    void Function(String message)? onStep,
  }) async {
    final frame = event.serialize();
    debugPrint(
      '[NostrService] "$contactLabel": publishing event id=${event.id} to ${_relays.length} relay(s)',
    );
    final results = await Future.wait(
      _relays.map((relay) => _publishToRelay(contactLabel, relay, frame, onStep: onStep)),
    );
    return results.any((accepted) => accepted);
  }

  /// Connects to [relayUrl], publishes [frame], and — unlike before — waits
  /// briefly for the relay's `["OK", id, accepted, message]` (or `NOTICE`)
  /// response before closing, logging whatever comes back (or the absence
  /// of a response). Previously this closed the socket immediately after
  /// `add()`, which gave zero visibility into whether a relay actually
  /// accepted the event (e.g. rejected for a bad signature, an
  /// unsupported/rate-limited kind, or some other policy reason) — this is
  /// the most likely explanation for alerts silently not arriving.
  ///
  /// Returns whether the relay explicitly responded `OK ... true`.
  Future<bool> _publishToRelay(
    String contactLabel,
    String relayUrl,
    String frame, {
    void Function(String message)? onStep,
  }) async {
    WebSocket? socket;
    try {
      debugPrint('[NostrService] "$contactLabel" -> $relayUrl: connecting');
      onStep?.call('Nostr "$contactLabel" @ $relayUrl: conectando...');
      socket = await WebSocket.connect(relayUrl).timeout(_relayConnectTimeout);
      debugPrint('[NostrService] "$contactLabel" -> $relayUrl: connected, sending event');
      onStep?.call('Nostr "$contactLabel" @ $relayUrl: conectado, enviando...');

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
        final msg = 'Nostr "$contactLabel" @ $relayUrl: sem resposta OK/NOTICE dentro do tempo limite';
        debugPrint('[NostrService] $msg');
        onStep?.call(msg);
        return false;
      }

      debugPrint('[NostrService] "$contactLabel" -> $relayUrl: response=$raw');
      final accepted = _isOkAccepted(raw);
      onStep?.call('Nostr "$contactLabel" @ $relayUrl: resposta="$raw"');
      return accepted;
    } catch (e) {
      // Best-effort broadcast — a slow/unreachable relay must not block or
      // fail the others; redundancy across relays is the whole point.
      final msg = 'Nostr "$contactLabel" @ $relayUrl: FALHA — $e';
      debugPrint('[NostrService] $msg');
      onStep?.call(msg);
      return false;
    } finally {
      try {
        await socket?.close();
      } catch (_) {
        // Already closed/broken — nothing left to clean up.
      }
    }
  }

  /// Parses a raw relay frame looking for `["OK", "<id>", true|false, "..."]`
  /// and reports whether the relay accepted the event. Anything else (a
  /// `NOTICE`, malformed JSON, `OK ... false`) is treated as not-accepted.
  static bool _isOkAccepted(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List && decoded.length >= 3 && decoded[0] == 'OK') {
        return decoded[2] == true;
      }
    } catch (_) {
      // Not a JSON array we recognize — treat as not-accepted.
    }
    return false;
  }
}
