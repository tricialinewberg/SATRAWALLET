import 'package:flutter_test/flutter_test.dart';

import 'package:calculadora/services/escape_status.dart';

void main() {
  group('EscapeStatus', () {
    test('starts with both steps pending', () {
      EscapeStatus.instance.reset();
      expect(EscapeStatus.instance.sweep, isA<EscapeStepPending>());
      expect(EscapeStatus.instance.alert, isA<EscapeStepPending>());
    });

    test('setSweep updates sweep state and notifies listeners', () {
      EscapeStatus.instance.reset();
      var notifications = 0;
      EscapeStatus.instance.addListener(() => notifications++);

      EscapeStatus.instance.setSweep(const EscapeStepState.success());
      expect(EscapeStatus.instance.sweep, isA<EscapeStepSuccess>());
      expect(notifications, 1);

      EscapeStatus.instance.setSweep(const EscapeStepState.failed('timeout'));
      expect(EscapeStatus.instance.sweep, isA<EscapeStepFailed>());
      expect((EscapeStatus.instance.sweep as EscapeStepFailed).reason,
          'timeout');
      expect(notifications, 2);
    });

    test('setAlert updates alert state independently', () {
      EscapeStatus.instance.reset();
      EscapeStatus.instance.setSweep(const EscapeStepState.success());
      expect(EscapeStatus.instance.alert, isA<EscapeStepPending>());

      EscapeStatus.instance.setAlert(const EscapeStepState.success());
      expect(EscapeStatus.instance.alert, isA<EscapeStepSuccess>());
    });

    test('reset clears both steps back to pending', () {
      EscapeStatus.instance.setSweep(const EscapeStepState.success());
      EscapeStatus.instance.setAlert(const EscapeStepState.failed('err'));
      EscapeStatus.instance.reset();
      expect(EscapeStatus.instance.sweep, isA<EscapeStepPending>());
      expect(EscapeStatus.instance.alert, isA<EscapeStepPending>());
    });

    test('EscapeStepState factory constructors produce correct types', () {
      const pending = EscapeStepState.pending();
      const success = EscapeStepState.success();
      const failed = EscapeStepState.failed('reason');

      expect(pending, isA<EscapeStepPending>());
      expect(success, isA<EscapeStepSuccess>());
      expect(failed, isA<EscapeStepFailed>());
      expect((failed as EscapeStepFailed).reason, 'reason');
    });
  });
}
