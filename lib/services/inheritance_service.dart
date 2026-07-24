import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nostr/nostr.dart' show Bech32Entity, Nip19Prefix;

import 'breez_service.dart';
import 'inheritance_background_service.dart';
import 'nfc_credential_crypto.dart';
import 'nostr_service.dart';

/// What [InheritanceService.handleSuccessfulUnlock] should do for a given
/// state and moment in time. Split out as a pure function of
/// ([InheritanceState], [DateTime]) — no storage or network I/O — purely
/// so the state machine's branching (the trickiest, most bug-prone part of
/// this feature) can be unit tested directly without mocking secure
/// storage or Nostr relays. See test/inheritance_service_test.dart.
enum InheritanceUnlockAction {
  none,
  startGracePeriod,
  cancelGracePeriod,
}

/// Pure decision function used by [InheritanceService.handleSuccessfulUnlock].
/// Public (via [visibleForTesting]) so it can be tested in isolation.
@visibleForTesting
InheritanceUnlockAction decideInheritanceUnlockAction(
    InheritanceState state, DateTime now) {
  if (!state.enabled) return InheritanceUnlockAction.none;

  final graceStart = state.gracePeriodStartedAt;
  if (graceStart != null) {
    // A successful owner authentication is always proof of life. Releasing
    // recovery material in response to the legitimate owner entering the
    // correct PIN would invert the safety guarantee precisely when it matters
    // most (for example, after returning to an old phone months later).
    return InheritanceUnlockAction.cancelGracePeriod;
  }

  final inactiveTooLong =
      now.difference(state.lastActiveAt) >= state.inactivityDuration;
  return inactiveTooLong
      ? InheritanceUnlockAction.startGracePeriod
      : InheritanceUnlockAction.none;
}

/// Current status of the inheritance feature, for display (see
/// `InheritanceSetupScreen`).
enum InheritanceStatus { disabled, healthy, gracePeriod }

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
  final int heartbeatSequence;
  final String? lastHeartbeatEventId;
  final DateTime? lastHeartbeatPublishedAt;
  final bool testMode;
  final int testInactivitySeconds;
  final int testGraceSeconds;
  final String inheritanceMessage;

  const InheritanceState({
    required this.enabled,
    required this.heirs,
    required this.inactivityDays,
    required this.graceDays,
    required this.lastActiveAt,
    required this.gracePeriodStartedAt,
    this.heartbeatSequence = 0,
    this.lastHeartbeatEventId,
    this.lastHeartbeatPublishedAt,
    this.testMode = false,
    this.testInactivitySeconds = 60,
    this.testGraceSeconds = 30,
    this.inheritanceMessage = InheritanceService.defaultInheritanceMessage,
  });

  factory InheritanceState.initial() => InheritanceState(
        enabled: false,
        heirs: const [],
        inactivityDays: InheritanceService.defaultInactivityDays,
        graceDays: InheritanceService.defaultGraceDays,
        lastActiveAt: DateTime.now(),
        gracePeriodStartedAt: null,
        heartbeatSequence: 0,
        lastHeartbeatEventId: null,
        lastHeartbeatPublishedAt: null,
        testMode: false,
        testInactivitySeconds: 60,
        testGraceSeconds: 30,
        inheritanceMessage: InheritanceService.defaultInheritanceMessage,
      );

  InheritanceStatus get status {
    if (!enabled) return InheritanceStatus.disabled;
    if (gracePeriodStartedAt != null) return InheritanceStatus.gracePeriod;
    return InheritanceStatus.healthy;
  }

  Duration get inactivityDuration => testMode
      ? Duration(seconds: testInactivitySeconds)
      : Duration(days: inactivityDays);

  Duration get graceDuration => testMode
      ? Duration(seconds: testGraceSeconds)
      : Duration(days: graceDays);

  /// Time remaining until the inactivity threshold is reached, from the
  /// last confirmed activity — clamped to zero rather than negative.
  /// Meaningless (but harmless) outside [InheritanceStatus.healthy].
  Duration get timeUntilInactivityThreshold {
    final deadline = lastActiveAt.add(inactivityDuration);
    final remaining = deadline.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Time remaining until the grace period itself elapses, or null if none
  /// is active.
  Duration? get timeUntilGraceDeadline {
    final start = gracePeriodStartedAt;
    if (start == null) return null;
    final deadline = start.add(graceDuration);
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
    int? heartbeatSequence,
    String? lastHeartbeatEventId,
    DateTime? lastHeartbeatPublishedAt,
    bool? testMode,
    int? testInactivitySeconds,
    int? testGraceSeconds,
    String? inheritanceMessage,
  }) {
    return InheritanceState(
      enabled: enabled ?? this.enabled,
      heirs: heirs ?? this.heirs,
      inactivityDays: inactivityDays ?? this.inactivityDays,
      graceDays: graceDays ?? this.graceDays,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      gracePeriodStartedAt: clearGracePeriod
          ? null
          : (gracePeriodStartedAt ?? this.gracePeriodStartedAt),
      heartbeatSequence: heartbeatSequence ?? this.heartbeatSequence,
      lastHeartbeatEventId: lastHeartbeatEventId ?? this.lastHeartbeatEventId,
      lastHeartbeatPublishedAt:
          lastHeartbeatPublishedAt ?? this.lastHeartbeatPublishedAt,
      testMode: testMode ?? this.testMode,
      testInactivitySeconds:
          testInactivitySeconds ?? this.testInactivitySeconds,
      testGraceSeconds: testGraceSeconds ?? this.testGraceSeconds,
      inheritanceMessage: inheritanceMessage ?? this.inheritanceMessage,
    );
  }

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'heirs': heirs.map((h) => h.toMap()).toList(),
        'inactivityDays': inactivityDays,
        'graceDays': graceDays,
        'lastActiveAt': lastActiveAt.toIso8601String(),
        'gracePeriodStartedAt': gracePeriodStartedAt?.toIso8601String(),
        'heartbeatSequence': heartbeatSequence,
        'lastHeartbeatEventId': lastHeartbeatEventId,
        'lastHeartbeatPublishedAt': lastHeartbeatPublishedAt?.toIso8601String(),
        'testMode': testMode,
        'testInactivitySeconds': testInactivitySeconds,
        'testGraceSeconds': testGraceSeconds,
        'inheritanceMessage': inheritanceMessage,
      };

  factory InheritanceState.fromMap(Map<String, dynamic> map) =>
      InheritanceState(
        enabled: map['enabled'] as bool? ?? false,
        heirs: (map['heirs'] as List<dynamic>? ?? const [])
            .map((e) => TrustedContact.fromMap(e as Map<String, dynamic>))
            .toList(),
        inactivityDays: map['inactivityDays'] as int? ??
            InheritanceService.defaultInactivityDays,
        graceDays:
            map['graceDays'] as int? ?? InheritanceService.defaultGraceDays,
        lastActiveAt: DateTime.tryParse(map['lastActiveAt'] as String? ?? '') ??
            DateTime.now(),
        gracePeriodStartedAt: map['gracePeriodStartedAt'] != null
            ? DateTime.tryParse(map['gracePeriodStartedAt'] as String)
            : null,
        heartbeatSequence: map['heartbeatSequence'] as int? ?? 0,
        lastHeartbeatEventId: map['lastHeartbeatEventId'] as String?,
        lastHeartbeatPublishedAt: map['lastHeartbeatPublishedAt'] != null
            ? DateTime.tryParse(map['lastHeartbeatPublishedAt'] as String)
            : null,
        testMode: map['testMode'] as bool? ?? false,
        testInactivitySeconds: map['testInactivitySeconds'] as int? ?? 60,
        testGraceSeconds: map['testGraceSeconds'] as int? ?? 30,
        inheritanceMessage: map['inheritanceMessage'] as String? ??
            InheritanceService.defaultInheritanceMessage,
      );
}

/// Experimental inheritance/legacy coordinator. It records local activity,
/// publishes signed Nostr heartbeats and can test encrypted delivery to
/// verified heirs.
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
/// A successful PIN unlock is always treated as proof of life. It may start
/// the local warning state after a long absence, or cancel an existing grace
/// state, but it never releases recovery material. A real time-conditioned
/// release requires independent guardians/observers and is not implemented
/// by this phone-local state machine.
///
/// ## Recovery delivery: pre-published vault, not on-demand release
///
/// The recovery envelope (seed encrypted with the release password via
/// [NfcCredentialCrypto] — Argon2id + AES-GCM) is **pre-published** to
/// Nostr relays at configuration time (see [_publishInheritanceVaults]),
/// both as a NIP-44-wrapped NIP-78 replaceable event and as a NIP-17
/// encrypted DM to each heir. This means the vault is available on the
/// relays regardless of whether the owner's phone ever opens again —
/// the core property the inheritance feature needs to be honest and real.
/// The heir retrieves it from their own Nostr client (Damus, Primal, or
/// the in-app `InheritanceClaimScreen`) and decrypts it with the release
/// password shared out-of-band by the owner (e.g. on a sealed card).
class InheritanceService {
  InheritanceService._();
  static final InheritanceService instance = InheritanceService._();

  static const defaultInheritanceMessage =
      'Olá. Eu escolhi você para cuidar da minha carteira caso eu não possa mais acessá-la. Guarde esta mensagem e use a tela “Decifrar herança” do app Satra somente quando o prazo combinado for atingido. A senha de liberação foi entregue separadamente.';

  Timer? _testAlertTimer;

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

  /// Sets the password used to encrypt the seed pre-published to heirs
  /// (see [_publishInheritanceVaults]) — separate from every other
  /// password/PIN in this app, the same way `NfcKeyPasswordService`'s
  /// password is. Throws [ArgumentError] if shorter than
  /// [NfcCredentialCrypto.minPasswordLength].
  Future<void> setPassword(String password) async {
    if (password.length < NfcCredentialCrypto.minPasswordLength) {
      throw ArgumentError(
        'A senha precisa ter pelo menos ${NfcCredentialCrypto.minPasswordLength} caracteres.',
      );
    }
    await _secureStorage.write(key: _passwordKey, value: password);
    final state = await getState();
    if (state.enabled) {
      await _publishInheritanceVaults(state);
    }
  }

  Future<String?> _getPassword() => _secureStorage.read(key: _passwordKey);

  /// Enables or disables the feature. Enabling requires at least one heir
  /// and a release password to already be configured — allowing it to be
  /// switched on half-configured would mean it silently fails to do
  /// anything useful right at release time, when nobody is around to fix
  /// it. Throws [StateError] with a user-facing message if either is
  /// missing; disabling always succeeds.
  ///
  /// Re-enabling restarts the whole cycle fresh (resets
  /// [InheritanceState.lastActiveAt] to now, clears any active grace
  /// period) so the owner is always starting from a clean state.
  Future<void> setEnabled(bool enabled) async {
    final state = await getState();
    if (enabled) {
      if (state.heirs.isEmpty) {
        throw StateError('Adicione ao menos um herdeiro antes de ativar.');
      }
      if (!await hasPassword()) {
        throw StateError('Defina uma senha de liberação antes de ativar.');
      }
      final now = DateTime.now();
      final next = state.copyWith(
        enabled: true,
        lastActiveAt: now,
      );
      await _saveState(next);
      await _publishHeartbeat(next, now);
      await _publishInheritanceVaults(next);
      _scheduleTestAlertIfNeeded(next);
      return;
    }
    _testAlertTimer?.cancel();
    unawaited(InheritanceBackgroundService.stop());
    final now = DateTime.now();
    final next = state.copyWith(enabled: false);
    await _saveState(next);
    await _publishHeartbeat(next, now);
  }

  Future<void> setInactivityDays(int days) async {
    final state = await getState();
    final next = state.copyWith(inactivityDays: days);
    await _saveState(next);
    if (next.enabled) await _publishHeartbeat(next, DateTime.now());
  }

  Future<void> setGraceDays(int days) async {
    final state = await getState();
    final next = state.copyWith(graceDays: days);
    await _saveState(next);
    if (next.enabled) await _publishHeartbeat(next, DateTime.now());
  }

  Future<void> configureTestMode({
    required bool enabled,
    int inactivitySeconds = 60,
    int graceSeconds = 30,
  }) async {
    if (inactivitySeconds < 5 || graceSeconds < 5) {
      throw ArgumentError(
          'Os períodos de teste devem ter ao menos 5 segundos.');
    }
    final state = await getState();
    final now = DateTime.now();
    final next = state.copyWith(
      testMode: enabled,
      testInactivitySeconds: inactivitySeconds,
      testGraceSeconds: graceSeconds,
      lastActiveAt: now,
      clearGracePeriod: true,
    );
    await _saveState(next);
    if (next.enabled) await _publishHeartbeat(next, now);
    _scheduleTestAlertIfNeeded(next);
  }

  /// Starts a one-shot end-to-end delivery simulation. It is deliberately
  /// independent from the production policy: no release password and no
  /// enabled policy are required, but at least one heir must have completed
  /// the challenge/response contact verification.
  Future<void> startDeliveryTest({required int delaySeconds}) async {
    if (delaySeconds < 10 || delaySeconds > 300) {
      throw ArgumentError('Escolha um tempo entre 10 segundos e 5 minutos.');
    }
    final state = await getState();
    if (!state.heirs.any((heir) => heir.verifiedAt != null)) {
      throw StateError(
        'Verifique pelo menos um herdeiro com o código recebido antes do teste.',
      );
    }
    final now = DateTime.now();
    final next = state.copyWith(
      testMode: true,
      testInactivitySeconds: delaySeconds,
      testGraceSeconds: 30,
      lastActiveAt: now,
      clearGracePeriod: true,
    );
    await _saveState(next);
    _scheduleTestAlertIfNeeded(next);
  }

  Future<void> cancelDeliveryTest() async {
    _testAlertTimer?.cancel();
    await InheritanceBackgroundService.stop();
    final state = await getState();
    if (!state.testMode) return;
    await _saveState(
      state.copyWith(
        testMode: false,
        clearGracePeriod: true,
        lastActiveAt: DateTime.now(),
      ),
    );
  }

  Future<void> resumePendingDeliveryTest() async {
    final state = await getState();
    // Repairs the state written by an earlier test-mode implementation that
    // could leave a stale grace-period flag after a force-quit. Cleared here
    // so the user never sees a red screen from a test that was interrupted.
    if (state.testMode && state.gracePeriodStartedAt != null) {
      final repaired = state.copyWith(
        testMode: false,
        clearGracePeriod: true,
        lastActiveAt: DateTime.now(),
      );
      await _saveState(repaired);
      await InheritanceBackgroundService.stop();
      return;
    }
    if (state.testMode) _scheduleTestAlertIfNeeded(state);
  }

  Future<void> setInheritanceMessage(String message) async {
    final trimmed = message.trim();
    if (trimmed.length < 10) {
      throw ArgumentError('Escreva uma mensagem com pelo menos 10 caracteres.');
    }
    if (trimmed.length > 2000) {
      throw ArgumentError('A mensagem pode ter no máximo 2000 caracteres.');
    }
    final state = await getState();
    await _saveState(state.copyWith(inheritanceMessage: trimmed));
  }

  /// Schedules the first inheritance warning for test mode. This is useful
  /// for an end-to-end phone test, but is intentionally not presented as a
  /// durable scheduler: Android may kill a Flutter process after the app is
  /// closed. Production release needs an independent observer/coordinator.
  void _scheduleTestAlertIfNeeded(InheritanceState state) {
    _testAlertTimer?.cancel();
    if (!state.testMode) {
      unawaited(InheritanceBackgroundService.stop());
      return;
    }
    if (Platform.isAndroid) {
      unawaited(InheritanceBackgroundService.start());
      return;
    }
    final elapsed = DateTime.now().difference(state.lastActiveAt);
    final remaining = state.inactivityDuration - elapsed;
    _testAlertTimer = Timer(
      remaining.isNegative ? Duration.zero : remaining,
      _runTestAlert,
    );
  }

  Future<void> _runTestAlert() async {
    try {
      await runBackgroundTestCheck();
    } catch (e) {
      debugPrint('[InheritanceService] scheduled test alert failed — $e');
    }
  }

  /// Entry point used by the Android foreground task. `completed` separates
  /// "not due yet" from a completed attempt, while `accepted` means at least
  /// one recipient inbox relay explicitly acknowledged the NIP-17 gift-wrap.
  Future<({bool completed, bool accepted})> runBackgroundTestCheck() async {
    final state = await getState();
    if (!state.testMode) {
      return (completed: false, accepted: false);
    }
    if (DateTime.now().difference(state.lastActiveAt) <
        state.inactivityDuration) {
      return (completed: false, accepted: false);
    }

    final verifiedHeirs =
        state.heirs.where((heir) => heir.verifiedAt != null).toList();
    var accepted = false;
    try {
      final delivered = await NostrService.instance.sendDirectMessageToAll(
        verifiedHeirs,
        'TESTE DE HERANÇA — Satra Wallet\n\n'
        '${state.inheritanceMessage}\n\n'
        'Esta é uma simulação solicitada pelo titular para confirmar a entrega '
        'criptografada. Nenhuma seed ou informação da carteira foi liberada.',
      );
      accepted = delivered > 0;
    } catch (e) {
      debugPrint('[InheritanceService] delivery test failed — $e');
    } finally {
      final now = DateTime.now();
      final restored = state.copyWith(
        testMode: false,
        clearGracePeriod: true,
        lastActiveAt: now,
      );
      await _saveState(restored);
      if (restored.enabled) await _publishHeartbeat(restored, now);
    }
    return (completed: true, accepted: accepted);
  }

  /// Adds (or replaces, if the npub is already registered) an heir.
  /// Throws [ArgumentError] if [npub] isn't valid or [label] is empty —
  /// same validation `NostrService.addContact` applies to trusted contacts,
  /// since an heir is the same (label, npub) shape, just a different list.
  Future<void> addHeir(
    String npub,
    String label, {
    String? relationship,
    double? sharePercentage,
    String? replacingNpub,
  }) async {
    final trimmedNpub = npub.trim();
    final trimmedLabel = label.trim();
    if (!NostrService.isValidNpub(trimmedNpub)) {
      throw ArgumentError('npub inválida.');
    }
    if (trimmedLabel.isEmpty) {
      throw ArgumentError('Escolha um nome para o herdeiro.');
    }
    if (sharePercentage != null &&
        (sharePercentage <= 0 || sharePercentage > 100)) {
      throw ArgumentError('O percentual deve estar entre 0 e 100.');
    }

    final state = await getState();
    final heirs = [...state.heirs]..removeWhere(
        (h) => h.npub == trimmedNpub || h.npub == replacingNpub,
      );
    heirs.add(
      TrustedContact(
        label: trimmedLabel,
        npub: trimmedNpub,
        relationship:
            relationship?.trim().isEmpty == true ? null : relationship?.trim(),
        sharePercentage: sharePercentage,
      ),
    );
    final next = state.copyWith(heirs: heirs);
    await _saveState(next);
    if (next.enabled) {
      await _publishInheritanceVaults(next);
    }
  }

  Future<void> removeHeir(String npub) async {
    final state = await getState();
    final heirs = [...state.heirs]..removeWhere((h) => h.npub == npub);
    final next = state.copyWith(heirs: heirs);
    await _saveState(next);
    if (next.enabled) {
      await _publishInheritanceVaults(next);
    }
  }

  Future<void> setHeirInboxRelays(String npub, List<String> relays) async {
    final validated = NostrService.validateInboxRelays(relays);
    final state = await getState();
    final heirs = [...state.heirs];
    final index = heirs.indexWhere((heir) => heir.npub == npub);
    if (index < 0) throw StateError('Herdeiro não encontrado.');
    heirs[index] = heirs[index].copyWith(
      inboxRelays: validated,
      inboxRelaysManual: true,
    );
    await _saveState(state.copyWith(heirs: heirs));
  }

  Future<void> recordHeirTest(
      String npub, DirectMessageDelivery delivery) async {
    final state = await getState();
    final heirs = [...state.heirs];
    final index = heirs.indexWhere((heir) => heir.npub == npub);
    if (index < 0) return;
    final current = heirs[index];
    heirs[index] = current.copyWith(
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
    await _saveState(state.copyWith(heirs: heirs));
  }

  Future<bool> verifyHeirCode(String npub, String code) async {
    final state = await getState();
    final heirs = [...state.heirs];
    final index = heirs.indexWhere((heir) => heir.npub == npub);
    if (index < 0 ||
        !NostrService.verificationCodeMatches(heirs[index], code)) {
      return false;
    }
    heirs[index] = heirs[index].copyWith(
      verifiedAt: DateTime.now(),
      clearVerificationChallenge: true,
    );
    await _saveState(state.copyWith(heirs: heirs));
    return true;
  }

  Future<DirectMessageDelivery> sendHeirVerification(String npub) async {
    final state = await getState();
    final heir = state.heirs.where((item) => item.npub == npub).firstOrNull;
    if (heir == null) throw StateError('Herdeiro não encontrado.');
    final delivery = await NostrService.instance.sendContactTest(heir);
    await recordHeirTest(npub, delivery);
    return delivery;
  }

  /// Sends the owner's configured message immediately to verified heirs.
  /// A positive result means at least one recipient inbox relay acknowledged
  /// the encrypted NIP-17/NIP-59 event; it cannot prove that a human read it.
  Future<({int delivered, int recipients})> sendInheritanceMessageTest() async {
    final state = await getState();
    final verified =
        state.heirs.where((heir) => heir.verifiedAt != null).toList();
    if (verified.isEmpty) {
      throw StateError('Verifique pelo menos um herdeiro antes do teste.');
    }
    final delivered = await NostrService.instance.sendDirectMessageToAll(
      verified,
      'TESTE DE HERANÇA — Satra Wallet\n\n'
      '${state.inheritanceMessage}\n\n'
      'Esta é uma simulação solicitada pelo titular. A mensagem foi enviada '
      'com criptografia NIP-17/NIP-59. Nenhuma seed, senha ou informação '
      'financeira foi compartilhada.',
    );
    return (delivered: delivered, recipients: verified.length);
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
      }
      final current = await getState();
      await _publishHeartbeat(current, now);
    } catch (e) {
      debugPrint('[InheritanceService] handleSuccessfulUnlock: FAILED — $e');
    }
  }

  /// Explicit owner-controlled renewal used by the inheritance screen.
  /// Returns true only when at least one relay confirms the signed event.
  Future<bool> confirmProofOfLife() async {
    final state = await getState();
    if (!state.enabled) {
      throw StateError('Ative a herança antes de confirmar a prova de vida.');
    }
    final now = DateTime.now();
    final next = state.copyWith(
      lastActiveAt: now,
      clearGracePeriod: true,
    );
    await _saveState(next);
    final published = await _publishHeartbeat(next, now);
    // Re-publishing the vault here gives the owner a way to force another
    // delivery attempt (e.g. after fixing a relay hiccup at enable time)
    // without needing to re-add an heir or reset the password.
    await _publishInheritanceVaults(next);
    _scheduleTestAlertIfNeeded(next);
    return published;
  }

  /// Advances the monotonic sequence before network I/O, then publishes a
  /// signed heartbeat. A failed publish never rolls the sequence back: an
  /// older relay event must never become authoritative again.
  Future<bool> _publishHeartbeat(
    InheritanceState state,
    DateTime issuedAt,
  ) async {
    final pending = state.copyWith(
      heartbeatSequence: state.heartbeatSequence + 1,
    );
    await _saveState(pending);
    try {
      final publication =
          await NostrService.instance.publishInheritanceHeartbeat(
        sequence: pending.heartbeatSequence,
        issuedAt: issuedAt,
        inactivityDuration: pending.inactivityDuration,
        graceDuration: pending.graceDuration,
        enabled: pending.enabled,
      );
      if (!publication.accepted) {
        debugPrint(
          '[InheritanceService] heartbeat ${publication.eventId} was not accepted by any relay',
        );
        return false;
      }
      await _saveState(
        pending.copyWith(
          lastHeartbeatEventId: publication.eventId,
          lastHeartbeatPublishedAt: issuedAt,
        ),
      );
      return true;
    } catch (e) {
      debugPrint('[InheritanceService] heartbeat publish failed — $e');
      return false;
    }
  }

  /// Pre-publishes the password-encrypted recovery vault as a NIP-44-wrapped,
  /// NIP-78 replaceable event (see [NostrService.publishInheritanceVault])
  /// to each heir. Called whenever the inheritance policy is enabled, and
  /// whenever the set of heirs or the release password changes — so the
  /// relay copy always reflects the current recovery material.
  ///
  /// Best-effort, like the heartbeat publish: a relay failure here is
  /// logged, never thrown — the inheritance enable flow must not abort
  /// because a relay was unreachable. The owner can re-trigger a
  /// re-publish from the inheritance screen at any time via
  /// [confirmProofOfLife] (which bumps activity and re-publishes the
  /// heartbeat) — but the vault is intentionally republished on its own
  /// here so an unreachable relay at enable time gets another shot on the
  /// next mutation. There is no "vault sequence": the envelope is fully
  /// determined by (mnemonic, password), so re-publishing the same value
  /// is idempotent.
  Future<void> _publishInheritanceVaults(InheritanceState state) async {
    if (!state.enabled) return;
    try {
      final mnemonic = await BreezService.instance.getMnemonic();
      final password = await _getPassword();
      if (mnemonic == null ||
          mnemonic.isEmpty ||
          password == null ||
          password.isEmpty) {
        debugPrint(
            '[InheritanceService] _publishInheritanceVaults: missing mnemonic or password, skipping');
        return;
      }
      final envelopeJson = await NfcCredentialCrypto.encrypt(
          mnemonic: mnemonic, password: password);

      // Two delivery channels, in parallel, for redundancy:
      //
      // 1. NIP-78 replaceable event (kind 30078) — durable on the relays,
      //    addressable per-heir by d-tag. Invisible to normal Nostr clients
      //    (Damus/Primal don't render kind 30078), but fetchable by the
      //    Satra app itself (see NostrService.fetchInheritanceVault).
      //
      // 2. NIP-17 encrypted DM — appears in the heir's inbox in ANY normal
      //    Nostr client (Damus, Primal, Amethyst). This is the delivery
      //    channel a non-technical heir actually has. The envelope inside
      //    is still password-encrypted, so seeing the DM while the owner
      //    is alive is harmless — without the release password (shared
      //    out-of-band, opened only when the owner's Nostr goes silent),
      //    the envelope is just base64 noise.
      var published = 0;
      for (final heir in state.heirs) {
        final hex = _heirPubkeyHex(heir.npub);
        if (hex == null) continue;
        final accepted = await NostrService.instance.publishInheritanceVault(
          heirPubkeyHex: hex,
          encryptedEnvelopeJson: envelopeJson,
        );
        if (accepted) published++;
      }

      final dmMessage = '${state.inheritanceMessage}\n\n'
          'Quando o prazo combinado for atingido, abra o app Satra, escolha '
          '“Decifrar herança”, cole o envelope abaixo e informe a senha de '
          'liberação recebida separadamente. O envelope é cifrado e não '
          'revela a carteira sem essa senha.\n\n'
          'ENVELOPE CIFRADO:\n$envelopeJson';
      final dmDelivered = await NostrService.instance
          .sendDirectMessageToAll(state.heirs, dmMessage);

      debugPrint(
          '[InheritanceService] _publishInheritanceVaults: relay vault to $published of ${state.heirs.length} heir(s), DM to $dmDelivered of ${state.heirs.length} heir(s)');
    } catch (e) {
      debugPrint('[InheritanceService] _publishInheritanceVaults: FAILED — $e');
    }
  }

  /// Decodes an npub to its hex pubkey, or null if it isn't a valid npub.
  /// Mirrors the same decode path [NostrService._deliverDirectMessage]
  /// uses for DM delivery, so a vault is only ever published to an address
  /// we can actually deliver a DM to as well.
  static String? _heirPubkeyHex(String npub) {
    try {
      final decoded = Bech32Entity.decode(payload: npub.trim());
      if (decoded.prefix != Nip19Prefix.npub) return null;
      return decoded.data;
    } catch (_) {
      return null;
    }
  }

  /// Deliberately does NOT bump [InheritanceState.lastActiveAt] — starting
  /// the grace period isn't proof of life, it's the alarm going off.
  /// [lastActiveAt] only moves forward on a healthy unlock or an explicit
  /// cancellation (see [_cancelGracePeriod]).
  Future<void> _startGracePeriod(InheritanceState state, DateTime now) async {
    await _saveState(state.copyWith(gracePeriodStartedAt: now));
    debugPrint(
        '[InheritanceService] inactivity threshold reached — grace period started');
    final graceLabel = state.testMode
        ? '${state.testGraceSeconds} segundo(s)'
        : '${state.graceDays} dia(s)';
    await NostrService.instance.sendDirectMessageToAll(
      state.heirs,
      'Aviso de herança — Satra Wallet\n\n'
      '${state.inheritanceMessage}\n\n'
      'O período de inatividade configurado pelo titular foi atingido. '
      'Se não houver atividade em $graceLabel, o processo de recuperação poderá avançar.\n\n'
      'Remetente: identidade Nostr assinada da carteira.',
    );
  }

  Future<void> _cancelGracePeriod(InheritanceState state, DateTime now) async {
    await _saveState(state.copyWith(clearGracePeriod: true, lastActiveAt: now));
    debugPrint(
        '[InheritanceService] app reopened during the grace period — cancelling');
    unawaited(
      NostrService.instance.sendDirectMessageToAll(
        state.heirs,
        'Aviso Satra Wallet: o titular da carteira voltou a usar o app. O processo de herança '
        'iniciado anteriormente foi cancelado.',
      ),
    );
  }
}
