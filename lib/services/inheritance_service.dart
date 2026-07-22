import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'breez_service.dart';
import 'nfc_credential_crypto.dart';
import 'nostr_service.dart';

/// What [InheritanceService.handleSuccessfulUnlock] should do for a given
/// state and moment in time. Split out as a pure function of
/// ([InheritanceState], [DateTime]) — no storage or network I/O — purely
/// so the state machine's branching (the trickiest, most bug-prone part of
/// this feature) can be unit tested directly without mocking secure
/// storage or Nostr relays. See test/inheritance_service_test.dart.
enum InheritanceUnlockAction { none, startGracePeriod, cancelGracePeriod, release }

/// Pure decision function used by [InheritanceService.handleSuccessfulUnlock].
/// Public (via [visibleForTesting]) so it can be tested in isolation.
@visibleForTesting
InheritanceUnlockAction decideInheritanceUnlockAction(InheritanceState state, DateTime now) {
  if (!state.enabled || state.released) return InheritanceUnlockAction.none;

  final graceStart = state.gracePeriodStartedAt;
  if (graceStart != null) {
    final graceDeadlinePassed = now.difference(graceStart) >= Duration(days: state.graceDays);
    return graceDeadlinePassed ? InheritanceUnlockAction.release : InheritanceUnlockAction.cancelGracePeriod;
  }

  final inactiveTooLong = now.difference(state.lastActiveAt) >= Duration(days: state.inactivityDays);
  return inactiveTooLong ? InheritanceUnlockAction.startGracePeriod : InheritanceUnlockAction.none;
}

/// Current status of the inheritance feature, for display (see
/// `InheritanceSetupScreen`).
enum InheritanceStatus { disabled, healthy, gracePeriod, released }

/// Immutable snapshot of the inheritance feature's configuration and
/// progress. Every mutation in [InheritanceService] reads the current one,
/// derives a new one via [copyWith], and persists it as a single JSON blob
/// (see [InheritanceService._stateKey]) — small enough, and always read as
/// a whole, that splitting it into separate secure-storage keys (the way
/// e.g. the wallet mnemonic and PIN are) wouldn't buy anything here.
class InheritanceState {
  final bool enabled;
  final List<TrustedContact> heirs;
  final int inactivityDays;
  final int graceDays;
  final DateTime lastActiveAt;
  final DateTime? gracePeriodStartedAt;
  final bool released;

  const InheritanceState({
    required this.enabled,
    required this.heirs,
    required this.inactivityDays,
    required this.graceDays,
    required this.lastActiveAt,
    required this.gracePeriodStartedAt,
    required this.released,
  });

  factory InheritanceState.initial() => InheritanceState(
        enabled: false,
        heirs: const [],
        inactivityDays: InheritanceService.defaultInactivityDays,
        graceDays: InheritanceService.defaultGraceDays,
        lastActiveAt: DateTime.now(),
        gracePeriodStartedAt: null,
        released: false,
      );

  InheritanceStatus get status {
    if (released) return InheritanceStatus.released;
    if (!enabled) return InheritanceStatus.disabled;
    if (gracePeriodStartedAt != null) return InheritanceStatus.gracePeriod;
    return InheritanceStatus.healthy;
  }

  /// Time remaining until the inactivity threshold is reached, from the
  /// last confirmed activity — clamped to zero rather than negative.
  /// Meaningless (but harmless) outside [InheritanceStatus.healthy].
  Duration get timeUntilInactivityThreshold {
    final deadline = lastActiveAt.add(Duration(days: inactivityDays));
    final remaining = deadline.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Time remaining until the grace period itself elapses, or null if none
  /// is active.
  Duration? get timeUntilGraceDeadline {
    final start = gracePeriodStartedAt;
    if (start == null) return null;
    final deadline = start.add(Duration(days: graceDays));
    final remaining = deadline.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  InheritanceState copyWith({
    bool? enabled,
    List<TrustedContact>? heirs,
    int? inactivityDays,
    int? graceDays,
    DateTime? lastActiveAt,
    DateTime? gracePeriodStartedAt,
    bool clearGracePeriod = false,
    bool? released,
  }) {
    return InheritanceState(
      enabled: enabled ?? this.enabled,
      heirs: heirs ?? this.heirs,
      inactivityDays: inactivityDays ?? this.inactivityDays,
      graceDays: graceDays ?? this.graceDays,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      gracePeriodStartedAt: clearGracePeriod ? null : (gracePeriodStartedAt ?? this.gracePeriodStartedAt),
      released: released ?? this.released,
    );
  }

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'heirs': heirs.map((h) => h.toMap()).toList(),
        'inactivityDays': inactivityDays,
        'graceDays': graceDays,
        'lastActiveAt': lastActiveAt.toIso8601String(),
        'gracePeriodStartedAt': gracePeriodStartedAt?.toIso8601String(),
        'released': released,
      };

  factory InheritanceState.fromMap(Map<String, dynamic> map) => InheritanceState(
        enabled: map['enabled'] as bool? ?? false,
        heirs: (map['heirs'] as List<dynamic>? ?? const [])
            .map((e) => TrustedContact.fromMap(e as Map<String, dynamic>))
            .toList(),
        inactivityDays: map['inactivityDays'] as int? ?? InheritanceService.defaultInactivityDays,
        graceDays: map['graceDays'] as int? ?? InheritanceService.defaultGraceDays,
        lastActiveAt: DateTime.tryParse(map['lastActiveAt'] as String? ?? '') ?? DateTime.now(),
        gracePeriodStartedAt:
            map['gracePeriodStartedAt'] != null ? DateTime.tryParse(map['gracePeriodStartedAt'] as String) : null,
        released: map['released'] as bool? ?? false,
      );
}

/// Simplified inheritance/legacy feature: if the wallet goes unused for a
/// configurable period, registered heirs are notified over Nostr, and — if
/// nobody proves the wallet is still in use before a grace period runs
/// out — the wallet's recovery seed is released to them.
///
/// ## How "inactivity" is actually detected — and its core limitation
///
/// There is no server or background job here — this is a fully
/// client-side wallet. The entire state machine below (see
/// [handleSuccessfulUnlock]) only ever runs at the moment someone
/// successfully unlocks the app with the correct PIN. That is the ONLY
/// event this feature can react to.
///
/// This has an unavoidable consequence worth being explicit about: if the
/// wallet's owner truly never opens the app again, NOTHING here ever runs
/// — no notification, no release. The check that would detect "too much
/// time has passed" only executes at app-open time, and if the app is
/// never opened, that code never executes either. A real dead-man's-switch
/// needs *something* that runs on its own while the app is closed (a
/// server tracking a heartbeat, or each heir's own client periodically
/// checking for one) — out of scope for a client-only hackathon build.
///
/// What this DOES correctly handle: if someone — the original owner
/// returning after a long absence, or anyone else who has since obtained
/// the PIN — opens the app after [inactivityDays] have passed without it
/// being opened, that open is treated as the trigger: a grace period
/// starts and heirs are notified. A further open before the grace period
/// elapses cancels it (proof of life). If the grace period elapses with no
/// such open in between, the NEXT open — whenever it happens — performs
/// the release, even if that opener is the original owner returning very
/// late. There is no way to release strictly "in the background" without
/// a server component.
///
/// ## Recovery delivery: Nostr DM, not a physical NFC key
///
/// [_release] reuses the exact password-based encryption scheme already
/// used for the physical NFC recovery key ([NfcCredentialCrypto] —
/// Argon2id + AES-GCM), but delivers the resulting envelope as a NIP-17
/// encrypted Nostr DM to each heir instead of writing it to a tag.
/// Writing to a physical tag was considered and rejected: every existing
/// NFC write path in this app (see `NfcService.writeRecoveryCredential`)
/// requires a person to physically hold a tag against the phone at the
/// moment of writing, driven by an interactive screen with retries and
/// visual feedback. Automatic release fundamentally cannot assume anyone
/// is present to do that — the phone might be sitting untouched. A Nostr
/// DM, by contrast, can be published unattended, and is picked up by the
/// heir's own Nostr client whenever they next check it. The envelope is
/// still password-protected on top of NIP-17's own encryption — the heir
/// needs the release password (set here ahead of time, and expected to be
/// shared with them out-of-band by the owner as part of estate planning)
/// to actually decrypt the seed, so the DM's content alone isn't enough.
class InheritanceService {
  InheritanceService._();
  static final InheritanceService instance = InheritanceService._();

  static const defaultInactivityDays = 180; // ~6 months
  static const defaultGraceDays = 30;

  /// Preset options shown in `InheritanceSetupScreen` — 3 months, 6
  /// months, 1 year. A custom day count is also allowed.
  static const inactivityPresetDays = [90, 180, 365];

  /// Preset grace-period options — 7, 14, 30 days. A custom day count is
  /// also allowed.
  static const gracePresetDays = [7, 14, 30];

  static const _stateKey = 'satra_inheritance_state';
  static const _passwordKey = 'satra_inheritance_password';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  Future<InheritanceState> getState() async {
    final raw = await _secureStorage.read(key: _stateKey);
    if (raw == null || raw.isEmpty) {
      final initial = InheritanceState.initial();
      await _saveState(initial);
      return initial;
    }
    try {
      return InheritanceState.fromMap(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Corrupted/unrecognized blob — reset rather than crash every screen
      // that reads this. Loses only the inheritance configuration, not the
      // wallet itself.
      final initial = InheritanceState.initial();
      await _saveState(initial);
      return initial;
    }
  }

  Future<void> _saveState(InheritanceState state) =>
      _secureStorage.write(key: _stateKey, value: jsonEncode(state.toMap()));

  Future<bool> hasPassword() async {
    final value = await _secureStorage.read(key: _passwordKey);
    return value != null && value.isNotEmpty;
  }

  /// Sets the password used to encrypt the seed released to heirs (see
  /// [_release]) — separate from every other password/PIN in this app, the
  /// same way `NfcKeyPasswordService`'s password is. Throws [ArgumentError]
  /// if shorter than [NfcCredentialCrypto.minPasswordLength].
  Future<void> setPassword(String password) async {
    if (password.length < NfcCredentialCrypto.minPasswordLength) {
      throw ArgumentError(
        'A senha precisa ter pelo menos ${NfcCredentialCrypto.minPasswordLength} caracteres.',
      );
    }
    await _secureStorage.write(key: _passwordKey, value: password);
  }

  Future<String?> _getPassword() => _secureStorage.read(key: _passwordKey);

  /// Enables or disables the feature. Enabling requires at least one heir
  /// and a release password to already be configured — allowing it to be
  /// switched on half-configured would mean it silently fails to do
  /// anything useful right at release time, when nobody is around to fix
  /// it. Throws [StateError] with a user-facing message if either is
  /// missing; disabling always succeeds.
  ///
  /// Re-enabling after a release restarts the whole cycle fresh (clears
  /// [InheritanceState.released], resets [InheritanceState.lastActiveAt] to
  /// now) — otherwise the feature would be permanently stuck "released"
  /// with no way back on, even though the owner is clearly here turning it
  /// back on.
  Future<void> setEnabled(bool enabled) async {
    final state = await getState();
    if (enabled) {
      if (state.heirs.isEmpty) {
        throw StateError('Adicione ao menos um herdeiro antes de ativar.');
      }
      if (!await hasPassword()) {
        throw StateError('Defina uma senha de liberação antes de ativar.');
      }
      await _saveState(state.copyWith(enabled: true, released: false, lastActiveAt: DateTime.now()));
      return;
    }
    await _saveState(state.copyWith(enabled: false));
  }

  Future<void> setInactivityDays(int days) async {
    final state = await getState();
    await _saveState(state.copyWith(inactivityDays: days));
  }

  Future<void> setGraceDays(int days) async {
    final state = await getState();
    await _saveState(state.copyWith(graceDays: days));
  }

  /// Adds (or replaces, if the npub is already registered) an heir.
  /// Throws [ArgumentError] if [npub] isn't valid or [label] is empty —
  /// same validation `NostrService.addContact` applies to trusted contacts,
  /// since an heir is the same (label, npub) shape, just a different list.
  Future<void> addHeir(String npub, String label) async {
    final trimmedNpub = npub.trim();
    final trimmedLabel = label.trim();
    if (!NostrService.isValidNpub(trimmedNpub)) {
      throw ArgumentError('npub inválida.');
    }
    if (trimmedLabel.isEmpty) {
      throw ArgumentError('Escolha um nome para o herdeiro.');
    }

    final state = await getState();
    final heirs = [...state.heirs]..removeWhere((h) => h.npub == trimmedNpub);
    heirs.add(TrustedContact(label: trimmedLabel, npub: trimmedNpub));
    await _saveState(state.copyWith(heirs: heirs));
  }

  Future<void> removeHeir(String npub) async {
    final state = await getState();
    final heirs = [...state.heirs]..removeWhere((h) => h.npub == npub);
    await _saveState(state.copyWith(heirs: heirs));
  }

  /// Call after every successful PIN unlock on the normal daily-use path
  /// (see `CalculatorScreen._onEquals`) — never on the master-sequence
  /// first-time-setup path (no PIN exists yet, nothing to protect) or the
  /// escape gesture (a deliberate emergency action, not "activity" in the
  /// sense this feature cares about).
  ///
  /// Orchestrates the whole inactivity/grace/release state machine in one
  /// place specifically so callers never have to sequence "record this as
  /// activity" and "check for inactivity" themselves — doing those in the
  /// wrong order (e.g. recording activity first) would make the inactivity
  /// check against itself and never fire. Never throws — this runs
  /// unawaited on every unlock and must not be able to block or fail it.
  Future<void> handleSuccessfulUnlock() async {
    try {
      final state = await getState();
      final now = DateTime.now();

      switch (decideInheritanceUnlockAction(state, now)) {
        case InheritanceUnlockAction.none:
          await _saveState(state.copyWith(lastActiveAt: now));
        case InheritanceUnlockAction.startGracePeriod:
          await _startGracePeriod(state, now);
        case InheritanceUnlockAction.cancelGracePeriod:
          await _cancelGracePeriod(state, now);
        case InheritanceUnlockAction.release:
          await _release(state);
      }
    } catch (e) {
      debugPrint('[InheritanceService] handleSuccessfulUnlock: FAILED — $e');
    }
  }

  /// Deliberately does NOT bump [InheritanceState.lastActiveAt] — starting
  /// the grace period isn't proof of life, it's the alarm going off.
  /// [lastActiveAt] only moves forward on a healthy unlock or an explicit
  /// cancellation (see [_cancelGracePeriod]).
  Future<void> _startGracePeriod(InheritanceState state, DateTime now) async {
    await _saveState(state.copyWith(gracePeriodStartedAt: now));
    debugPrint('[InheritanceService] inactivity threshold reached — grace period started');
    unawaited(
      NostrService.instance.sendDirectMessageToAll(
        state.heirs,
        'Aviso Satra Wallet: o período de inatividade configurado pelo titular da carteira foi '
        'atingido. Se não houver atividade em ${state.graceDays} dia(s), as informações de '
        'recuperação da carteira serão enviadas para você.',
      ),
    );
  }

  Future<void> _cancelGracePeriod(InheritanceState state, DateTime now) async {
    await _saveState(state.copyWith(clearGracePeriod: true, lastActiveAt: now));
    debugPrint('[InheritanceService] app reopened during the grace period — cancelling');
    unawaited(
      NostrService.instance.sendDirectMessageToAll(
        state.heirs,
        'Aviso Satra Wallet: o titular da carteira voltou a usar o app. O processo de herança '
        'iniciado anteriormente foi cancelado.',
      ),
    );
  }

  /// Encrypts the wallet mnemonic with the release password (same
  /// Argon2id + AES-GCM envelope format the physical NFC key uses — see
  /// [NfcCredentialCrypto]) and sends it to every heir as a NIP-17
  /// encrypted DM. Best-effort: any failure (missing mnemonic/password,
  /// encryption error, delivery failure) is logged, not thrown, since this
  /// already runs unawaited with nobody positioned to react to an
  /// exception.
  Future<void> _release(InheritanceState state) async {
    await _saveState(state.copyWith(clearGracePeriod: true, released: true));
    debugPrint('[InheritanceService] grace period elapsed — releasing recovery info to heirs');
    try {
      final mnemonic = await BreezService.instance.getMnemonic();
      final password = await _getPassword();
      if (mnemonic == null || mnemonic.isEmpty || password == null || password.isEmpty) {
        debugPrint('[InheritanceService] _release: missing mnemonic or release password, aborting');
        return;
      }

      final envelopeJson = await NfcCredentialCrypto.encrypt(mnemonic: mnemonic, password: password);
      final message = 'Herança Satra Wallet: o período de carência terminou sem confirmação de '
          'atividade do titular. Abaixo está a frase de recuperação da carteira, cifrada com a '
          'senha combinada previamente com você. Use essa senha para decifrá-la.\n\n$envelopeJson';

      final succeeded = await NostrService.instance.sendDirectMessageToAll(state.heirs, message);
      debugPrint('[InheritanceService] _release: delivered to $succeeded of ${state.heirs.length} heir(s)');
    } catch (e) {
      debugPrint('[InheritanceService] _release: FAILED — $e');
    }
  }
}
