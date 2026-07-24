import 'package:calculadora/services/inheritance_heartbeat.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nostr/nostr.dart';

void main() {
  const secretKey =
      '5ee1c8000ab28edd64d74a7d951ac2dd559814887b1b9e1ac7c5f89e96125c12';
  final issuedAt = DateTime.utc(2026, 7, 22, 12);

  Event heartbeatEvent({bool enabled = true}) =>
      InheritanceHeartbeat.createSignedEvent(
        secretKey: secretKey,
        sequence: 7,
        issuedAt: issuedAt,
        inactivityDuration: const Duration(days: 180),
        graceDuration: const Duration(days: 30),
        enabled: enabled,
      );

  test('creates a signed heartbeat that round-trips through validation', () {
    final parsed = InheritanceHeartbeat.fromEvent(heartbeatEvent());

    expect(parsed.sequence, 7);
    expect(parsed.issuedAt, issuedAt);
    expect(parsed.validUntil, issuedAt.add(const Duration(days: 180)));
    expect(parsed.graceDeadline, issuedAt.add(const Duration(days: 210)));
    expect(parsed.enabled, isTrue);
  });

  test('evaluates active, grace and release-eligible periods', () {
    final parsed = InheritanceHeartbeat.fromEvent(heartbeatEvent());

    expect(
      parsed.statusAt(issuedAt.add(const Duration(days: 179))),
      InheritanceHeartbeatStatus.active,
    );
    expect(
      parsed.statusAt(issuedAt.add(const Duration(days: 180))),
      InheritanceHeartbeatStatus.gracePeriod,
    );
    expect(
      parsed.statusAt(issuedAt.add(const Duration(days: 210))),
      InheritanceHeartbeatStatus.releaseEligible,
    );
  });

  test('disabled heartbeat never starts inheritance countdown', () {
    final parsed =
        InheritanceHeartbeat.fromEvent(heartbeatEvent(enabled: false));
    expect(
      parsed.statusAt(issuedAt.add(const Duration(days: 999))),
      InheritanceHeartbeatStatus.disabled,
    );
  });

  test('supports second-based test windows', () {
    final event = InheritanceHeartbeat.createSignedEvent(
      secretKey: secretKey,
      sequence: 8,
      issuedAt: issuedAt,
      inactivityDuration: const Duration(seconds: 30),
      graceDuration: const Duration(seconds: 15),
      enabled: true,
    );
    final parsed = InheritanceHeartbeat.fromEvent(event);

    expect(parsed.validUntil, issuedAt.add(const Duration(seconds: 30)));
    expect(parsed.graceDeadline, issuedAt.add(const Duration(seconds: 45)));
  });

  test('rejects a heartbeat whose signed payload was tampered with', () {
    final original = heartbeatEvent();
    final tampered = original.copyWith(
      content: original.content.replaceFirst('"sequence":7', '"sequence":8'),
      verify: false,
    );

    expect(
      () => InheritanceHeartbeat.fromEvent(tampered),
      throwsA(anything),
    );
  });
}
