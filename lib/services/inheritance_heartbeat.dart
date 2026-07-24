import 'dart:convert';

import 'package:nostr/nostr.dart';

/// Public, signed dead-man's-switch heartbeat.
///
/// The event deliberately contains no wallet secret or heir identity. An
/// external observer only learns that an opaque Nostr identity renewed an
/// inheritance timer, and can verify that renewal without holding any key.
class InheritanceHeartbeat {
  static const version = 1;
  static const eventKind = 30078;
  static const eventDTag = 'satra-wallet:inheritance-heartbeat:v1';

  final String eventId;
  final String ownerPubkey;
  final int sequence;
  final DateTime issuedAt;
  final DateTime validUntil;
  final int graceSeconds;
  final bool enabled;

  const InheritanceHeartbeat({
    required this.eventId,
    required this.ownerPubkey,
    required this.sequence,
    required this.issuedAt,
    required this.validUntil,
    required this.graceSeconds,
    required this.enabled,
  });

  Duration get graceDuration => Duration(seconds: graceSeconds);
  DateTime get graceDeadline => validUntil.add(graceDuration);

  InheritanceHeartbeatStatus statusAt(DateTime now) {
    if (!enabled) return InheritanceHeartbeatStatus.disabled;
    if (now.isBefore(validUntil)) return InheritanceHeartbeatStatus.active;
    if (now.isBefore(graceDeadline)) {
      return InheritanceHeartbeatStatus.gracePeriod;
    }
    return InheritanceHeartbeatStatus.releaseEligible;
  }

  /// Creates the canonical signed event published by the wallet.
  static Event createSignedEvent({
    required String secretKey,
    required int sequence,
    required DateTime issuedAt,
    required Duration inactivityDuration,
    required Duration graceDuration,
    required bool enabled,
  }) {
    if (sequence < 1) throw ArgumentError.value(sequence, 'sequence');
    if (inactivityDuration <= Duration.zero) {
      throw ArgumentError.value(inactivityDuration, 'inactivityDuration');
    }
    if (graceDuration <= Duration.zero) {
      throw ArgumentError.value(graceDuration, 'graceDuration');
    }

    final issuedSeconds = issuedAt.toUtc().millisecondsSinceEpoch ~/ 1000;
    final validUntilSeconds = issuedSeconds + inactivityDuration.inSeconds;
    final content = jsonEncode({
      'version': version,
      'sequence': sequence,
      'valid_until': validUntilSeconds,
      'grace_seconds': graceDuration.inSeconds,
      'enabled': enabled,
    });

    return Event.from(
      kind: eventKind,
      content: content,
      secretKey: secretKey,
      createdAt: issuedSeconds,
      tags: const [
        ['d', eventDTag],
      ],
      verify: true,
    );
  }

  /// Parses and cryptographically validates a heartbeat received from a
  /// relay. Invalid signatures, kinds, tags or timer values are rejected.
  factory InheritanceHeartbeat.fromEvent(Event event) {
    // Reconstruct with verification enabled even if the caller originally
    // deserialized the event without verification.
    final verified = Event.fromJson(event.toJson(), verify: true);
    if (verified.kind != eventKind) {
      throw const FormatException('Not a Satra inheritance heartbeat kind.');
    }
    final hasDTag = verified.tags.any(
      (tag) => tag.length >= 2 && tag[0] == 'd' && tag[1] == eventDTag,
    );
    if (!hasDTag) {
      throw const FormatException('Missing inheritance heartbeat d tag.');
    }

    final Object? decoded = jsonDecode(verified.content);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Heartbeat content must be a JSON object.');
    }
    final eventVersion = decoded['version'];
    final sequence = decoded['sequence'];
    final validUntil = decoded['valid_until'];
    final legacyGraceDays = decoded['grace_days'];
    final graceSeconds = decoded['grace_seconds'] ??
        (legacyGraceDays is int
            ? legacyGraceDays * Duration.secondsPerDay
            : null);
    final enabled = decoded['enabled'];
    if (eventVersion != version ||
        sequence is! int ||
        sequence < 1 ||
        validUntil is! int ||
        graceSeconds is! int ||
        graceSeconds < 1 ||
        enabled is! bool) {
      throw const FormatException('Invalid inheritance heartbeat payload.');
    }
    if (validUntil <= verified.createdAt) {
      throw const FormatException(
          'Heartbeat validity must end after issuance.');
    }

    return InheritanceHeartbeat(
      eventId: verified.id,
      ownerPubkey: verified.pubkey,
      sequence: sequence,
      issuedAt: DateTime.fromMillisecondsSinceEpoch(
        verified.createdAt * 1000,
        isUtc: true,
      ),
      validUntil: DateTime.fromMillisecondsSinceEpoch(
        validUntil * 1000,
        isUtc: true,
      ),
      graceSeconds: graceSeconds,
      enabled: enabled,
    );
  }
}

enum InheritanceHeartbeatStatus {
  disabled,
  active,
  gracePeriod,
  releaseEligible,
}
