import 'package:flutter/material.dart';

import '../routes.dart';
import '../services/escape_status.dart';
import '../theme/colors.dart';

/// Shown right after the escape gesture completes. By the time this screen
/// is on screen, [WalletHomeScreen] has already fired off the balance sweep
/// and the NIP-17 alert to trusted contacts in the background.
///
/// This screen listens to [EscapeStatus] and reflects the real-time outcome
/// of each step — so the user sees whether the money moved and whether the
/// alert went out, instead of a generic "done" that might mask a failure.
/// In the threat model of this app (domestic violence), a silent failure
/// is dangerous: the user might believe they escaped when they didn't.
///
/// Per the product spec, the app quietly returns to looking like a plain
/// calculator a few seconds after both steps resolve (or after a max
/// timeout, so a hung relay doesn't trap the user on this screen).
class EscapeConfirmationScreen extends StatefulWidget {
  const EscapeConfirmationScreen({super.key});

  @override
  State<EscapeConfirmationScreen> createState() =>
      _EscapeConfirmationScreenState();
}

class _EscapeConfirmationScreenState extends State<EscapeConfirmationScreen>
    with SingleTickerProviderStateMixin {
  static const _entranceDuration = Duration(milliseconds: 380);
  static const _maxScreenTime = Duration(seconds: 12);

  late final AnimationController _entranceController;
  late final Animation<double> _entranceOpacity;
  late final Animation<double> _entranceScale;
  bool _navigatedAway = false;

  @override
  void initState() {
    super.initState();
    _entranceController =
        AnimationController(vsync: this, duration: _entranceDuration);
    final curved =
        CurvedAnimation(parent: _entranceController, curve: Curves.easeOut);
    _entranceOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(curved);
    _entranceScale = Tween<double>(begin: 0.8, end: 1.0).animate(curved);
    _entranceController.forward();

    EscapeStatus.instance.addListener(_onStatusChanged);

    // Hard timeout: if a relay hangs forever, don't trap the user on this
    // screen — return to the calculator (safety state) after the max time.
    Future.delayed(_maxScreenTime, _returnToCalculator);
  }

  void _onStatusChanged() {
    if (!mounted) return;
    setState(() {});
    final sweep = EscapeStatus.instance.sweep;
    final alert = EscapeStatus.instance.alert;
    final bothResolved =
        sweep is! EscapeStepPending && alert is! EscapeStepPending;
    if (bothResolved) {
      // Give the user ~3s to read the result before disappearing.
      Future.delayed(const Duration(seconds: 3), _returnToCalculator);
    }
  }

  void _returnToCalculator() {
    if (_navigatedAway || !mounted) return;
    _navigatedAway = true;
    Navigator.of(context).pushNamedAndRemoveUntil(
      SatraRoutes.calculator,
      (route) => false,
    );
  }

  @override
  void dispose() {
    EscapeStatus.instance.removeListener(_onStatusChanged);
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sweep = EscapeStatus.instance.sweep;
    final alert = EscapeStatus.instance.alert;
    return Scaffold(
      backgroundColor: SatraColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 3),
              FadeTransition(
                opacity: _entranceOpacity,
                child: ScaleTransition(
                  scale: _entranceScale,
                  child: Column(
                    children: [
                      Container(
                        width: 96,
                        height: 96,
                        decoration: const BoxDecoration(
                            color: SatraColors.success, shape: BoxShape.circle),
                        child: const Icon(Icons.check,
                            color: Colors.white, size: 48),
                      ),
                      const SizedBox(height: 28),
                      const Text(
                        'Escape ativado',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: SatraColors.navy),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
              _EscapeStepRow(
                label: 'Saldo transferido',
                state: sweep,
              ),
              const SizedBox(height: 12),
              _EscapeStepRow(
                label: 'Rede de confiança avisada',
                state: alert,
              ),
              const Spacer(flex: 4),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: SatraColors.light),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(Icons.shield_outlined,
                          size: 16, color: SatraColors.medium),
                      SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'PROTOCOLO DE SEGURANÇA ATIVO',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: SatraColors.medium),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

/// One row showing the live status of a single escape sub-task. Uses a
/// spinner while pending, a green check on success, and a red warning on
/// failure — so a failed sweep or alert is immediately visible, not
/// buried in a generic "done".
class _EscapeStepRow extends StatelessWidget {
  final String label;
  final EscapeStepState state;

  const _EscapeStepRow({required this.label, required this.state});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        switch (state) {
          EscapeStepPending() => const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: SatraColors.medium),
            ),
          EscapeStepSuccess() => const Icon(Icons.check_circle,
              color: SatraColors.success, size: 22),
          EscapeStepFailed() => Icon(Icons.error_outline,
              color: Colors.red.shade400, size: 22),
        },
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: SatraColors.navy),
              ),
              if (state is EscapeStepFailed)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'Falha — voltaremos ao normal automaticamente.',
                    style: TextStyle(
                        fontSize: 11, color: Colors.red.shade400),
                  ),
                ),
            ],
          ),
        ),
        switch (state) {
          EscapeStepPending() => Text('enviando...',
              style: TextStyle(
                  fontSize: 12,
                  color: SatraColors.navy.withValues(alpha: 0.5))),
          EscapeStepSuccess() => const Text('concluído',
              style: TextStyle(
                  fontSize: 12, color: SatraColors.success)),
          EscapeStepFailed() => const Text('falha',
              style: TextStyle(fontSize: 12, color: Colors.red)),
        },
      ],
    );
  }
}
