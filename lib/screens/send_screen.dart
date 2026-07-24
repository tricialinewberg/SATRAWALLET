import 'dart:async';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../screens/qr_scanner_screen.dart';
import '../services/breez_service.dart';
import '../theme/colors.dart';

/// Send flow: paste a Lightning invoice, Lightning address, on-chain
/// Bitcoin address, or Spark address/invoice, confirm.
///
/// The destination is parsed (via [BreezService.parseInput]) as soon as the
/// user stops typing, so the screen knows up front whether it already
/// carries its own amount (a fixed-amount BOLT11/Spark invoice) or the user
/// must supply one (a bare address/Lightning address) — different
/// destination kinds genuinely need different handling here, this isn't
/// optional polish.
class SendScreen extends StatefulWidget {
  const SendScreen({super.key});

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  static const _fiatCurrencies = {
    'BRL': ('Real brasileiro', 'R\$'),
    'USD': ('Dólar americano', 'US\$'),
    'EUR': ('Euro', '€'),
  };

  final _destinationController = TextEditingController();
  final _amountController = TextEditingController();
  bool _sending = false;

  Timer? _parseDebounce;
  StreamSubscription<Map<String, double>>? _fiatRatesSubscription;
  bool _parsing = false;
  InputType? _parsedInput;
  String? _parseError;
  bool _sendOnchain = false;
  String _fiatCode = 'BRL';
  int? _balanceSats;
  bool _inputInSats = true;

  @override
  void initState() {
    super.initState();
    _destinationController.addListener(_onDestinationChanged);
    _amountController.addListener(_onAmountChanged);
    _fiatRatesSubscription = BreezService.instance.fiatRatesStream.listen((_) {
      if (mounted) setState(() {});
    });
    _loadWalletDisplay();
  }

  @override
  void dispose() {
    _parseDebounce?.cancel();
    _fiatRatesSubscription?.cancel();
    _destinationController.removeListener(_onDestinationChanged);
    _amountController.removeListener(_onAmountChanged);
    _destinationController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _onDestinationChanged() {
    _parseDebounce?.cancel();
    setState(() {
      _parsedInput = null;
      _parseError = null;
    });

    final text = _destinationController.text.trim();
    if (text.isEmpty) return;

    _parseDebounce =
        Timer(const Duration(milliseconds: 180), () => _parseDestination(text));
  }

  void _onAmountChanged() => setState(() {});

  Future<void> _loadWalletDisplay() async {
    try {
      final code = await BreezService.instance.getSelectedFiatCurrency();
      // Match the pattern in parseInput/preparePayment: ensure the wallet is
      // connected before reading the balance. If the connection failed on the
      // home screen (where the privacy-hidden state masks the error), getBalance
      // would otherwise throw an unhandled StateError out of _requireSdk.
      await BreezService.instance.initialize();
      final balance = BreezService.instance.cachedBalanceSats ??
          await BreezService.instance.getBalance();
      if (BreezService.instance.cachedFiatRate(code) == null) {
        try {
          await BreezService.instance.refreshFiatRates();
        } catch (_) {
          // The balance remains usable even when the optional fiat feed is
          // temporarily unavailable.
        }
      }
      if (!mounted) return;
      setState(() {
        _fiatCode = _fiatCurrencies.containsKey(code) ? code : 'BRL';
        _balanceSats = balance;
      });
    } catch (_) {
      // A failed connection just means the "Saldo: —" placeholder stays —
      // the real error surfaces when the user actually tries to send.
      if (mounted) setState(() => _balanceSats = null);
    }
  }

  Future<void> _parseDestination(String text) async {
    setState(() => _parsing = true);
    try {
      final parsed = await BreezService.instance
          .parseInput(text)
          .timeout(const Duration(seconds: 8));
      if (!mounted || _destinationController.text.trim() != text) return;
      setState(() {
        _parsedInput = parsed;
        _parseError = null;
      });
    } catch (_) {
      if (!mounted || _destinationController.text.trim() != text) return;
      setState(() {
        _parsedInput = null;
        _parseError =
            'Não reconhecemos esse destino. Confira se copiou certinho.';
      });
    } finally {
      if (mounted) setState(() => _parsing = false);
    }
  }

  /// The amount (in sats) the destination already specifies, if any.
  static int? _fixedAmountSatsFor(InputType parsed) => switch (parsed) {
        InputType_Bolt11Invoice(:final field0) => field0.amountMsat != null
            ? (field0.amountMsat! ~/ BigInt.from(1000)).toInt()
            : null,
        InputType_Bip21(:final field0) => field0.amountSat?.toInt(),
        InputType_SparkInvoice(:final field0) => field0.amount?.toInt(),
        _ => null,
      };

  static String _labelFor(InputType parsed) => switch (parsed) {
        InputType_Bolt11Invoice() => 'Fatura Lightning',
        InputType_LightningAddress() => 'Endereço Lightning',
        InputType_BitcoinAddress() => 'Endereço Bitcoin (on-chain)',
        InputType_SparkAddress() => 'Endereço Spark',
        InputType_SparkInvoice() => 'Fatura Spark',
        InputType_LnurlPay() => 'Pagamento LNURL',
        InputType_Bip21() => 'Bitcoin (URI de pagamento)',
        _ => 'Destino reconhecido',
      };

  static bool _isOnchainDestination(InputType parsed) => switch (parsed) {
        InputType_BitcoinAddress() || InputType_Bip21() => true,
        _ => false,
      };

  bool _destinationMatchesSelectedNetwork(InputType parsed) =>
      _isOnchainDestination(parsed) == _sendOnchain;

  void _selectPaymentNetwork(bool sendOnchain) {
    if (_sendOnchain == sendOnchain) return;
    setState(() {
      _sendOnchain = sendOnchain;
      _parsedInput = null;
      _parseError = null;
    });
    final destination = _destinationController.text.trim();
    if (destination.isNotEmpty) {
      _parseDebounce?.cancel();
      _parseDestination(destination);
    }
  }

  /// Min/max sendable, in sats, for LNURL-style destinations — null if not
  /// applicable or not known.
  static (int, int)? _sendableRangeFor(InputType parsed) {
    final payRequest = BreezService.lnurlPayRequestDetailsFor(parsed);
    if (payRequest == null) return null;
    return (
      (payRequest.minSendable ~/ BigInt.from(1000)).toInt(),
      (payRequest.maxSendable ~/ BigInt.from(1000)).toInt()
    );
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    _destinationController.text = text;
    _destinationController.selection =
        TextSelection.collapsed(offset: text.length);
  }

  Future<void> _scanQrCode() async {
    final scannedValue = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (!mounted || scannedValue == null || scannedValue.isEmpty) return;
    final value = _normalizePaymentQr(scannedValue);
    _destinationController.text = value;
    _destinationController.selection =
        TextSelection.collapsed(offset: value.length);
    _parseDebounce?.cancel();
    await _parseDestination(value);
  }

  static String _normalizePaymentQr(String rawValue) {
    var value = rawValue.trim();
    value = value
        .replaceFirst(RegExp(r'^lightning:(//)?', caseSensitive: false), '')
        .trim();
    try {
      return Uri.decodeComponent(value);
    } on FormatException {
      return value;
    }
  }

  Future<void> _selectFiatCurrency(String selected) async {
    if (selected == _fiatCode) return;
    final satsBeforeCurrencyChange = _enteredAmountSats();
    await BreezService.instance.setSelectedFiatCurrency(selected);
    if (!mounted) return;
    setState(() => _fiatCode = selected);
    if (!_inputInSats && satsBeforeCurrencyChange != null) {
      final rate = BreezService.instance.cachedFiatRate(selected);
      if (rate != null) {
        final value = satsBeforeCurrencyChange / 100000000 * rate;
        _amountController.text = value
            .toStringAsFixed(2)
            .replaceFirst('.', selected == 'USD' ? '.' : ',');
        _amountController.selection =
            TextSelection.collapsed(offset: _amountController.text.length);
      }
    }
  }

  String _fiatTextFor(int? sats) {
    if (sats == null) return '${_fiatCurrencies[_fiatCode]!.$2} —';
    final rate = BreezService.instance.cachedFiatRate(_fiatCode);
    if (rate == null) return '${_fiatCurrencies[_fiatCode]!.$2} —';
    final value = sats / 100000000 * rate;
    final decimal = _fiatCode == 'USD' ? '.' : ',';
    return '${_fiatCurrencies[_fiatCode]!.$2} ${value.toStringAsFixed(2).replaceFirst('.', decimal)}';
  }

  int? _enteredAmountSats() {
    final text = _amountController.text.trim();
    if (text.isEmpty) return null;
    if (_inputInSats) return int.tryParse(text);
    final fiatValue = double.tryParse(text.replaceAll(',', '.'));
    final rate = BreezService.instance.cachedFiatRate(_fiatCode);
    if (fiatValue == null || rate == null || rate <= 0) return null;
    return (fiatValue / rate * 100000000).round();
  }

  String _secondaryAmountText() {
    final sats = _enteredAmountSats();
    if (_inputInSats) return _fiatTextFor(sats);
    return sats == null ? '— sats' : '${_formatThousands(sats)} sats';
  }

  void _switchAmountUnit() {
    final sats = _enteredAmountSats();
    final rate = BreezService.instance.cachedFiatRate(_fiatCode);
    setState(() => _inputInSats = !_inputInSats);
    if (sats == null) {
      _amountController.clear();
    } else if (_inputInSats) {
      _amountController.text = sats.toString();
    } else if (rate != null) {
      final value = sats / 100000000 * rate;
      _amountController.text = value
          .toStringAsFixed(2)
          .replaceFirst('.', _fiatCode == 'USD' ? '.' : ',');
    }
    _amountController.selection =
        TextSelection.collapsed(offset: _amountController.text.length);
  }

  Future<void> _showResultDialog(
      {required bool success, required String title, required String message}) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              success ? Icons.check_circle : Icons.error_outline,
              color: success ? SatraColors.success : SatraColors.error,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(title)),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirm() async {
    final destination = _destinationController.text.trim();
    if (destination.isEmpty) {
      await _showResultDialog(
        success: false,
        title: 'Destino em branco',
        message: 'Cole uma fatura ou endereço para continuar.',
      );
      return;
    }

    final parsed = _parsedInput;
    if (parsed != null && !_destinationMatchesSelectedNetwork(parsed)) {
      await _showResultDialog(
        success: false,
        title: _sendOnchain
            ? 'Este destino não é on-chain'
            : 'Este é um endereço on-chain',
        message: _sendOnchain
            ? 'Selecione Lightning ou informe um endereço Bitcoin on-chain.'
            : 'Selecione Bitcoin para enviar para esse endereço.',
      );
      return;
    }
    final fixedAmount = parsed != null ? _fixedAmountSatsFor(parsed) : null;

    int amountSats;
    if (fixedAmount != null) {
      amountSats = fixedAmount;
    } else {
      final parsedAmount = _enteredAmountSats();
      if (parsedAmount == null || parsedAmount <= 0) {
        await _showResultDialog(
          success: false,
          title: 'Valor necessário',
          message:
              'Este destino não tem um valor fixo — informe quantos sats deseja enviar.',
        );
        return;
      }
      amountSats = parsedAmount;
    }

    setState(() => _sending = true);
    try {
      final prepared = await BreezService.instance.preparePayment(
        destination,
        amountSats: amountSats,
        parsedInput: parsed,
      );
      if (!mounted) return;
      final speed = await _confirmPreparedPayment(prepared, amountSats);
      if (!mounted || speed == null) return;
      final payment = await BreezService.instance.sendPreparedPayment(
        prepared,
        onchainSpeed: speed,
      );
      if (!mounted) return;
      final completed = payment.status == PaymentStatus.completed;
      final pending = payment.status == PaymentStatus.pending;
      await _showResultDialog(
        success: completed,
        title: completed
            ? 'Pagamento concluído'
            : pending
                ? 'Pagamento pendente'
                : 'Pagamento falhou',
        message: completed
            ? '${_formatThousands(payment.amount.toInt())} sats enviados com sucesso.'
            : pending
                ? 'O pagamento foi aceito, mas ainda aguarda confirmação. '
                    'Confira o histórico antes de tentar novamente.'
                : 'O SDK informou que o pagamento não foi concluído.',
      );
      if (!mounted) return;
      if (completed || pending) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      await _showResultDialog(
        success: false,
        title: 'Não foi possível enviar',
        message: '$e',
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<OnchainConfirmationSpeed?> _confirmPreparedPayment(
    BreezPreparedPayment prepared,
    int amountSats,
  ) {
    var selectedSpeed = OnchainConfirmationSpeed.medium;
    return showDialog<OnchainConfirmationSpeed>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final fee = prepared.feeFor(selectedSpeed).toInt();
          return AlertDialog(
            title: const Text('Confirmar pagamento'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Valor: ${_formatThousands(amountSats)} sats'),
                const SizedBox(height: 8),
                Text('Taxa estimada: ${_formatThousands(fee)} sats'),
                if (prepared.isOnchain) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Velocidade de confirmação',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  RadioGroup<OnchainConfirmationSpeed>(
                    groupValue: selectedSpeed,
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => selectedSpeed = value);
                      }
                    },
                    child: const Column(
                      children: [
                        RadioListTile(
                          value: OnchainConfirmationSpeed.slow,
                          title: Text('Econômica'),
                        ),
                        RadioListTile(
                          value: OnchainConfirmationSpeed.medium,
                          title: Text('Normal'),
                        ),
                        RadioListTile(
                          value: OnchainConfirmationSpeed.fast,
                          title: Text('Rápida'),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(selectedSpeed),
                child: const Text('Enviar'),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _formatThousands(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final parsed = _parsedInput;
    final fixedAmount = parsed != null ? _fixedAmountSatsFor(parsed) : null;
    final sendableRange = parsed != null ? _sendableRangeFor(parsed) : null;

    return Scaffold(
      backgroundColor: SatraColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: SatraColors.navy),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const Expanded(
                  child: Text(
                    'Enviar',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: SatraColors.navy),
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.bolt),
                  label: Text('Lightning'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.currency_bitcoin),
                  label: Text('Bitcoin'),
                ),
              ],
              selected: {_sendOnchain},
              onSelectionChanged: _sending
                  ? null
                  : (selection) => _selectPaymentNetwork(selection.first),
            ),
            const SizedBox(height: 12),
            Text(
              _sendOnchain
                  ? 'Envie para um endereço Bitcoin. A taxa e a velocidade '
                      'serão mostradas antes da confirmação.'
                  : 'Envie por fatura, endereço Lightning ou Spark.',
              style: const TextStyle(
                color: SatraColors.medium,
                fontSize: 13,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _scanQrCode,
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 21),
                  label: const Text('Ler QR Code'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: SatraColors.navy,
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: SatraColors.light),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              _sendOnchain ? 'ENDEREÇO BITCOIN' : 'FATURA OU ENDEREÇO',
              style: const TextStyle(
                  color: SatraColors.medium,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 0.5),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: SatraColors.light),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _destinationController,
                      minLines: 3,
                      maxLines: 5,
                      style: const TextStyle(color: SatraColors.navy),
                      decoration: InputDecoration(
                        hintText: _sendOnchain
                            ? 'Endereço Bitcoin ou URI bitcoin:'
                            : 'Fatura Lightning, endereço Lightning ou Spark',
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.all(16),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.content_paste,
                        color: SatraColors.medium, size: 20),
                    tooltip: 'Colar',
                    onPressed: _pasteFromClipboard,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (_parsing)
              const Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: SatraColors.medium),
                  ),
                  SizedBox(width: 8),
                  Text('Identificando destino...',
                      style:
                          TextStyle(color: SatraColors.medium, fontSize: 13)),
                ],
              )
            else if (_parseError != null)
              Row(
                children: [
                  const Icon(Icons.error_outline,
                      color: SatraColors.error, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(_parseError!,
                        style: const TextStyle(
                            color: SatraColors.error, fontSize: 13)),
                  ),
                ],
              )
            else if (parsed != null &&
                !_destinationMatchesSelectedNetwork(parsed))
              Row(
                children: [
                  const Icon(Icons.swap_horiz,
                      color: SatraColors.warningIcon, size: 17),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _sendOnchain
                          ? 'Destino Lightning detectado. Selecione Lightning.'
                          : 'Endereço Bitcoin detectado. Selecione Bitcoin.',
                      style: const TextStyle(
                        color: SatraColors.warningDark,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              )
            else if (parsed != null)
              Row(
                children: [
                  const Icon(Icons.check_circle_outline,
                      color: SatraColors.medium, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(_labelFor(parsed),
                        style: const TextStyle(
                            color: SatraColors.medium,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'VALOR DO ENVIO',
                  style: TextStyle(
                      color: SatraColors.medium,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 0.5),
                ),
                Text(
                  _balanceSats == null
                      ? 'Saldo: —'
                      : 'Saldo: ${_formatThousands(_balanceSats!)} sats',
                  style: const TextStyle(
                      color: SatraColors.medium,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final code in _fiatCurrencies.keys)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: SizedBox(
                            width: double.infinity,
                            child: Text(code, textAlign: TextAlign.center)),
                        selected: _fiatCode == code,
                        onSelected: (_) => _selectFiatCurrency(code),
                        showCheckmark: false,
                        selectedColor: SatraColors.navy,
                        backgroundColor: Colors.white,
                        side: BorderSide(
                            color: _fiatCode == code
                                ? SatraColors.navy
                                : SatraColors.light),
                        labelStyle: TextStyle(
                          color: _fiatCode == code
                              ? Colors.white
                              : SatraColors.medium,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (fixedAmount != null)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: SatraColors.light.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: SatraColors.light),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.lock_outline,
                            size: 16, color: SatraColors.navy),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${_formatThousands(fixedAmount)} sats',
                            style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: SatraColors.navy),
                          ),
                        ),
                        const Text('Valor da fatura',
                            style: TextStyle(
                                color: SatraColors.medium, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          Text('≈ ${_fiatTextFor(fixedAmount)}',
                              style: const TextStyle(
                                  color: SatraColors.medium,
                                  fontWeight: FontWeight.w600)),
                          const Spacer(),
                          Text(_fiatCode,
                              style: const TextStyle(
                                  color: SatraColors.navy,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              Container(
                padding: const EdgeInsets.fromLTRB(18, 10, 14, 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: SatraColors.light),
                ),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _amountController,
                            keyboardType: TextInputType.numberWithOptions(
                                decimal: !_inputInSats),
                            style: const TextStyle(
                                color: SatraColors.navy,
                                fontSize: 30,
                                fontWeight: FontWeight.w800),
                            decoration: const InputDecoration(
                              hintText: '0',
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        Text(
                          _inputInSats
                              ? 'sats'
                              : _fiatCurrencies[_fiatCode]!.$2,
                          style: const TextStyle(
                              color: SatraColors.navy,
                              fontSize: 18,
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const Divider(height: 1, color: SatraColors.light),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Text(
                            '≈ ${_secondaryAmountText()}',
                            style: const TextStyle(
                                color: SatraColors.navy,
                                fontWeight: FontWeight.w700),
                          ),
                          const Spacer(),
                          IconButton.filled(
                            onPressed: _switchAmountUnit,
                            tooltip: _inputInSats
                                ? 'Digitar em $_fiatCode'
                                : 'Digitar em sats',
                            style: IconButton.styleFrom(
                              backgroundColor: SatraColors.navy,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.swap_vert_rounded),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (sendableRange != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Entre ${_formatThousands(sendableRange.$1)} e ${_formatThousands(sendableRange.$2)} sats',
                  style:
                      const TextStyle(color: SatraColors.medium, fontSize: 12),
                ),
              ],
            ],
            const SizedBox(height: 28),
            SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: _sending ? null : _confirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: SatraColors.navy,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28)),
                ),
                child: _sending
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Confirmar',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
