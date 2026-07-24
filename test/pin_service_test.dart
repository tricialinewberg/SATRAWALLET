import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:calculadora/services/pin_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // FlutterSecureStorage reads/writes through platform channels — in unit
  // tests there's no Android Keystore / iOS Keychain. setMockInitialValues
  // redirects it to an in-memory map, so each test can start clean.
  PinService newService() {
    FlutterSecureStorage.setMockInitialValues({});
    return PinService(storage: const FlutterSecureStorage());
  }

  group('PinService rate limiting', () {
    test('correct PIN resets the failed-attempt counter', () async {
      final service = newService();
      await service.savePin('1234');

      // Burn 2 wrong attempts first.
      await service.verifyPin('0000');
      await service.verifyPin('0000');

      final result = await service.verifyPin('1234');
      expect(result.isCorrect, isTrue);

      // After a correct PIN, a new wrong attempt must start from attempt 1
      // (no lockout) rather than continuing the old escalation.
      final next = await service.verifyPin('0000');
      expect(next.isCorrect, isFalse);
      expect(next.lockedFor, isNull); // attempt 1 → no lockout
    });

    test('locks out progressively after 3 wrong attempts', () async {
      final service = newService();
      await service.savePin('9999');

      // Attempts 1-3: no lockout (typos).
      for (var i = 1; i <= 3; i++) {
        final r = await service.verifyPin('0000');
        expect(r.isCorrect, isFalse);
        expect(r.lockedFor, isNull,
            reason: 'attempt $i should not lock yet');
      }

      // Attempt 4: first lockout (30s).
      final locked = await service.verifyPin('0000');
      expect(locked.isCorrect, isFalse);
      expect(locked.lockedFor, isNotNull);
      expect(locked.lockedFor!.inSeconds, greaterThanOrEqualTo(30));
    });

    test('locked state is observed before the next check', () async {
      final service = newService();
      await service.savePin('4321');

      // Burn 3 attempts to trigger lockout on the 4th.
      await service.verifyPin('0000');
      await service.verifyPin('0000');
      await service.verifyPin('0000');
      await service.verifyPin('0000'); // locks for 30s

      final lockout = await service.currentLockout();
      expect(lockout, isNotNull);
      expect(lockout!.inSeconds, greaterThan(0));

      // A verifyPin while locked returns "locked" without consuming a new
      // attempt — an adversary hammering "=" sees the same countdown.
      final locked = await service.verifyPin('0000');
      expect(locked.remaining, isNotNull);
      expect(locked.remaining!.inSeconds, greaterThan(0));
    });

    test('escalates lockout duration with more attempts', () async {
      final service = newService();
      await service.savePin('5555');

      Duration? lastLock;
      for (var i = 1; i <= 6; i++) {
        final r = await service.verifyPin('0000');
        if (r.lockedFor != null) {
          if (lastLock != null) {
            expect(r.lockedFor!.inSeconds,
                greaterThan(lastLock.inSeconds),
                reason: 'lockout at attempt $i should exceed previous');
          }
          lastLock = r.lockedFor;
        }
      }
      expect(lastLock, isNotNull, reason: 'should have locked by attempt 6');
    });
  });
}
