import 'package:flutter/material.dart';

// TEMPORARY debugging aid for the escape flow — delete this whole file (and
// its call sites in wallet_home_screen.dart, breez_service.dart, and
// nostr_service.dart) once NFC write + Nostr alert delivery are confirmed
// reliable on-device. Not meant to ship.
//
// Every step of the escape sequence (swipe confirmed -> Breez sweep -> NFC
// write -> Nostr alert) logs through [EscapeDebugLog.instance.log], which
// both prints to the console and appends to a floating on-screen panel. The
// panel is inserted into the app's root [Overlay] (via [satraNavigatorKey])
// rather than shown through any one screen's Scaffold, because the escape
// flow navigates WalletHomeScreen -> EscapeConfirmationScreen -> calculator
// within seconds, and a per-screen SnackBar/panel would be torn down before
// slower steps (Breez reconnects, Nostr relay round-trips) finish logging.

/// Root navigator key so the debug panel can reach the app's Overlay from
/// anywhere, independent of whichever screen happens to be on top.
final GlobalKey<NavigatorState> satraNavigatorKey = GlobalKey<NavigatorState>();

class EscapeDebugLog {
  EscapeDebugLog._();
  static final EscapeDebugLog instance = EscapeDebugLog._();

  final ValueNotifier<List<String>> _lines = ValueNotifier<List<String>>([]);
  OverlayEntry? _entry;

  /// Appends [message] to the on-screen panel (showing it first if this is
  /// the first line since the last [clear]) and also prints it, so the
  /// same trail is visible either on-device or over `adb logcat`.
  void log(String message) {
    debugPrint('[ESCAPE_DEBUG] $message');
    _lines.value = [..._lines.value, message];
    _ensureOverlayShown();
  }

  /// Clears previous lines — called at the start of a new escape attempt
  /// so logs from an earlier (e.g. failed/aborted) attempt don't linger
  /// and get mistaken for part of the current one.
  void clear() {
    _lines.value = [];
  }

  void _ensureOverlayShown() {
    if (_entry != null) return;
    final overlay = satraNavigatorKey.currentState?.overlay;
    if (overlay == null) return;
    final entry = OverlayEntry(
      builder: (context) => _EscapeDebugPanel(lines: _lines, onClose: _dismiss),
    );
    _entry = entry;
    overlay.insert(entry);
  }

  void _dismiss() {
    _entry?.remove();
    _entry = null;
  }
}

class _EscapeDebugPanel extends StatelessWidget {
  final ValueNotifier<List<String>> lines;
  final VoidCallback onClose;

  const _EscapeDebugPanel({required this.lines, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 12,
      right: 12,
      bottom: 24,
      child: SafeArea(
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxHeight: 320),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.greenAccent),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'ESCAPE DEBUG (temporário)',
                        style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                    GestureDetector(
                      onTap: onClose,
                      child: const Icon(Icons.close, color: Colors.white70, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Flexible(
                  child: ValueListenableBuilder<List<String>>(
                    valueListenable: lines,
                    builder: (context, value, _) {
                      if (value.isEmpty) {
                        return const Text(
                          'Aguardando...',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        );
                      }
                      return ListView.builder(
                        shrinkWrap: true,
                        itemCount: value.length,
                        itemBuilder: (context, index) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            '${index + 1}. ${value[index]}',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
