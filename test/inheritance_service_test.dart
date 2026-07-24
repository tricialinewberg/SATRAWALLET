import 'package:flutter_test/flutter_test.dart';

import 'package:calculadora/services/inheritance_service.dart';

void main() {
  final now = DateTime(2026, 1, 1);

  InheritanceState stateWith({
    bool enabled = true,
    required DateTime lastActiveAt,
    DateTime? gracePeriodStartedAt,
    int inactivityDays = 180,
    int graceDays = 30,
    bool testMode = false,
    int testInactivitySeconds = 30,
    int testGraceSeconds = 30,
  }) {
    return InheritanceState(
      enabled: enabled,
      heirs: const [],
      inactivityDays: inactivityDays,
      graceDays: graceDays,
      lastActiveAt: lastActiveAt,
      gracePeriodStartedAt: gracePeriodStartedAt,
      testMode: testMode,
      testInactivitySeconds: testInactivitySeconds,
      testGraceSeconds: testGraceSeconds,
    );
  }

  test('disabled: does nothing regardless of how stale lastActiveAt is', () {
    final state = stateWith(
        enabled: false, lastActiveAt: now.subtract(const Duration(days: 400)));
    expect(decideInheritanceUnlockAction(state, now),
        InheritanceUnlockAction.none);
  });

  test('enabled, healthy, well within the inactivity window: does nothing', () {
    final state =
        stateWith(lastActiveAt: now.subtract(const Duration(days: 10)));
    expect(decideInheritanceUnlockAction(state, now),
        InheritanceUnlockAction.none);
  });

  test('enabled, exactly at the inactivity threshold: starts the grace period',
      () {
    final state =
        stateWith(lastActiveAt: now.subtract(const Duration(days: 180)));
    expect(decideInheritanceUnlockAction(state, now),
        InheritanceUnlockAction.startGracePeriod);
  });

  test(
      'enabled, past the inactivity threshold, no grace period yet: starts one',
      () {
    final state =
        stateWith(lastActiveAt: now.subtract(const Duration(days: 200)));
    expect(decideInheritanceUnlockAction(state, now),
        InheritanceUnlockAction.startGracePeriod);
  });

  test(
      'grace period active and not yet expired: this open cancels it (proof of life)',
      () {
    final state = stateWith(
      lastActiveAt: now.subtract(const Duration(days: 200)),
      gracePeriodStartedAt: now.subtract(const Duration(days: 5)),
      graceDays: 30,
    );
    expect(decideInheritanceUnlockAction(state, now),
        InheritanceUnlockAction.cancelGracePeriod);
  });

  test('grace period expired: valid owner unlock still proves life', () {
    final state = stateWith(
      lastActiveAt: now.subtract(const Duration(days: 200)),
      gracePeriodStartedAt: now.subtract(const Duration(days: 30)),
      graceDays: 30,
    );
    expect(decideInheritanceUnlockAction(state, now),
        InheritanceUnlockAction.cancelGracePeriod);
  });

  test('grace period long expired: valid owner unlock never releases', () {
    final state = stateWith(
      lastActiveAt: now.subtract(const Duration(days: 200)),
      gracePeriodStartedAt: now.subtract(const Duration(days: 90)),
      graceDays: 30,
    );
    expect(decideInheritanceUnlockAction(state, now),
        InheritanceUnlockAction.cancelGracePeriod);
  });

  test(
      'a stale lastActiveAt is irrelevant once a grace period is already tracked',
      () {
    // Regardless of how long ago lastActiveAt was, once gracePeriodStartedAt
    // is set the grace-period branch takes over entirely.
    final withoutGrace =
        stateWith(lastActiveAt: now.subtract(const Duration(days: 400)));
    final withGrace = stateWith(
      lastActiveAt: now.subtract(const Duration(days: 400)),
      gracePeriodStartedAt: now.subtract(const Duration(days: 1)),
    );
    expect(decideInheritanceUnlockAction(withoutGrace, now),
        InheritanceUnlockAction.startGracePeriod);
    expect(decideInheritanceUnlockAction(withGrace, now),
        InheritanceUnlockAction.cancelGracePeriod);
  });

  test('test mode transitions using seconds instead of production days', () {
    final active = stateWith(
      lastActiveAt: now.subtract(const Duration(seconds: 29)),
      testMode: true,
    );
    final expired = stateWith(
      lastActiveAt: now.subtract(const Duration(seconds: 30)),
      testMode: true,
    );
    final graceExpired = stateWith(
      lastActiveAt: now.subtract(const Duration(seconds: 60)),
      gracePeriodStartedAt: now.subtract(const Duration(seconds: 30)),
      testMode: true,
    );

    expect(decideInheritanceUnlockAction(active, now),
        InheritanceUnlockAction.none);
    expect(
      decideInheritanceUnlockAction(expired, now),
      InheritanceUnlockAction.startGracePeriod,
    );
    expect(
      decideInheritanceUnlockAction(graceExpired, now),
      InheritanceUnlockAction.cancelGracePeriod,
    );
  });

  group('InheritanceState derived getters', () {
    test(
        'timeUntilInactivityThreshold clamps to zero once past due, never negative',
        () {
      final state =
          stateWith(lastActiveAt: now.subtract(const Duration(days: 400)));
      // Evaluated against DateTime.now() internally, but any already-past
      // deadline must clamp to zero rather than a negative duration.
      expect(state.timeUntilInactivityThreshold, Duration.zero);
    });

    test('timeUntilGraceDeadline is null when no grace period is active', () {
      final state = stateWith(lastActiveAt: now);
      expect(state.timeUntilGraceDeadline, isNull);
    });

    test('status reflects disabled/gracePeriod/healthy precedence', () {
      expect(stateWith(enabled: false, lastActiveAt: now).status,
          InheritanceStatus.disabled);
      expect(
        stateWith(lastActiveAt: now, gracePeriodStartedAt: now).status,
        InheritanceStatus.gracePeriod,
      );
      expect(stateWith(lastActiveAt: now).status, InheritanceStatus.healthy);
    });
  });
}
