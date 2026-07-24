import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores the user's personal PIN in encrypted local storage
/// (Android Keystore / iOS Keychain) — never in plain files or memory-only state.
///
/// Includes a progressive rate limiter so an adversary with physical access to
/// the phone can't brute-force a 4-digit PIN with unlimited tries. After each
/// failed attempt, a lockout window is enforced before the next attempt is
/// even checked:
///
///   attempts 1–3  → no delay (honest typos happen)
///   attempt 4     → 30 seconds
///   attempt 5     → 2 minutes
///   attempt 6     → 10 minutes
///   attempt 7     → 1 hour
///   attempt 8+    → 24 hours per attempt
///
/// This is deliberately NOT a wipe-on-N-attempts design. The threat model
/// here is a controlling partner with physical access to the phone — a
/// partner who would certainly try PINs. A wipe would protect the funds
/// but destroy the victim's escape reserve; an exponential lockout makes
/// brute-force impractical while keeping the wallet recoverable by the real
/// owner, who either knows the PIN (and resets the counter) or uses the
/// physical NFC recovery key / inheritance paths that don't touch the PIN
/// at all.
class PinService {
  PinService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _pinKey = 'satra_user_pin';
  static const _failedAttemptsKey = 'satra_pin_failed_attempts';
  static const _lockedUntilKey = 'satra_pin_locked_until';

  static const _delayTable = <int, Duration>{
    4: Duration(seconds: 30),
    5: Duration(minutes: 2),
    6: Duration(minutes: 10),
    7: Duration(hours: 1),
    // 8+ → 24h, enforced via _lockoutFor().
  };

  final FlutterSecureStorage _storage;

  Future<bool> hasPin() async {
    final pin = await _storage.read(key: _pinKey);
    return pin != null && pin.isNotEmpty;
  }

  Future<void> savePin(String pin) async {
    await _storage.write(key: _pinKey, value: pin);
    await _resetAttempts();
  }

  /// Returns null when the PIN can be checked right now, or the remaining
  /// lockout duration if a previous failed attempt is still cooling down.
  /// The calculator screen calls this before even reading the typed digits,
  /// so the calculator can remain visually neutral instead of revealing
  /// whether a PIN was checked.
  Future<Duration?> currentLockout() async {
    final untilIso = await _storage.read(key: _lockedUntilKey);
    if (untilIso == null) return null;
    final until = DateTime.tryParse(untilIso);
    if (until == null) return null;
    final remaining = until.difference(DateTime.now());
    return remaining.isNegative ? null : remaining;
  }

  /// Verifies the candidate PIN against the stored one, enforcing the
  /// progressive lockout. Returns a [PinCheckResult] so the caller can
  /// distinguish "correct", "wrong (and now locked for X)", and
  /// "wrong (no lock yet)" without re-querying state.
  Future<PinCheckResult> verifyPin(String candidate) async {
    final lockout = await currentLockout();
    if (lockout != null) {
      return PinCheckResult.locked(remaining: lockout);
    }

    final pin = await _storage.read(key: _pinKey);
    final correct = pin != null && pin == candidate;

    if (correct) {
      await _resetAttempts();
      return const PinCheckResult.correct();
    }

    final attempts = await _incrementAttempts();
    final nextLockout = _lockoutFor(attempts);
    if (nextLockout != null) {
      final until = DateTime.now().add(nextLockout);
      await _storage.write(key: _lockedUntilKey, value: until.toIso8601String());
      return PinCheckResult.wrong(lockedFor: nextLockout);
    }
    return const PinCheckResult.wrong(lockedFor: null);
  }

  Future<int> _incrementAttempts() async {
    final raw = await _storage.read(key: _failedAttemptsKey);
    final current = int.tryParse(raw ?? '0') ?? 0;
    final next = current + 1;
    await _storage.write(key: _failedAttemptsKey, value: next.toString());
    return next;
  }

  Future<void> _resetAttempts() async {
    await _storage.delete(key: _failedAttemptsKey);
    await _storage.delete(key: _lockedUntilKey);
  }

  static Duration? _lockoutFor(int failedAttempts) {
    if (failedAttempts < 4) return null;
    return _delayTable[failedAttempts] ?? const Duration(hours: 24);
  }
}

/// Result of a [PinService.verifyPin] call. The calculator translates each
/// variant into a distinct internal state while the calculator keeps its
/// visible surface neutral.
class PinCheckResult {
  final bool isCorrect;
  final Duration? lockedFor;
  final Duration? remaining;

  const PinCheckResult.correct()
      : isCorrect = true,
        lockedFor = null,
        remaining = null;

  const PinCheckResult.wrong({this.lockedFor})
      : isCorrect = false,
        remaining = null;

  const PinCheckResult.locked({this.remaining})
      : isCorrect = false,
        lockedFor = null;
}
