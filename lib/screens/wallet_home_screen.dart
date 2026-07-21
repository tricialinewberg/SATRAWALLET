import 'dart:async';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter/material.dart';

import '../route_observer.dart';
import '../routes.dart';
import '../services/breez_service.dart';
import '../services/nfc_service.dart';
import '../services/nostr_service.dart';
import '../theme/colors.dart';
import 'side_menu_screen.dart';

String _formatThousands(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Main wallet screen, backed by the real Breez SDK connection in
/// [BreezService]: balance and its BRL estimate are live.
class WalletHomeScreen extends StatefulWidget {
  const WalletHomeScreen({super.key});

  @override
  State<WalletHomeScreen> createState() => _WalletHomeScreenState();
}

class _WalletHomeScreenState extends State<WalletHomeScreen> with RouteAware {
  bool _balanceHidden = false;
  late final Future<void> _connectFuture;

  @override
  void initState() {
    super.initState();
    _connectFuture = BreezService.instance.initialize();
    _startNfcListening();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<void>) {
      satraRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    satraRouteObserver.unsubscribe(this);
    NfcService.instance.stopListening();
    super.dispose();
  }

  /// Pauses ambient listening while another screen (e.g. [NfcTransferScreen],
  /// which runs its own NFC session) is pushed on top of this one.
  @override
  void didPushNext() {
    NfcService.instance.stopListening();
  }

  /// Resumes ambient listening once this screen is back on top.
  @override
  void didPopNext() {
    _startNfcListening();
  }

  /// Listens for the physical recovery key while the wallet is in normal
  /// use, so tapping it navigates straight to [NfcTransferScreen] without
  /// the user needing to find it via the side menu first. Errors (an
  /// unreadable/unrelated tag) are ignored — this is ambient background
  /// listening, not a screen the user is actively watching for feedback.
  void _startNfcListening() {
    NfcService.instance.startListeningForKey(
      onKeyDetected: (mnemonic) {
        if (!mounted) return;
        Navigator.of(context).pushNamed(SatraRoutes.nfcTransfer);
      },
    );
  }

  static String _formatBrl(double value) {
    final fixed = value.toStringAsFixed(2);
    final parts = fixed.split('.');
    return 'R\$ ${_formatThousands(int.parse(parts[0]))},${parts[1]}';
  }

  void _openEscapeInfo() {
    showModalBottomSheet(
      context: context,
      backgroundColor: SatraColors.light.withValues(alpha: 0.95),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.info_outline, color: SatraColors.navy),
            const SizedBox(height: 12),
            const Text(
              'O que acontece no modo de escape?',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold, color: SatraColors.navy, fontSize: 16),
            ),
            const SizedBox(height: 12),
            const Text(
              'Ao deslizar, todo o saldo da sua carteira é enviado automaticamente '
              'para sua chave física. Ao mesmo tempo, um alerta discreto é enviado '
              'para as pessoas de confiança que você cadastrou.',
              textAlign: TextAlign.center,
              style: TextStyle(color: SatraColors.navy, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 16),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.warning_rounded, color: Colors.red, size: 18),
                SizedBox(width: 6),
                Text(
                  'Essa ação não pode ser desfeita.',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _onEscapeConfirmed() {
    // None of these are awaited — the user must see the confirmation screen
    // immediately, regardless of how long the Breez sweep, a slow Nostr
    // relay, or waiting for an NFC tag takes.
    unawaited(_sweepToNewWalletAndWriteTag());
    unawaited(NostrService.instance.sendEscapeAlert());
    Navigator.of(context).pushNamedAndRemoveUntil(
      SatraRoutes.escapeConfirmation,
      (route) => false,
    );
  }

  /// Generates a brand-new wallet, sweeps this wallet's entire balance into
  /// it, then opportunistically writes the NEW wallet's mnemonic to a
  /// physical NFC key if one happens to be presented within the write
  /// timeout — never this wallet's own mnemonic, since that one stays
  /// behind (now empty) as the wallet the normal PIN opens. The write step
  /// must run after the sweep since it needs the sweep's new mnemonic, and
  /// the user may not have the key on hand at this exact moment, so the
  /// whole thing is best-effort — not a hard dependency of the escape flow,
  /// and its result (including the iOS "writing isn't supported" case) is
  /// never surfaced to the UI.
  Future<void> _sweepToNewWalletAndWriteTag() async {
    try {
      final newMnemonic = await BreezService.instance.executeEscapeSweep();
      await NfcService.instance.writeRecoveryCredential(newMnemonic);
    } catch (_) {
      // Best-effort — the confirmation screen is shown regardless of outcome.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SatraColors.background,
      endDrawer: const SideMenuScreen(),
      body: SafeArea(
        child: Builder(
          builder: (context) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: Icon(_balanceHidden ? Icons.visibility_off : Icons.visibility, color: SatraColors.medium),
                      onPressed: () => setState(() => _balanceHidden = !_balanceHidden),
                    ),
                    IconButton(
                      icon: const Icon(Icons.menu, color: SatraColors.navy),
                      onPressed: () => Scaffold.of(context).openEndDrawer(),
                    ),
                  ],
                ),
                FutureBuilder<void>(
                  future: _connectFuture,
                  builder: (context, connectSnapshot) {
                    if (connectSnapshot.connectionState != ConnectionState.done) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: SatraColors.medium),
                        ),
                      );
                    }
                    if (connectSnapshot.hasError) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Text(
                          'Não foi possível conectar à carteira',
                          style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
                        ),
                      );
                    }
                    return StreamBuilder<int>(
                      stream: BreezService.instance.balanceStream,
                      builder: (context, balanceSnapshot) {
                        final sats = balanceSnapshot.data;
                        final brlRate = BreezService.instance.cachedBrlPerBtc;
                        final brlText = sats != null && brlRate != null
                            ? _formatBrl(sats / 100000000 * brlRate)
                            : null;

                        return Column(
                          children: [
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: _balanceHidden
                                        ? '*****'
                                        : (sats != null ? _formatThousands(sats) : '···'),
                                    style: const TextStyle(
                                      fontSize: 30,
                                      fontWeight: FontWeight.w900,
                                      color: SatraColors.navy,
                                    ),
                                  ),
                                  const TextSpan(
                                    text: '  Sats',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: SatraColors.navy),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _balanceHidden ? '≈ R\$ ****' : '≈ ${brlText ?? '—'}',
                              style: const TextStyle(color: SatraColors.medium, fontWeight: FontWeight.w600),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pushNamed(SatraRoutes.receive),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: SatraColors.navy,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                          ),
                          child: const Text('Receber', style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pushNamed(SatraRoutes.send),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: SatraColors.navy,
                            side: const BorderSide(color: SatraColors.light),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                          ),
                          child: const Text('Enviar', style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'TRANSAÇÕES RECENTES',
                    style: TextStyle(color: SatraColors.medium, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5),
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: SatraColors.light),
                    ),
                    child: StreamBuilder<List<Payment>>(
                      stream: BreezService.instance.paymentsStream,
                      builder: (context, paymentsSnapshot) {
                        final payments = paymentsSnapshot.data;
                        if (payments == null) {
                          return const Center(
                            child: SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(strokeWidth: 2, color: SatraColors.medium),
                            ),
                          );
                        }
                        if (payments.isEmpty) {
                          return const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.history, color: SatraColors.light, size: 32),
                              SizedBox(height: 10),
                              Text('Nenhuma transação ainda', style: TextStyle(color: Colors.black54)),
                            ],
                          );
                        }
                        return ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          itemCount: payments.length,
                          separatorBuilder: (context, index) => const Divider(height: 1, color: SatraColors.background),
                          itemBuilder: (context, index) => _TransactionRow(payment: payments[index]),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _EscapeSlider(onConfirmed: _onEscapeConfirmed),
                const SizedBox(height: 8),
                IconButton(
                  icon: const Icon(Icons.info_outline, color: SatraColors.medium),
                  onPressed: _openEscapeInfo,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Slide-to-confirm control for the emergency escape. Requires a deliberate
/// drag to the end (not a tap) so it can't be triggered by accident. Once
/// the drag threshold is reached, plays a brief settle+pulse animation
/// before calling [onConfirmed] — a beat of "confirmed" feedback instead of
/// cutting straight to the next screen.
class _EscapeSlider extends StatefulWidget {
  final VoidCallback onConfirmed;

  const _EscapeSlider({required this.onConfirmed});

  @override
  State<_EscapeSlider> createState() => _EscapeSliderState();
}

class _EscapeSliderState extends State<_EscapeSlider> with SingleTickerProviderStateMixin {
  double _dragFraction = 0;
  double _dragFractionAtRelease = 0;
  bool _completing = false;
  late final AnimationController _successController;

  static const _trackHeight = 56.0;
  static const _handleSize = 44.0;
  static const _successDuration = Duration(milliseconds: 320);

  // The handle finishes settling at the end of the track over the first
  // half of the animation; the pulse/checkmark plays over the back half,
  // once it's already there.
  static const _settleCurve = Interval(0.0, 0.5, curve: Curves.easeOut);
  static const _pulseCurve = Interval(0.45, 1.0, curve: Curves.easeOut);
  static const _checkThreshold = 0.5;

  @override
  void initState() {
    super.initState();
    _successController = AnimationController(vsync: this, duration: _successDuration);
  }

  @override
  void dispose() {
    _successController.dispose();
    super.dispose();
  }

  void _playSuccessThenConfirm() {
    _dragFractionAtRelease = _dragFraction;
    setState(() => _completing = true);
    _successController.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      widget.onConfirmed();
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxDrag = constraints.maxWidth - _handleSize - 8;
        return AnimatedBuilder(
          animation: _successController,
          builder: (context, _) {
            final t = _successController.value.clamp(0.0, 1.0);

            final settleT = _settleCurve.transform(t);
            final fraction =
                _completing ? _dragFractionAtRelease + (1.0 - _dragFractionAtRelease) * settleT : _dragFraction;

            // Rises to a peak mid-pulse then eases back down — a quick
            // "thump" on the handle rather than a lasting size change.
            final pulseT = _pulseCurve.transform(t);
            final pulse = _completing ? (1 - (pulseT - 0.5).abs() * 2).clamp(0.0, 1.0) : 0.0;
            final handleScale = 1.0 + pulse * 0.22;

            final showCheck = _completing && t >= _checkThreshold;

            return Container(
              height: _trackHeight,
              decoration: BoxDecoration(
                color: Color.lerp(Colors.white, SatraColors.navy, fraction),
                borderRadius: BorderRadius.circular(_trackHeight / 2),
                border: Border.all(color: SatraColors.light),
              ),
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Center(
                    child: Text(
                      'deslize para o modo de escape',
                      style: TextStyle(
                        color: Color.lerp(SatraColors.navy, Colors.white, fraction),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: GestureDetector(
                      onHorizontalDragUpdate: _completing
                          ? null
                          : (details) {
                              setState(() {
                                _dragFraction = ((_dragFraction * maxDrag) + details.delta.dx) / maxDrag;
                                _dragFraction = _dragFraction.clamp(0.0, 1.0);
                              });
                            },
                      onHorizontalDragEnd: _completing
                          ? null
                          : (details) {
                              if (_dragFraction > 0.85) {
                                _playSuccessThenConfirm();
                              } else {
                                setState(() => _dragFraction = 0);
                              }
                            },
                      child: Transform.translate(
                        offset: Offset(fraction * maxDrag, 0),
                        child: Transform.scale(
                          scale: handleScale,
                          child: Container(
                            width: _handleSize,
                            height: _handleSize,
                            decoration: const BoxDecoration(color: SatraColors.navy, shape: BoxShape.circle),
                            child: Icon(
                              showCheck ? Icons.check : Icons.arrow_forward,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// A single row in "Transações recentes".
class _TransactionRow extends StatelessWidget {
  final Payment payment;

  const _TransactionRow({required this.payment});

  static const _receiveColor = Color(0xFF3FBF6F);
  static const _failedColor = Color(0xFFD64545);

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final isReceive = payment.paymentType == PaymentType.receive;
    final color = payment.status == PaymentStatus.failed
        ? _failedColor
        : (isReceive ? _receiveColor : SatraColors.navy);
    final icon = isReceive ? Icons.arrow_downward : Icons.arrow_upward;
    final sign = isReceive ? '+' : '-';

    // Assumes Payment.timestamp is Unix seconds (matches every other
    // timestamp convention already used in this codebase, e.g. Nostr's
    // created_at) — the Breez SDK docs don't state the unit explicitly.
    final date = DateTime.fromMillisecondsSinceEpoch(payment.timestamp.toInt() * 1000);
    final dateText =
        '${_twoDigits(date.day)}/${_twoDigits(date.month)} ${_twoDigits(date.hour)}:${_twoDigits(date.minute)}';
    final statusSuffix = switch (payment.status) {
      PaymentStatus.pending => ' · pendente',
      PaymentStatus.failed => ' · falhou',
      PaymentStatus.completed => '',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isReceive ? 'Recebido' : 'Enviado',
                  style: const TextStyle(fontWeight: FontWeight.w600, color: SatraColors.navy),
                ),
                Text(
                  '$dateText$statusSuffix',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
          Text(
            '$sign${_formatThousands(payment.amount.toInt())} sats',
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }
}
