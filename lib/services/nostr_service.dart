import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nostr/nostr.dart';

import 'breez_service.dart';
import 'nip06.dart';

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

/// Owns this device's Nostr identity and the trusted-contacts list used
/// for the escape alert (NIP-17).
///
/// The identity is derived deterministically from the wallet's BIP-39
/// mnemonic per [NIP-06] (see [Nip06]) rather than generated randomly —
/// restoring the wallet (by seed or physical key) always regenerates the
/// same Nostr keys, so trusted contacts recognize the same npub across
/// reinstalls and the encrypted contacts-list backup below stays
/// addressable to the same identity. There is deliberately no separate
/// stored private key anymore: it's re-derived from [BreezService]'s
/// mnemonic on demand and cached only in memory for the session.
///
/// The trusted-contacts list itself is stored locally (fast, works
/// offline) via [FlutterSecureStorage] and mirrored to the relays already
/// used for the escape alert as a NIP-44-encrypted, self-addressed,
/// parameterized-replaceable event (NIP-78 "application-specific data",
/// kind 30078) — the local copy is the fast day-to-day cache, the relay
/// copy is what [resyncAfterRestore] recovers from after a restore.
///
/// [NIP-06]: https://github.com/nostr-protocol/nips/blob/master/06.md
class NostrService {
  NostrService._();
  static final NostrService instance = NostrService._();

  static const _contactsKey = 'satra_nostr_trusted_contacts';

  /// Event kind and `d` tag identifying the encrypted trusted-contacts
  /// backup among this identity's other NIP-78 app-data events, if any.
  static const _contactsEventKind = 30078;
  static const _contactsDTag = 'satra-wallet:trusted-contacts';

  /// Well-known public relays the escape alert is broadcast to, for
  /// redundancy — if one is down or slow, the others still get the alert.
  /// Also where the encrypted trusted-contacts backup is published/read.
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

  /// How long to wait for a relay to finish sending stored events (EOSE)
  /// when fetching the trusted-contacts backup, before giving up on it.
  static const _relayFetchTimeout = Duration(seconds: 8);

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  Keys? _keys;

  /// Derives (or returns the cached) Nostr [Keys] for the wallet's current
  /// mnemonic. Cached only in memory — cheap enough (a handful of BIP-32
  /// derivation steps) to recompute after a fresh app launch, and caching
  /// beyond the current mnemonic would risk serving a stale identity after
  /// [resetIdentity] is called on a wallet restore.
  Future<Keys> _getOrCreateKeys() async {
    final cached = _keys;
    if (cached != null) return cached;

    final mnemonic = await BreezService.instance.getMnemonic();
    if (mnemonic == null || mnemonic.isEmpty) {
      throw StateError('BreezService wallet must be initialized before deriving a Nostr identity.');
    }

    final keys = Keys(Nip06.deriveNostrPrivateKeyHex(mnemonic));
    _keys = keys;
    return keys;
  }

  /// Drops the cached identity so the next call re-derives it from
  /// whatever mnemonic [BreezService] currently holds. Call this right
  /// after [BreezService.restoreFromMnemonic] — otherwise a cached
  /// identity from the previous wallet would keep being used even though
  /// the underlying mnemonic (and therefore the correct derived identity)
  /// has changed.
  void resetIdentity() {
    _keys = null;
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
  ///
  /// Saves locally first (always succeeds if validation passes), then
  /// best-effort publishes the updated list to the relays as the
  /// recoverable backup — a relay hiccup here must not stop the user from
  /// adding a contact, so it's swallowed rather than rethrown.
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
    await _publishContactsBackup(contacts);
  }

  Future<void> removeContact(String npub) async {
    final contacts = await getContacts();
    contacts.removeWhere((c) => c.npub == npub);
    await _saveContacts(contacts);
    await _publishContactsBackup(contacts);
  }

  /// Best-effort: publishes [contacts] as a NIP-44-encrypted, self-addressed
  /// NIP-78 event (kind [_contactsEventKind], `d` tag [_contactsDTag]) to
  /// all [_relays]. Being parameterized-replaceable, each publish overwrites
  /// the previous backup on well-behaved relays rather than accumulating
  /// old copies. Never throws — see [addContact]/[removeContact].
  Future<void> _publishContactsBackup(List<TrustedContact> contacts) async {
    try {
      final keys = await _getOrCreateKeys();
      final plaintext = jsonEncode(contacts.map((c) => c.toMap()).toList());
      final encrypted = await Nip44.encrypt(
        plaintext: plaintext,
        senderSecretKey: keys.secret,
        recipientPubkey: keys.public,
      );
      final event = Event.from(
        kind: _contactsEventKind,
        content: encrypted,
        secretKey: keys.secret,
        tags: [
          ['d', _contactsDTag],
        ],
      );
      await _publishToAllRelays('contacts-backup', event);
    } catch (e) {
      debugPrint('[NostrService] _publishContactsBackup: FAILED — $e');
    }
  }

  /// Fetches the most recent encrypted trusted-contacts backup (see
  /// [_publishContactsBackup]) across all [_relays] and decrypts it.
  /// Returns null if no relay has one, or if decryption/parsing fails.
  Future<List<TrustedContact>?> _fetchContactsBackup() async {
    final keys = await _getOrCreateKeys();
    final events = await Future.wait(
      _relays.map((relay) => _fetchLatestContactsEvent(relay, keys.public)),
    );

    Event? latest;
    for (final event in events) {
      if (event == null) continue;
      if (latest == null || event.createdAt > latest.createdAt) latest = event;
    }
    if (latest == null) {
      debugPrint('[NostrService] _fetchContactsBackup: no backup found on any relay');
      return null;
    }

    try {
      final decrypted = await Nip44.decrypt(
        payload: latest.content,
        recipientSecretKey: keys.secret,
        senderPubkey: keys.public,
      );
      final decoded = jsonDecode(decrypted) as List<dynamic>;
      return decoded
          .map((e) => TrustedContact.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[NostrService] _fetchContactsBackup: FAILED to decrypt/parse — $e');
      return null;
    }
  }

  /// Subscribes on [relayUrl] for this identity's latest trusted-contacts
  /// backup event and returns it (or null on timeout/error/not found).
  /// Verifies the event's signature — a relay could otherwise inject a
  /// forged event under this pubkey since the REQ filter alone isn't
  /// enforced by the protocol, only conventionally honored by relays.
  Future<Event?> _fetchLatestContactsEvent(String relayUrl, String pubkeyHex) async {
    WebSocket? socket;
    StreamSubscription<dynamic>? subscription;
    try {
      socket = await WebSocket.connect(relayUrl).timeout(_relayConnectTimeout);
      final request = Request(
        subscriptionId: 'satra-contacts-${DateTime.now().microsecondsSinceEpoch}',
        filters: [
          Filter(
            authors: [pubkeyHex],
            kinds: [_contactsEventKind],
            tagFilters: {
              'd': [_contactsDTag],
            },
            limit: 1,
          ),
        ],
      );

      Event? found;
      final eose = Completer<void>();
      subscription = socket.listen(
        (data) {
          try {
            final frame = jsonDecode(data.toString());
            if (frame is! List || frame.isEmpty) return;
            if (frame[0] == 'EVENT') {
              final event = Event.deserialize(data.toString(), verify: true);
              if (found == null || event.createdAt > found!.createdAt) found = event;
            } else if (frame[0] == 'EOSE') {
              if (!eose.isCompleted) eose.complete();
            }
          } catch (_) {
            // Malformed/unverifiable frame — ignore and keep listening.
          }
        },
        onError: (Object _) {
          if (!eose.isCompleted) eose.complete();
        },
        onDone: () {
          if (!eose.isCompleted) eose.complete();
        },
      );

      socket.add(request.serialize());
      await eose.future.timeout(_relayFetchTimeout, onTimeout: () {});
      return found;
    } catch (e) {
      debugPrint('[NostrService] _fetchLatestContactsEvent @ $relayUrl: FAILED — $e');
      return null;
    } finally {
      await subscription?.cancel();
      try {
        await socket?.close();
      } catch (_) {
        // Already closed/broken — nothing left to clean up.
      }
    }
  }

  /// Call after [BreezService.restoreFromMnemonic] succeeds (both the
  /// seed-paste and physical-key restore paths): drops the cached identity
  /// so it's re-derived from the now-current mnemonic, then attempts to
  /// recover the trusted-contacts list for that identity from the relays.
  ///
  /// Never throws — a failed recovery just leaves the local contacts list
  /// as-is (whatever this device already had, likely empty on a fresh
  /// install) rather than blocking or failing the restore itself, which
  /// has already succeeded by the time this runs. If a backup IS found, it
  /// replaces the local list outright — this is the recovery path, and the
  /// relay copy is the source of truth for it.
  Future<void> resyncAfterRestore() async {
    resetIdentity();
    try {
      final recovered = await _fetchContactsBackup();
      if (recovered != null) {
        await _saveContacts(recovered);
        debugPrint('[NostrService] resyncAfterRestore: recovered ${recovered.length} contact(s) from relays');
      }
    } catch (e) {
      debugPrint('[NostrService] resyncAfterRestore: FAILED — $e');
    }
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

    final succeeded = await sendDirectMessageToAll(contacts, message, onStep: onStep);
    debugPrint('[NostrService] sendEscapeAlert: finished processing all contacts');
    onStep?.call('Nostr: concluído — $succeeded de ${contacts.length} contato(s) confirmado(s) por ao menos um relay.');
  }

  /// Sends [message] as a NIP-17 encrypted, NIP-59 gift-wrapped DM to every
  /// entry in [recipients], publishing each to all [_relays] in parallel.
  /// The same delivery mechanism [sendEscapeAlert] uses, generalized so
  /// other features addressed to a list of npubs (e.g. the inheritance
  /// feature's heir notifications — see `InheritanceService`) don't need
  /// their own copy of the gift-wrap/relay-publish plumbing.
  ///
  /// Returns how many recipients had at least one relay confirm acceptance
  /// (`OK true`). Never throws — a bad npub or an unreachable relay for one
  /// recipient must not stop delivery to the rest; see [_alertContact].
  Future<int> sendDirectMessageToAll(
    List<TrustedContact> recipients,
    String message, {
    void Function(String message)? onStep,
  }) async {
    if (recipients.isEmpty) return 0;

    final keys = await _getOrCreateKeys();
    debugPrint('[NostrService] sendDirectMessageToAll: sending from npub=${keys.npub} to ${recipients.length} recipient(s)');

    var succeeded = 0;
    await Future.wait(
      recipients.map((recipient) async {
        final accepted = await _alertContact(keys: keys, contact: recipient, message: message, onStep: onStep);
        if (accepted) succeeded++;
      }),
    );
    return succeeded;
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
