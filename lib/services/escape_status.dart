import 'package:flutter/foundation.dart';

/// Tracks the real-time outcome of the two background tasks fired by the
/// escape gesture: the Breez balance sweep and the Nostr trusted-contacts
/// alert. The [EscapeConfirmationScreen] listens to [stream] and updates its
/// UI as each step resolves — so the user actually sees whether the money
/// moved and whether the alert went out, instead of a generic "done" that
/// might be a lie.
///
/// This is a singleton (not tied to any widget's lifecycle) because the
/// escape futures run `unawaited` from `WalletHomeScreen._onEscapeConfirmed`
/// and outlive the screens involved. The screen subscribes in initState and
/// unsubscribes in dispose; the singleton survives across navigation.
class EscapeStatus extends ChangeNotifier {
  EscapeStatus._();
  static final EscapeStatus instance = EscapeStatus._();

  EscapeStepState _sweep = const EscapeStepState.pending();
  EscapeStepState _alert = const EscapeStepState.pending();

  EscapeStepState get sweep => _sweep;
  EscapeStepState get alert => _alert;

  /// Resets to pending — call right before firing a new escape, so a stale
  /// status from a previous escape doesn't bleed into the new confirmation.
  void reset() {
    _sweep = const EscapeStepState.pending();
    _alert = const EscapeStepState.pending();
    notifyListeners();
  }

  void setSweep(EscapeStepState state) {
    _sweep = state;
    notifyListeners();
  }

  void setAlert(EscapeStepState state) {
    _alert = state;
    notifyListeners();
  }
}

/// State of a single escape sub-task. Deliberately sealed-ish via a
/// discriminated union so the UI can switch exhaustively.
sealed class EscapeStepState {
  const EscapeStepState();
  const factory EscapeStepState.pending() = EscapeStepPending;
  const factory EscapeStepState.success() = EscapeStepSuccess;
  const factory EscapeStepState.failed(String reason) = EscapeStepFailed;
}

class EscapeStepPending extends EscapeStepState {
  const EscapeStepPending();
}

class EscapeStepSuccess extends EscapeStepState {
  const EscapeStepSuccess();
}

class EscapeStepFailed extends EscapeStepState {
  final String reason;
  const EscapeStepFailed(this.reason);
}
