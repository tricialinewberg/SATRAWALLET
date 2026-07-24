import 'package:calculadora/services/inheritance_heartbeat.dart';
import 'package:calculadora/services/inheritance_observer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  InheritanceHeartbeat heartbeat(int sequence, DateTime issuedAt) =>
      InheritanceHeartbeat(
        eventId: 'event-$sequence',
        ownerPubkey: List.filled(64, 'a').join(),
        sequence: sequence,
        issuedAt: issuedAt,
        validUntil: issuedAt.add(const Duration(days: 180)),
        graceSeconds: const Duration(days: 30).inSeconds,
        enabled: true,
      );

  test('highest signed sequence wins across inconsistent relays', () {
    final old = heartbeat(4, DateTime.utc(2026, 1, 1));
    final current = heartbeat(5, DateTime.utc(2026, 2, 1));

    expect(InheritanceObserver.selectLatest([old, current]), same(current));
  });

  test('sequence wins even if a stale event claims a newer timestamp', () {
    final current = heartbeat(8, DateTime.utc(2026, 1, 1));
    final stale = heartbeat(7, DateTime.utc(2030, 1, 1));

    expect(InheritanceObserver.selectLatest([current, stale]), same(current));
  });

  test('empty relay view produces no authoritative heartbeat', () {
    expect(InheritanceObserver.selectLatest([]), isNull);
  });
}
