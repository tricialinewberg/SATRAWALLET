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

class _FiatCurrency {
  final String code;
  final String label;
  final String symbol;
  final bool commaDecimal;

  const _FiatCurrency(this.code, this.label, this.symbol,
      {required this.commaDecimal});
}

const _fiatCurrencies = [
  _FiatCurrency('BRL', 'Real brasileiro', 'R\$', commaDecimal: true),
  _FiatCurrency('USD', 'Dólar americano', 'US\$', commaDecimal: false),
  _FiatCurrency('EUR', 'Euro', '€', commaDecimal: true),
];

/// Main wallet screen, backed by the real Breez SDK connection in
/// [BreezService]: balance and its BRL estimate are live.
class WalletHomeScreen extends StatefulWidget {
  const WalletHomeScreen({super.key});

  @override
  State<WalletHomeScreen> createState() => _WalletHomeScreenState();
}

class _WalletHomeScreenState extends State<WalletHomeScreen>
    with RouteAware, SingleTickerProviderStateMixin {
  // Privacy-first: never flash a loading placeholder or the real balance
  // when the wallet opens. The user explicitly reveals it with the eye
  // button, and returning to this screen starts hidden again.
  bool _balanceHidden = true;
  _FiatCurrency _selectedFiatCurrency = _fiatCurrencies.first;
  late final Future<void> _connectFuture;

  // Drives the "payment received" banner (see [_buildPaymentBanner]) shown
  // whenever a new *completed* incoming payment is seen — not on every
  // balanceStream/paymentsStream emission, which also fires on plain
  // re-syncs and on outgoing payments (e.g. the escape sweep).
  late final AnimationController _paymentBannerController;
  late final Animation<double> _paymentBannerOpacity;
  late final Animation<double> _paymentBannerScale;
  late final Animation<Offset> _paymentBannerSlide;
  String? _paymentBannerText;
  StreamSubscription<List<Payment>>? _paymentsSubscription;
  final Set<String> _seenCompletedReceiveIds = {};
  bool _paymentsBaselineSet = false;

  // Entrance (fade/scale/slide in) -> hold (fully visible) -> exit (fade
  // out); expressed as millisecond weights so the total controller
  // duration and each phase's proportional share both stay in one place.
  static const _paymentBannerEntranceMs = 350;
  static const _paymentBannerHoldMs = 2200;
  static const _paymentBannerExitMs = 450;
  static const _paymentBannerDuration = Duration(
    milliseconds:
        _paymentBannerEntranceMs + _paymentBannerHoldMs + _paymentBannerExitMs,
  );

  @override
  void initState() {
    super.initState();
    _connectFuture = BreezService.instance.initialize();
    _loadSelectedFiatCurrency();
    _startNfcListening();

    _paymentBannerController = AnimationController(
      vsync: this,
      duration: _paymentBannerDuration,
    );
    _paymentBannerOpacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: _paymentBannerEntranceMs.toDouble(),
      ),
      TweenSequenceItem(
        tween: ConstantTween(1.0),
        weight: _paymentBannerHoldMs.toDouble(),
      ),
      TweenSequenceItem(
        tween:
            Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeIn)),
        weight: _paymentBannerExitMs.toDouble(),
      ),
    ]).animate(_paymentBannerController);
    _paymentBannerScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.88, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: _paymentBannerEntranceMs.toDouble(),
      ),
      TweenSequenceItem(
        tween: ConstantTween(1.0),
        weight: (_paymentBannerHoldMs + _paymentBannerExitMs).toDouble(),
      ),
    ]).animate(_paymentBannerController);
    _paymentBannerSlide = TweenSequence<Offset>([
      TweenSequenceItem(
        tween: Tween(begin: const Offset(0, -0.3), end: Offset.zero)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: _paymentBannerEntranceMs.toDouble(),
      ),
      TweenSequenceItem(
        tween: ConstantTween(Offset.zero),
        weight: (_paymentBannerHoldMs + _paymentBannerExitMs).toDouble(),
      ),
    ]).animate(_paymentBannerController);
    _paymentsSubscription =
        BreezService.instance.paymentsStream.listen(_onPaymentsUpdate);
  }

  Future<void> _loadSelectedFiatCurrency() async {
    final savedCode = await BreezService.instance.getSelectedFiatCurrency();
    if (!mounted) return;
    setState(() {
      _selectedFiatCurrency = _fiatCurrencies.firstWhere(
        (currency) => currency.code == savedCode,
        orElse: () => _fiatCurrencies.first,
      );
    });
  }

  /// Detects newly-completed incoming payments by diffing against what's
  /// already been seen, so the celebration only plays once per payment (and
  /// never for the historical list a reconnect re-emits). The first
  /// snapshot just seeds the baseline instead of celebrating every payment
  /// already in the wallet's history.
  void _onPaymentsUpdate(List<Payment> payments) {
    final completedReceives = payments.where(
      (p) =>
          p.paymentType == PaymentType.receive &&
          p.status == PaymentStatus.completed,
    );

    if (!_paymentsBaselineSet) {
      _seenCompletedReceiveIds.addAll(completedReceives.map((p) => p.id));
      _paymentsBaselineSet = true;
      return;
    }

    for (final payment in completedReceives) {
      if (_seenCompletedReceiveIds.add(payment.id)) {
        _onIncomingPayment(payment);
      }
    }
  }

  void _onIncomingPayment(Payment payment) {
    if (!mounted) return;
    final amountText = _formatThousands(payment.amount.toInt());
    setState(() => _paymentBannerText =
        _balanceHidden ? 'Pagamento recebido' : '+$amountText sats recebidos');
    _paymentBannerController.forward(from: 0);
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
    _paymentsSubscription?.cancel();
    _paymentBannerController.dispose();
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
      onCredentialDetected: (envelopeJson) {
        if (!mounted) return;
        Navigator.of(context).pushNamed(SatraRoutes.nfcTransfer);
      },
    );
  }

  static String _formatFiat(double value, _FiatCurrency currency) {
    final fixed = value.toStringAsFixed(2);
    final parts = fixed.split('.');
    final integerDigits = parts[0];
    final grouped = StringBuffer();
    final thousandsSeparator = currency.commaDecimal ? '.' : ',';
    for (var i = 0; i < integerDigits.length; i++) {
      if (i > 0 && (integerDigits.length - i) % 3 == 0)
        grouped.write(thousandsSeparator);
      grouped.write(integerDigits[i]);
    }
    final decimalSeparator = currency.commaDecimal ? ',' : '.';
    return '${currency.symbol} $grouped$decimalSeparator${parts[1]}';
  }

  Widget _buildHiddenBalance() {
    return Column(
      children: [
        const Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '*****',
                style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    color: SatraColors.navy),
              ),
              TextSpan(
                text: '  Sats',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: SatraColors.navy),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _chooseFiatCurrency,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '≈ ${_selectedFiatCurrency.symbol} ****',
                  style: const TextStyle(
                      color: SatraColors.medium, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.expand_more,
                    size: 18, color: SatraColors.medium),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _chooseFiatCurrency() async {
    final selected = await showModalBottomSheet<_FiatCurrency>(
      context: context,
      backgroundColor: SatraColors.background,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Moeda de referência',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: SatraColors.navy),
              ),
              const SizedBox(height: 8),
              const Text(
                'O saldo continua em sats. Esta opção altera apenas a conversão exibida.',
                style: TextStyle(color: SatraColors.medium, height: 1.3),
              ),
              const SizedBox(height: 12),
              for (final currency in _fiatCurrencies)
                RadioListTile<_FiatCurrency>(
                  value: currency,
                  groupValue: _selectedFiatCurrency,
                  activeColor: SatraColors.medium,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${currency.symbol}  ${currency.label}',
                      style: const TextStyle(color: SatraColors.navy)),
                  subtitle: Text(currency.code,
                      style: const TextStyle(color: SatraColors.medium)),
                  onChanged: (value) => Navigator.of(sheetContext).pop(value),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || selected == null) return;
    await BreezService.instance.setSelectedFiatCurrency(selected.code);
    if (mounted) setState(() => _selectedFiatCurrency = selected);
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
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: SatraColors.navy,
                  fontSize: 16),
            ),
            const SizedBox(height: 12),
            const Text(
              'Ao deslizar, todo o saldo da sua carteira é enviado automaticamente '
              'para sua chave física. Ao mesmo tempo, um alerta discreto é enviado '
              'para as pessoas de confiança que você cadastrou.\n\n'
              'Isso só funciona se a chave física já tiver sido configurada com uma '
              'senha antes (menu > Senha da chave física) — sem isso, o saldo não '
              'tem para onde ir.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: SatraColors.navy, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 16),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.warning_rounded, color: Colors.red, size: 18),
                SizedBox(width: 6),
                Text(
                  'Essa ação não pode ser desfeita.',
                  style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 13),
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
    // immediately, regardless of how long the Breez sweep or a slow Nostr
    // relay takes.
    unawaited(_sweepToFixedEscapeWallet());
    unawaited(_sendEscapeAlert());
    Navigator.of(context).pushNamedAndRemoveUntil(
      SatraRoutes.escapeConfirmation,
      (route) => false,
    );
  }

  /// Sweeps this wallet's entire balance to the FIXED escape wallet
  /// configured ahead of time during physical-key setup (see
  /// [NfcKeyPasswordSetupScreen] and [BreezService.getEscapeWalletMnemonic]).
  ///
  /// Deliberately does NOT touch NFC at all: the escape wallet's mnemonic
  /// was already written to the physical key once, at setup time, and
  /// never needs to change again — moving wallet creation and NFC writing
  /// out of this time-critical, hardware-dependent path (and out of a
  /// disposable per-escape wallet whose tag write had to succeed in the
  /// moment or funds were stranded) is the whole point of the fixed-wallet
  /// design. If no escape wallet has been configured yet, the sweep is
  /// skipped entirely — the Nostr alert in [_sendEscapeAlert] still fires
  /// regardless, since it's a separate, unawaited step.
  Future<void> _sweepToFixedEscapeWallet() async {
    try {
      final escapeMnemonic =
          await BreezService.instance.getEscapeWalletMnemonic();
      if (escapeMnemonic == null || escapeMnemonic.isEmpty) {
        debugPrint('[WalletHomeScreen] nenhuma carteira de escape configurada');
        return;
      }

      await BreezService.instance
          .executeEscapeSweep(escapeWalletMnemonic: escapeMnemonic);
    } catch (e) {
      // Best-effort — the confirmation screen is shown regardless of outcome.
      debugPrint('[WalletHomeScreen] escape sweep failed: $e');
    }
  }

  Future<void> _sendEscapeAlert() async {
    try {
      await NostrService.instance.sendEscapeAlert();
    } catch (e) {
      debugPrint('[WalletHomeScreen] escape Nostr alert failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SatraColors.background,
      endDrawer: const SideMenuScreen(),
      body: SafeArea(
        child: Stack(
          children: [
            Builder(
              builder: (context) => Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: Icon(
                              _balanceHidden
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: SatraColors.medium),
                          onPressed: () =>
                              setState(() => _balanceHidden = !_balanceHidden),
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
                        // Render the privacy state immediately, without waiting for
                        // the wallet connection. This prevents the first frame from
                        // showing either a loading state or stale balance values.
                        if (_balanceHidden) return _buildHiddenBalance();

                        if (connectSnapshot.connectionState !=
                            ConnectionState.done) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 14),
                            child: SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: SatraColors.medium),
                            ),
                          );
                        }
                        if (connectSnapshot.hasError) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 14),
                            child: Text(
                              'Não foi possível conectar à carteira',
                              style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.w600),
                            ),
                          );
                        }
                        return StreamBuilder<int>(
                          stream: BreezService.instance.balanceStream,
                          initialData: BreezService.instance.cachedBalanceSats,
                          builder: (context, balanceSnapshot) {
                            final sats = balanceSnapshot.data;
                            final fiatRate = BreezService.instance
                                .cachedFiatRate(_selectedFiatCurrency.code);
                            final fiatText = sats != null && fiatRate != null
                                ? _formatFiat(sats / 100000000 * fiatRate,
                                    _selectedFiatCurrency)
                                : null;

                            return Column(
                              children: [
                                Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: _balanceHidden
                                            ? '*****'
                                            : (sats != null
                                                ? _formatThousands(sats)
                                                : '···'),
                                        style: const TextStyle(
                                          fontSize: 30,
                                          fontWeight: FontWeight.w900,
                                          color: SatraColors.navy,
                                        ),
                                      ),
                                      const TextSpan(
                                        text: '  Sats',
                                        style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: SatraColors.navy),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: _chooseFiatCurrency,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 5),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '≈ ${fiatText ?? '—'}',
                                          style: const TextStyle(
                                              color: SatraColors.medium,
                                              fontWeight: FontWeight.w600),
                                        ),
                                        const SizedBox(width: 4),
                                        const Icon(Icons.expand_more,
                                            size: 18,
                                            color: SatraColors.medium),
                                      ],
                                    ),
                                  ),
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
                              onPressed: () => Navigator.of(context)
                                  .pushNamed(SatraRoutes.receive),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: SatraColors.navy,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(26)),
                              ),
                              child: const Text('Receber',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 52,
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(context)
                                  .pushNamed(SatraRoutes.send),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: SatraColors.navy,
                                side:
                                    const BorderSide(color: SatraColors.light),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(26)),
                              ),
                              child: const Text('Enviar',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w600)),
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
                        style: TextStyle(
                            color: SatraColors.medium,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            letterSpacing: 0.5),
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
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: SatraColors.medium),
                                ),
                              );
                            }
                            if (payments.isEmpty) {
                              return const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.history,
                                      color: SatraColors.light, size: 32),
                                  SizedBox(height: 10),
                                  Text('Nenhuma transação ainda',
                                      style: TextStyle(color: Colors.black54)),
                                ],
                              );
                            }
                            return ListView.separated(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              itemCount: payments.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(
                                      height: 1, color: SatraColors.background),
                              itemBuilder: (context, index) =>
                                  _TransactionRow(payment: payments[index]),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _EscapeSlider(onConfirmed: _onEscapeConfirmed),
                    const SizedBox(height: 8),
                    IconButton(
                      icon: const Icon(Icons.info_outline,
                          color: SatraColors.medium),
                      onPressed: _openEscapeInfo,
                    ),
                  ],
                ),
              ),
            ),
            _buildPaymentBanner(),
          ],
        ),
      ),
    );
  }

  /// Centered, near-top banner shown on top of the rest of the screen
  /// while [_paymentBannerController] is active — fades/scales/slides in,
  /// holds fully visible, then fades out (see the phase durations above).
  /// Purely decorative, so it never intercepts touches.
  Widget _buildPaymentBanner() {
    return Positioned(
      top: 72,
      left: 24,
      right: 24,
      child: IgnorePointer(
        child: Center(
          child: FadeTransition(
            opacity: _paymentBannerOpacity,
            child: SlideTransition(
              position: _paymentBannerSlide,
              child: ScaleTransition(
                scale: _paymentBannerScale,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: SatraColors.navy,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(
                            color: Color(0xFF3FBF6F), shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: const Icon(Icons.arrow_downward,
                            color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          _paymentBannerText ?? '',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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

class _EscapeSliderState extends State<_EscapeSlider>
    with SingleTickerProviderStateMixin {
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
    _successController =
        AnimationController(vsync: this, duration: _successDuration);
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
            final fraction = _completing
                ? _dragFractionAtRelease +
                    (1.0 - _dragFractionAtRelease) * settleT
                : _dragFraction;

            // Rises to a peak mid-pulse then eases back down — a quick
            // "thump" on the handle rather than a lasting size change.
            final pulseT = _pulseCurve.transform(t);
            final pulse = _completing
                ? (1 - (pulseT - 0.5).abs() * 2).clamp(0.0, 1.0)
                : 0.0;
            final handleScale = 1.0 + pulse * 0.22;

            final showCheck = _completing && t >= _checkThreshold;

            // A filled bar that grows from the handle's resting position
            // out to wherever it currently sits, so the colored area is
            // always proportional to how far the handle has been dragged
            // — rather than tinting the whole track's background at once,
            // which front-loads the color change (white blends visibly
            // dark within the first few percent of drag) and reads as an
            // instant jump instead of a progressive fill.
            final fillWidth = (fraction * maxDrag + _handleSize + 8)
                .clamp(0.0, constraints.maxWidth);

            return Container(
              height: _trackHeight,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(_trackHeight / 2),
                border: Border.all(color: SatraColors.light),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_trackHeight / 2),
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                          width: fillWidth,
                          height: _trackHeight,
                          color: SatraColors.navy),
                    ),
                    Center(
                      child: Text(
                        'deslize para o modo de escape',
                        style: TextStyle(
                          color: Color.lerp(
                              SatraColors.navy, Colors.white, fraction),
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
                                  _dragFraction = ((_dragFraction * maxDrag) +
                                          details.delta.dx) /
                                      maxDrag;
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
                              decoration: const BoxDecoration(
                                  color: SatraColors.navy,
                                  shape: BoxShape.circle),
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
    final date =
        DateTime.fromMillisecondsSinceEpoch(payment.timestamp.toInt() * 1000);
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
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
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
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, color: SatraColors.navy),
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
