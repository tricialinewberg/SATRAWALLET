import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nostr/nostr.dart';

import 'breez_service.dart';
import 'inheritance_heartbeat.dart';
import 'nip06.dart';

/// A trusted contact who receives the NIP-17 escape alert: a display name
/// the user picks plus the contact's npub.
class TrustedContact {
  final String label;
  final String npub;
  final String? relationship;
  final double? sharePercentage;
  final List<String> inboxRelays;
  final bool inboxRelaysManual;
  final DateTime? lastTestedAt;
  final bool? lastTestAccepted;
  final String? lastTestError;
  final String? verificationChallengeHash;
  final DateTime? verificationExpiresAt;
  final DateTime? verifiedAt;

  const TrustedContact({
    required this.label,
    required this.npub,
    this.relationship,
    this.sharePercentage,
    this.inboxRelays = const [],
    this.inboxRelaysManual = false,
    this.lastTestedAt,
    this.lastTestAccepted,
    this.lastTestError,
    this.verificationChallengeHash,
    this.verificationExpiresAt,
    this.verifiedAt,
  });

  TrustedContact copyWith({
    String? label,
    String? npub,
    String? relationship,
    double? sharePercentage,
    List<String>? inboxRelays,
    bool? inboxRelaysManual,
    DateTime? lastTestedAt,
    bool? lastTestAccepted,
    String? lastTestError,
    bool clearLastTestError = false,
    String? verificationChallengeHash,
    DateTime? verificationExpiresAt,
    DateTime? verifiedAt,
    bool clearVerificationChallenge = false,
  }) =>
      TrustedContact(
        label: label ?? this.label,
        npub: npub ?? this.npub,
        relationship: relationship ?? this.relationship,
        sharePercentage: sharePercentage ?? this.sharePercentage,
        inboxRelays: inboxRelays ?? this.inboxRelays,
        inboxRelaysManual: inboxRelaysManual ?? this.inboxRelaysManual,
        lastTestedAt: lastTestedAt ?? this.lastTestedAt,
        lastTestAccepted: lastTestAccepted ?? this.lastTestAccepted,
        lastTestError:
            clearLastTestError ? null : (lastTestError ?? this.lastTestError),
        verificationChallengeHash: clearVerificationChallenge
            ? null
            : (verificationChallengeHash ?? this.verificationChallengeHash),
        verificationExpiresAt: clearVerificationChallenge
            ? null
            : (verificationExpiresAt ?? this.verificationExpiresAt),
        verifiedAt: verifiedAt ?? this.verifiedAt,
      );

  Map<String, dynamic> toMap() => {
        'label': label,
        'npub': npub,
        'relationship': relationship,
        'sharePercentage': sharePercentage,
        'inboxRelays': inboxRelays,
        'inboxRelaysManual': inboxRelaysManual,
        'lastTestedAt': lastTestedAt?.toIso8601String(),
        'lastTestAccepted': lastTestAccepted,
        'lastTestError': lastTestError,
        'verificationChallengeHash': verificationChallengeHash,
        'verificationExpiresAt': verificationExpiresAt?.toIso8601String(),
        'verifiedAt': verifiedAt?.toIso8601String(),
      };

  factory TrustedContact.fromMap(Map<String, dynamic> map) => TrustedContact(
        label: map['label'] as String,
        npub: map['npub'] as String,
        relationship: map['relationship'] as String?,
        sharePercentage: (map['sharePercentage'] as num?)?.toDouble(),
        inboxRelays: (map['inboxRelays'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(),
        inboxRelaysManual: map['inboxRelaysManual'] as bool? ?? false,
        lastTestedAt: DateTime.tryParse(map['lastTestedAt'] as String? ?? ''),
        lastTestAccepted: map['lastTestAccepted'] as bool?,
        lastTestError: map['lastTestError'] as String?,
        verificationChallengeHash: map['verificationChallengeHash'] as String?,
        verificationExpiresAt:
            DateTime.tryParse(map['verificationExpiresAt'] as String? ?? ''),
        verifiedAt: DateTime.tryParse(map['verifiedAt'] as String? ?? ''),
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
  static const _directMessageRelayListKind = 10050;

  /// Kind and `d`-tag prefix for the pre-published inheritance vault.
  /// The wallet owner publishes one such event per heir, encrypted with
  /// NIP-44 to that heir's pubkey, as a NIP-78 parameterized-replaceable
  /// event (kind 30078). The `d`-tag embeds the heir's pubkey so each
  /// heir's vault is an independent replaceable event, and so an heir can
  /// find theirs by filtering on `d` starting with
  /// [_vaultDTagPrefix] followed by their own pubkey hex.
  ///
  /// Content is the JSON envelope produced by [NfcCredentialCrypto.encrypt]
  /// (Argon2id + AES-GCM), which is password-protected on top of NIP-44:
  /// even an heir who can decrypt the NIP-44 layer still needs the release
  /// password (shared out-of-band in life, e.g. on a sealed card) to
  /// recover the actual mnemonic. Pre-publishing means the vault is
  /// available on the relays regardless of whether the owner's phone ever
  /// opens again — the core property the inheritance feature needs to be
  /// honest and real.
  static const _vaultEventKind = 30078;
  static const _vaultDTagPrefix = 'satra-wallet:inheritance:vault:';

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

  /// Public for the external observer, which must query the exact same
  /// redundant relay set without gaining access to wallet secrets.
  static List<String> get inheritanceRelays => List.unmodifiable(_relays);

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
      throw StateError(
          'BreezService wallet must be initialized before deriving a Nostr identity.');
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

  Future<void> setContactInboxRelays(String npub, List<String> relays) async {
    final validated = validateInboxRelays(relays);
    final contacts = await getContacts();
    final index = contacts.indexWhere((contact) => contact.npub == npub);
    if (index < 0) throw StateError('Contato não encontrado.');
    contacts[index] = contacts[index].copyWith(
      inboxRelays: validated,
      inboxRelaysManual: true,
    );
    await _saveContacts(contacts);
    await _publishContactsBackup(contacts);
  }

  Future<void> recordContactTest(
      String npub, DirectMessageDelivery delivery) async {
    final contacts = await getContacts();
    final index = contacts.indexWhere((contact) => contact.npub == npub);
    if (index < 0) return;
    final current = contacts[index];
    contacts[index] = current.copyWith(
      inboxRelays: delivery.inboxRelays.isEmpty
          ? current.inboxRelays
          : delivery.inboxRelays,
      inboxRelaysManual: delivery.usedManualRelays || current.inboxRelaysManual,
      lastTestedAt: DateTime.now(),
      lastTestAccepted: delivery.accepted,
      lastTestError: delivery.error,
      clearLastTestError: delivery.error == null,
      verificationChallengeHash:
          delivery.accepted ? delivery.verificationChallengeHash : null,
      verificationExpiresAt:
          delivery.accepted ? delivery.verificationExpiresAt : null,
      clearVerificationChallenge: !delivery.accepted,
    );
    await _saveContacts(contacts);
    await _publishContactsBackup(contacts);
  }

  static List<String> validateInboxRelays(List<String> relays) {
    final result = <String>[];
    for (final raw in relays) {
      final relay = raw.trim();
      final uri = Uri.tryParse(relay);
      if (uri == null || uri.scheme != 'wss' || uri.host.isEmpty) {
        throw ArgumentError('Relay inválido: $raw');
      }
      if (!result.contains(relay)) result.add(relay);
    }
    if (result.isEmpty) throw ArgumentError('Informe ao menos um relay.');
    if (result.length > 3) throw ArgumentError('Use no máximo três relays.');
    return result;
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
      debugPrint(
          '[NostrService] _fetchContactsBackup: no backup found on any relay');
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
      debugPrint(
          '[NostrService] _fetchContactsBackup: FAILED to decrypt/parse — $e');
      return null;
    }
  }

  /// Subscribes on [relayUrl] for this identity's latest trusted-contacts
  /// backup event and returns it (or null on timeout/error/not found).
  /// Verifies the event's signature — a relay could otherwise inject a
  /// forged event under this pubkey since the REQ filter alone isn't
  /// enforced by the protocol, only conventionally honored by relays.
  Future<Event?> _fetchLatestContactsEvent(
      String relayUrl, String pubkeyHex) async {
    WebSocket? socket;
    StreamSubscription<dynamic>? subscription;
    try {
      socket = await WebSocket.connect(relayUrl).timeout(_relayConnectTimeout);
      final request = Request(
        subscriptionId:
            'satra-contacts-${DateTime.now().microsecondsSinceEpoch}',
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
              if (found == null || event.createdAt > found!.createdAt) {
                found = event;
              }
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
      debugPrint(
          '[NostrService] _fetchLatestContactsEvent @ $relayUrl: FAILED — $e');
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
        debugPrint(
            '[NostrService] resyncAfterRestore: recovered ${recovered.length} contact(s) from relays');
      }
    } catch (e) {
      debugPrint('[NostrService] resyncAfterRestore: FAILED — $e');
    }
  }

  /// Publishes a signed, secret-free inheritance heartbeat to all relays.
  /// At least one explicit `OK true` is required for [accepted] to be true.
  Future<InheritanceHeartbeatPublication> publishInheritanceHeartbeat({
    required int sequence,
    required DateTime issuedAt,
    required Duration inactivityDuration,
    required Duration graceDuration,
    required bool enabled,
  }) async {
    final keys = await _getOrCreateKeys();
    final event = InheritanceHeartbeat.createSignedEvent(
      secretKey: keys.secret,
      sequence: sequence,
      issuedAt: issuedAt,
      inactivityDuration: inactivityDuration,
      graceDuration: graceDuration,
      enabled: enabled,
    );
    final accepted = await _publishToAllRelays('inheritance-heartbeat', event);
    return InheritanceHeartbeatPublication(
      eventId: event.id,
      ownerPubkey: event.pubkey,
      accepted: accepted,
    );
  }

  /// Pre-publishes the password-encrypted recovery vault for a single heir.
  /// The envelope (already produced by [NfcCredentialCrypto.encrypt]) is
  /// wrapped a second time with NIP-44 to [heirPubkeyHex], so only that
  /// heir can read it from the relays. The `d`-tag embeds the heir pubkey
  /// so each heir's vault is an independent NIP-78 replaceable event and
  /// can be filtered deterministically.
  ///
  /// Returns whether at least one relay accepted the event. Never throws
  /// — best-effort, like the other publish paths: a relay hiccup during
  /// setup must not abort the whole inheritance enable flow.
  Future<bool> publishInheritanceVault({
    required String heirPubkeyHex,
    required String encryptedEnvelopeJson,
  }) async {
    try {
      final keys = await _getOrCreateKeys();
      final encrypted = await Nip44.encrypt(
        plaintext: encryptedEnvelopeJson,
        senderSecretKey: keys.secret,
        recipientPubkey: heirPubkeyHex,
      );
      final dTag = '$_vaultDTagPrefix$heirPubkeyHex';
      final event = Event.from(
        kind: _vaultEventKind,
        content: encrypted,
        secretKey: keys.secret,
        tags: [
          ['d', dTag],
          ['p', heirPubkeyHex],
        ],
      );
      final accepted = await _publishToAllRelays('inheritance-vault', event);
      return accepted;
    } catch (e) {
      debugPrint('[NostrService] publishInheritanceVault: FAILED — $e');
      return false;
    }
  }

  /// Fetches and decrypts the inheritance vault that [ownerPubkeyHex]
  /// pre-published for THIS device's Nostr identity (see
  /// [publishInheritanceVault]). The vault is a NIP-78 replaceable event
  /// (kind 30078) whose `d`-tag embeds the heir's pubkey, and whose content
  /// is NIP-44-encrypted to that heir. This method uses the keys derived
  /// from this device's own wallet mnemonic (via [NIP-06]) — so it only
  /// works if the heir has a Satra wallet configured whose derived npub
  /// matches the one the owner registered. If the heir installed fresh and
  /// has no wallet, they must use the DM path (the envelope was also sent
  /// via NIP-17 DM, which is visible in any normal Nostr client like Damus).
  ///
  /// Returns the decrypted envelope JSON (ready for
  /// [NfcCredentialCrypto.decrypt] with the release password), or null if
  /// no vault was found, no relay responded, or decryption failed.
  Future<String?> fetchInheritanceVault(String ownerPubkeyHex) async {
    try {
      final keys = await _getOrCreateKeys();
      final dTag = '$_vaultDTagPrefix${keys.public}';
      final events = await Future.wait(
        _relays.map(
          (relay) => _fetchLatestVaultEvent(relay, ownerPubkeyHex, dTag),
        ),
      );

      Event? latest;
      for (final event in events) {
        if (event == null) continue;
        if (latest == null || event.createdAt > latest.createdAt) {
          latest = event;
        }
      }
      if (latest == null) {
        debugPrint(
            '[NostrService] fetchInheritanceVault: no vault found for owner=$ownerPubkeyHex heir=${keys.public}');
        return null;
      }

      final decrypted = await Nip44.decrypt(
        payload: latest.content,
        recipientSecretKey: keys.secret,
        senderPubkey: ownerPubkeyHex,
      );
      return decrypted;
    } catch (e) {
      debugPrint('[NostrService] fetchInheritanceVault: FAILED — $e');
      return null;
    }
  }

  Future<Event?> _fetchLatestVaultEvent(
    String relayUrl,
    String ownerPubkeyHex,
    String dTag,
  ) async {
    WebSocket? socket;
    StreamSubscription<dynamic>? subscription;
    try {
      socket = await WebSocket.connect(relayUrl).timeout(_relayConnectTimeout);
      final request = Request(
        subscriptionId: 'satra-vault-${DateTime.now().microsecondsSinceEpoch}',
        filters: [
          Filter(
            authors: [ownerPubkeyHex],
            kinds: const [_vaultEventKind],
            tagFilters: {
              'd': [dTag],
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
              if (event.pubkey == ownerPubkeyHex &&
                  (found == null || event.createdAt > found!.createdAt)) {
                found = event;
              }
            } else if (frame[0] == 'EOSE') {
              if (!eose.isCompleted) eose.complete();
            }
          } catch (_) {
            // Ignore malformed or forged frames.
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
    } catch (_) {
      return null;
    } finally {
      await subscription?.cancel();
      try {
        await socket?.close();
      } catch (_) {
        // Already closed.
      }
    }
  }

  /// Reads and validates the newest heartbeat for [ownerPubkeyHex] from all
  /// configured relays. The highest sequence wins; creation time and event
  /// id provide deterministic tie-breakers for inconsistent relay views.
  Future<InheritanceHeartbeat?> fetchLatestInheritanceHeartbeat(
    String ownerPubkeyHex,
  ) async {
    final events = await Future.wait(
      _relays.map(
        (relay) => _fetchLatestInheritanceHeartbeatEvent(
          relay,
          ownerPubkeyHex,
        ),
      ),
    );

    InheritanceHeartbeat? latest;
    for (final event in events) {
      if (event == null) continue;
      if (latest == null || _heartbeatComesAfter(event, latest)) {
        latest = event;
      }
    }
    return latest;
  }

  static bool _heartbeatComesAfter(
    InheritanceHeartbeat candidate,
    InheritanceHeartbeat current,
  ) {
    if (candidate.sequence != current.sequence) {
      return candidate.sequence > current.sequence;
    }
    final timeComparison = candidate.issuedAt.compareTo(current.issuedAt);
    if (timeComparison != 0) return timeComparison > 0;
    return candidate.eventId.compareTo(current.eventId) < 0;
  }

  Future<InheritanceHeartbeat?> _fetchLatestInheritanceHeartbeatEvent(
    String relayUrl,
    String ownerPubkeyHex,
  ) async {
    WebSocket? socket;
    StreamSubscription<dynamic>? subscription;
    try {
      socket = await WebSocket.connect(relayUrl).timeout(_relayConnectTimeout);
      final request = Request(
        subscriptionId:
            'satra-heartbeat-${DateTime.now().microsecondsSinceEpoch}',
        filters: [
          Filter(
            authors: [ownerPubkeyHex],
            kinds: const [InheritanceHeartbeat.eventKind],
            tagFilters: const {
              'd': [InheritanceHeartbeat.eventDTag],
            },
            limit: 1,
          ),
        ],
      );

      InheritanceHeartbeat? found;
      final eose = Completer<void>();
      subscription = socket.listen(
        (data) {
          try {
            final frame = jsonDecode(data.toString());
            if (frame is! List || frame.isEmpty) return;
            if (frame[0] == 'EVENT') {
              final event = Event.deserialize(data.toString(), verify: true);
              final heartbeat = InheritanceHeartbeat.fromEvent(event);
              if (heartbeat.ownerPubkey != ownerPubkeyHex) return;
              if (found == null || _heartbeatComesAfter(heartbeat, found!)) {
                found = heartbeat;
              }
            } else if (frame[0] == 'EOSE') {
              if (!eose.isCompleted) eose.complete();
            }
          } catch (_) {
            // Ignore malformed, forged or unrelated relay frames.
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
      debugPrint(
        '[NostrService] inheritance heartbeat fetch @ $relayUrl: FAILED — $e',
      );
      return null;
    } finally {
      await subscription?.cancel();
      try {
        await socket?.close();
      } catch (_) {
        // Already closed.
      }
    }
  }

  /// Sends a NIP-17 encrypted, NIP-59 gift-wrapped DM to every trusted
  /// contact, publishing each to all [_relays] in parallel for redundancy.
  ///
  /// Returns how many contacts had the message accepted by at least one
  /// inbox relay. An empty contact list returns zero, and a failure alerting
  /// one contact does not stop attempts to the rest.
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
  Future<int> sendEscapeAlert(
      {String message = 'Alerta ativado. Preciso de ajuda.'}) async {
    final contacts = await getContacts();
    if (contacts.isEmpty) return 0;
    return sendDirectMessageToAll(contacts, message);
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
      List<TrustedContact> recipients, String message) async {
    if (recipients.isEmpty) return 0;

    final keys = await _getOrCreateKeys();
    var succeeded = 0;
    await Future.wait(
      recipients.map((recipient) async {
        final accepted = await _alertContact(
            keys: keys, contact: recipient, message: message);
        if (accepted) succeeded++;
      }),
    );
    return succeeded;
  }

  Future<DirectMessageDelivery> sendContactTest(
      TrustedContact recipient) async {
    final keys = await _getOrCreateKeys();
    final code = (Random.secure().nextInt(900000) + 100000).toString();
    final expiresAt = DateTime.now().toUtc().add(const Duration(hours: 24));
    final delivery = await _deliverDirectMessage(
      keys: keys,
      contact: recipient,
      message: 'Satra Wallet — teste de contato\n\n'
          'Você foi cadastrado como pessoa de confiança. Nenhuma informação '
          'financeira ou frase de recuperação foi compartilhada.\n\n'
          'Código de confirmação: $code\n'
          'Informe este código ao titular nas próximas 24 horas.',
    );
    if (!delivery.accepted) return delivery;
    return delivery.copyWith(
      verificationChallengeHash: hashVerificationCode(code),
      verificationExpiresAt: expiresAt,
    );
  }

  static String hashVerificationCode(String code) =>
      crypto.sha256.convert(utf8.encode(code.trim())).toString();

  static bool verificationCodeMatches(TrustedContact contact, String code,
      {DateTime? now}) {
    final hash = contact.verificationChallengeHash;
    final expiresAt = contact.verificationExpiresAt;
    if (hash == null || expiresAt == null) return false;
    if (!(now ?? DateTime.now()).toUtc().isBefore(expiresAt.toUtc())) {
      return false;
    }
    return hashVerificationCode(code) == hash;
  }

  Future<bool> verifyContactCode(String npub, String code) async {
    final contacts = await getContacts();
    final index = contacts.indexWhere((contact) => contact.npub == npub);
    if (index < 0 || !verificationCodeMatches(contacts[index], code)) {
      return false;
    }
    contacts[index] = contacts[index].copyWith(
      verifiedAt: DateTime.now(),
      clearVerificationChallenge: true,
    );
    await _saveContacts(contacts);
    await _publishContactsBackup(contacts);
    return true;
  }

  /// Returns whether at least one relay confirmed acceptance (`OK true`)
  /// for this contact — the strongest signal we have that the alert
  /// actually reached the network, as opposed to merely "no exception was
  /// thrown".
  Future<bool> _alertContact({
    required Keys keys,
    required TrustedContact contact,
    required String message,
  }) async {
    final delivery = await _deliverDirectMessage(
      keys: keys,
      contact: contact,
      message: message,
    );
    return delivery.accepted;
  }

  Future<DirectMessageDelivery> _deliverDirectMessage({
    required Keys keys,
    required TrustedContact contact,
    required String message,
  }) async {
    final label = contact.label;
    try {
      final decoded = Bech32Entity.decode(payload: contact.npub);
      if (decoded.prefix != Nip19Prefix.npub) {
        debugPrint(
            '[NostrService] "$label": FALHA — prefixo decodificado é ${decoded.prefix}, não npub');
        return DirectMessageDelivery.invalidRecipient(contact.npub);
      }

      final discoveredRelays = await discoverDirectMessageRelays(decoded.data);
      final usedManualRelays = discoveredRelays.isEmpty;
      final inboxRelays =
          discoveredRelays.isNotEmpty ? discoveredRelays : contact.inboxRelays;
      if (inboxRelays.isEmpty) {
        return DirectMessageDelivery(
          recipientNpub: contact.npub,
          inboxRelays: const [],
          acceptedRelays: const [],
          usedManualRelays: false,
          error:
              'A pessoa ainda não publicou relays de mensagens NIP-17 (kind 10050).',
        );
      }

      final giftWrap = await Nip17.create(
        message: message,
        authorSecretKey: keys.secret,
        recipientPubkey: decoded.data,
      );
      final acceptedRelays =
          await _publishToRelays(label, giftWrap, inboxRelays);
      return DirectMessageDelivery(
        recipientNpub: contact.npub,
        inboxRelays: inboxRelays,
        acceptedRelays: acceptedRelays,
        usedManualRelays: usedManualRelays,
        error: acceptedRelays.isEmpty
            ? 'Nenhum relay de entrada confirmou a mensagem.'
            : null,
      );
    } catch (e) {
      // Best-effort: one bad contact must not stop alerts to the rest.
      debugPrint('[NostrService] "$label": FAILED — $e');
      return DirectMessageDelivery(
        recipientNpub: contact.npub,
        inboxRelays: const [],
        acceptedRelays: const [],
        usedManualRelays: false,
        error: e.toString(),
      );
    }
  }

  /// Finds the recipient's NIP-17 inbox relays from their newest signed
  /// kind-10050 event. With no result we do not guess a delivery relay.
  Future<List<String>> discoverDirectMessageRelays(
      String recipientPubkeyHex) async {
    final events = await Future.wait(
      _relays.map((relay) => _fetchDmRelayList(relay, recipientPubkeyHex)),
    );
    Event? latest;
    for (final event in events) {
      if (event == null) continue;
      if (latest == null ||
          event.createdAt > latest.createdAt ||
          (event.createdAt == latest.createdAt &&
              event.id.compareTo(latest.id) < 0)) {
        latest = event;
      }
    }
    if (latest == null) return const [];

    final result = <String>[];
    for (final tag in latest.tags) {
      if (tag.length < 2 || tag[0] != 'relay') continue;
      final uri = Uri.tryParse(tag[1]);
      if (uri == null || (uri.scheme != 'wss' && uri.scheme != 'ws')) {
        continue;
      }
      if (!result.contains(tag[1])) result.add(tag[1]);
      if (result.length == 3) break;
    }
    return result;
  }

  Future<Event?> _fetchDmRelayList(
      String relayUrl, String recipientPubkeyHex) async {
    WebSocket? socket;
    StreamSubscription<dynamic>? subscription;
    try {
      socket = await WebSocket.connect(relayUrl).timeout(_relayConnectTimeout);
      final request = Request(
        subscriptionId:
            'satra-dm-relays-${DateTime.now().microsecondsSinceEpoch}',
        filters: [
          Filter(
            authors: [recipientPubkeyHex],
            kinds: const [_directMessageRelayListKind],
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
              if (event.pubkey == recipientPubkeyHex &&
                  event.kind == _directMessageRelayListKind &&
                  (found == null || event.createdAt > found!.createdAt)) {
                found = event;
              }
            } else if (frame[0] == 'EOSE' || frame[0] == 'CLOSED') {
              if (!eose.isCompleted) eose.complete();
            }
          } catch (_) {
            // Ignore malformed or forged relay frames.
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
    } catch (_) {
      return null;
    } finally {
      await subscription?.cancel();
      try {
        await socket?.close();
      } catch (_) {
        // Already closed.
      }
    }
  }

  Future<bool> _publishToAllRelays(String contactLabel, Event event) async {
    final accepted = await _publishToRelays(contactLabel, event, _relays);
    return accepted.isNotEmpty;
  }

  Future<List<String>> _publishToRelays(
      String contactLabel, Event event, List<String> relays) async {
    final frame = event.serialize();
    final results = await Future.wait(
      relays.map((relay) async =>
          (relay, await _publishToRelay(contactLabel, relay, frame))),
    );
    return [
      for (final result in results)
        if (result.$2) result.$1
    ];
  }

  /// Connects to [relayUrl], publishes [frame], and waits for the relay's
  /// `["OK", id, accepted, message]` response before closing. `NOTICE`
  /// frames are deliberately ignored: relays commonly emit them for flow
  /// control or policy info at any time, and completing on the first frame
  /// (as a previous version did) meant a `NOTICE` arriving before `OK`
  /// silently discarded a real `OK true`, deflating the accepted count.
  ///
  /// Only an `OK` whose event id matches the published event is honored —
  /// so a stale `OK` from another publisher on a shared socket (extremely
  /// unlikely here since each call opens its own socket) can't be mistaken
  /// for ours.
  ///
  /// Returns whether the relay explicitly responded `OK ... true`.
  Future<bool> _publishToRelay(
      String contactLabel, String relayUrl, String frame) async {
    WebSocket? socket;
    try {
      socket = await WebSocket.connect(relayUrl).timeout(_relayConnectTimeout);

      final eventId = _extractEventId(frame);
      final okCompleter = Completer<bool>();
      final subscription = socket.listen(
        (data) {
          try {
            final decoded = jsonDecode(data.toString());
            if (decoded is! List || decoded.isEmpty) return;
            if (decoded[0] == 'OK' && decoded.length >= 3) {
              if (eventId == null || decoded[1] == eventId) {
                if (!okCompleter.isCompleted) {
                  okCompleter.complete(decoded[2] == true);
                }
              }
            }
            // NOTICE and any other frame: keep waiting for OK within the
            // ack timeout. Relays may send NOTICE at any time.
          } catch (_) {
            // Malformed frame — keep listening.
          }
        },
        onError: (Object e) {
          if (!okCompleter.isCompleted) okCompleter.complete(false);
        },
        onDone: () {
          if (!okCompleter.isCompleted) okCompleter.complete(false);
        },
      );

      socket.add(frame);

      final accepted = await okCompleter.future
          .timeout(_relayAckTimeout, onTimeout: () => false);
      await subscription.cancel();
      return accepted;
    } catch (e) {
      // Best-effort broadcast — a slow/unreachable relay must not block or
      // fail the others; redundancy across relays is the whole point.
      debugPrint('[NostrService] "$contactLabel" @ $relayUrl: FALHA — $e');
      return false;
    } finally {
      try {
        await socket?.close();
      } catch (_) {
        // Already closed/broken — nothing left to clean up.
      }
    }
  }

  /// Pulls the event id out of a `["EVENT", {...}]` publish frame so the
  /// matching `["OK", id, ...]` can be positively correlated. Returns null
  /// for anything that isn't a recognized EVENT frame — in which case
  /// [_publishToRelay] falls back to accepting any `OK true`.
  static String? _extractEventId(String frame) {
    try {
      final decoded = jsonDecode(frame);
      if (decoded is List && decoded.length >= 2 && decoded[0] == 'EVENT') {
        final event = decoded[1];
        if (event is Map) return event['id'] as String?;
      }
    } catch (_) {
      // Not a JSON EVENT frame — caller falls back to lenient matching.
    }
    return null;
  }
}

class InheritanceHeartbeatPublication {
  final String eventId;
  final String ownerPubkey;
  final bool accepted;

  const InheritanceHeartbeatPublication({
    required this.eventId,
    required this.ownerPubkey,
    required this.accepted,
  });
}

class DirectMessageDelivery {
  final String recipientNpub;
  final List<String> inboxRelays;
  final List<String> acceptedRelays;
  final bool usedManualRelays;
  final String? error;
  final String? verificationChallengeHash;
  final DateTime? verificationExpiresAt;

  const DirectMessageDelivery({
    required this.recipientNpub,
    required this.inboxRelays,
    required this.acceptedRelays,
    required this.usedManualRelays,
    required this.error,
    this.verificationChallengeHash,
    this.verificationExpiresAt,
  });

  DirectMessageDelivery copyWith({
    String? verificationChallengeHash,
    DateTime? verificationExpiresAt,
  }) =>
      DirectMessageDelivery(
        recipientNpub: recipientNpub,
        inboxRelays: inboxRelays,
        acceptedRelays: acceptedRelays,
        usedManualRelays: usedManualRelays,
        error: error,
        verificationChallengeHash:
            verificationChallengeHash ?? this.verificationChallengeHash,
        verificationExpiresAt:
            verificationExpiresAt ?? this.verificationExpiresAt,
      );

  bool get accepted => acceptedRelays.isNotEmpty;

  factory DirectMessageDelivery.invalidRecipient(String npub) =>
      DirectMessageDelivery(
        recipientNpub: npub,
        inboxRelays: const [],
        acceptedRelays: const [],
        usedManualRelays: false,
        error: 'npub inválida.',
      );
}
