import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nostr/nostr.dart';

import 'inheritance_heartbeat.dart';

/// Reads and validates a wallet owner's latest inheritance heartbeat from
/// Nostr relays. This is the "observer" side of the dead-man's-switch: it
/// checks whether the owner has renewed their heartbeat within the
/// configured inactivity window.
///
/// **Not wired into the app UI** — intentionally. The app's own wallet
/// screen doesn't need to observe heartbeats (it publishes them). This
/// class exists for the external CLI tool (`tool/inheritance_observer.dart`),
/// which a technical heir or guardian can run from a terminal to monitor
/// a wallet owner's heartbeat without installing the Satra app. Non-
/// technical heirs observe the heartbeat's silence via any standard Nostr
/// client (Damus, Primal) — they don't need this class at all.
///
/// Unit-tested in `test/inheritance_observer_test.dart` (the `selectLatest`
/// tie-breaking logic), not integration-tested against live relays.
class InheritanceObserver {
  static const connectTimeout = Duration(seconds: 8);
  static const fetchTimeout = Duration(seconds: 8);

  final List<String> relays;

  InheritanceObserver({required List<String> relays})
      : relays = List.unmodifiable(relays) {
    if (relays.isEmpty) throw ArgumentError('At least one relay is required.');
  }

  Future<InheritanceObservation> observe(String ownerPubkeyHex) async {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(ownerPubkeyHex)) {
      throw ArgumentError.value(ownerPubkeyHex, 'ownerPubkeyHex');
    }
    final results = await Future.wait(
      relays.map((relay) => _fetchFromRelay(relay, ownerPubkeyHex)),
    );
    return InheritanceObservation(
      checkedAt: DateTime.now().toUtc(),
      relayResults: results,
      latest: selectLatest(
        results.map((result) => result.heartbeat).whereType(),
      ),
    );
  }

  static InheritanceHeartbeat? selectLatest(
    Iterable<InheritanceHeartbeat> heartbeats,
  ) {
    InheritanceHeartbeat? latest;
    for (final heartbeat in heartbeats) {
      if (latest == null || comesAfter(heartbeat, latest)) latest = heartbeat;
    }
    return latest;
  }

  static bool comesAfter(
    InheritanceHeartbeat candidate,
    InheritanceHeartbeat current,
  ) {
    if (candidate.sequence != current.sequence) {
      return candidate.sequence > current.sequence;
    }
    final timeComparison = candidate.issuedAt.compareTo(current.issuedAt);
    if (timeComparison != 0) return timeComparison > 0;
    return candidate.eventId.compareTo(current.eventId) < 0;
  }

  Future<InheritanceRelayResult> _fetchFromRelay(
    String relayUrl,
    String ownerPubkeyHex,
  ) async {
    WebSocket? socket;
    StreamSubscription<dynamic>? subscription;
    try {
      socket = await WebSocket.connect(relayUrl).timeout(connectTimeout);
      final request = Request(
        subscriptionId:
            'satra-observer-${DateTime.now().microsecondsSinceEpoch}',
        filters: [
          Filter(
            authors: [ownerPubkeyHex],
            kinds: const [InheritanceHeartbeat.eventKind],
            tagFilters: const {
              'd': [InheritanceHeartbeat.eventDTag],
            },
            limit: 1,
          ),
        ],
      );

      InheritanceHeartbeat? found;
      final finished = Completer<void>();
      subscription = socket.listen(
        (data) {
          try {
            final frame = jsonDecode(data.toString());
            if (frame is! List || frame.isEmpty) return;
            if (frame[0] == 'EVENT') {
              final event = Event.deserialize(data.toString(), verify: true);
              final heartbeat = InheritanceHeartbeat.fromEvent(event);
              if (heartbeat.ownerPubkey != ownerPubkeyHex) return;
              if (found == null || comesAfter(heartbeat, found!)) {
                found = heartbeat;
              }
            } else if (frame[0] == 'EOSE' || frame[0] == 'CLOSED') {
              if (!finished.isCompleted) finished.complete();
            }
          } catch (_) {
            // A relay cannot influence the timer with malformed or forged
            // data. Ignore it and continue checking the remaining frames.
          }
        },
        onError: (Object _) {
          if (!finished.isCompleted) finished.complete();
        },
        onDone: () {
          if (!finished.isCompleted) finished.complete();
        },
      );
      socket.add(request.serialize());
      await finished.future.timeout(fetchTimeout, onTimeout: () {});
      return InheritanceRelayResult(relay: relayUrl, heartbeat: found);
    } catch (e) {
      return InheritanceRelayResult(
        relay: relayUrl,
        error: e.toString(),
      );
    } finally {
      await subscription?.cancel();
      try {
        await socket?.close();
      } catch (_) {
        // Already closed.
      }
    }
  }
}

class InheritanceObservation {
  final DateTime checkedAt;
  final List<InheritanceRelayResult> relayResults;
  final InheritanceHeartbeat? latest;

  const InheritanceObservation({
    required this.checkedAt,
    required this.relayResults,
    required this.latest,
  });

  int get respondingRelayCount =>
      relayResults.where((result) => result.error == null).length;

  Map<String, dynamic> toMap() {
    final heartbeat = latest;
    return {
      'checked_at': checkedAt.toIso8601String(),
      'responding_relays': respondingRelayCount,
      'total_relays': relayResults.length,
      'status': heartbeat?.statusAt(checkedAt).name ?? 'missing',
      'heartbeat': heartbeat == null
          ? null
          : {
              'event_id': heartbeat.eventId,
              'owner_pubkey': heartbeat.ownerPubkey,
              'sequence': heartbeat.sequence,
              'issued_at': heartbeat.issuedAt.toIso8601String(),
              'valid_until': heartbeat.validUntil.toIso8601String(),
              'grace_deadline': heartbeat.graceDeadline.toIso8601String(),
              'enabled': heartbeat.enabled,
            },
      'relays': relayResults.map((result) => result.toMap()).toList(),
    };
  }
}

class InheritanceRelayResult {
  final String relay;
  final InheritanceHeartbeat? heartbeat;
  final String? error;

  const InheritanceRelayResult({
    required this.relay,
    this.heartbeat,
    this.error,
  });

  Map<String, dynamic> toMap() => {
        'relay': relay,
        'event_id': heartbeat?.eventId,
        'sequence': heartbeat?.sequence,
        'error': error,
      };
}
