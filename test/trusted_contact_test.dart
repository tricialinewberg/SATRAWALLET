import 'package:calculadora/services/nostr_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('old stored contacts migrate with safe delivery defaults', () {
    final contact = TrustedContact.fromMap({
      'label': 'Ana',
      'npub': 'npub1legacy',
    });

    expect(contact.inboxRelays, isEmpty);
    expect(contact.inboxRelaysManual, isFalse);
    expect(contact.lastTestedAt, isNull);
    expect(contact.lastTestAccepted, isNull);
  });

  test('delivery metadata survives serialization', () {
    final testedAt = DateTime.utc(2026, 7, 22, 20);
    final original = TrustedContact(
      label: 'Ana',
      npub: 'npub1test',
      inboxRelays: const ['wss://inbox.example.com'],
      inboxRelaysManual: true,
      lastTestedAt: testedAt,
      lastTestAccepted: true,
    );

    final restored = TrustedContact.fromMap(original.toMap());
    expect(restored.inboxRelays, original.inboxRelays);
    expect(restored.inboxRelaysManual, isTrue);
    expect(restored.lastTestedAt, testedAt);
    expect(restored.lastTestAccepted, isTrue);
    expect(restored.lastTestError, isNull);
  });

  test('verification code matches only before its expiry', () {
    final now = DateTime.utc(2026, 7, 22, 20);
    final contact = TrustedContact(
      label: 'Ana',
      npub: 'npub1test',
      verificationChallengeHash: NostrService.hashVerificationCode('843291'),
      verificationExpiresAt: now.add(const Duration(hours: 24)),
    );

    expect(
      NostrService.verificationCodeMatches(
        contact,
        '843291',
        now: now,
      ),
      isTrue,
    );
    expect(
      NostrService.verificationCodeMatches(
        contact,
        '000000',
        now: now,
      ),
      isFalse,
    );
    expect(
      NostrService.verificationCodeMatches(
        contact,
        '843291',
        now: now.add(const Duration(hours: 24)),
      ),
      isFalse,
    );
  });
}
