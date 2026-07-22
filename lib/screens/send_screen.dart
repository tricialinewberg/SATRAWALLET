import 'dart:async';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  final _destinationController = TextEditingController();
  final _amountController = TextEditingController();
  bool _sending = false;

  Timer? _parseDebounce;
  bool _parsing = false;
  InputType? _parsedInput;
  String? _parseError;

  @override
  void initState() {
    super.initState();
    _destinationController.addListener(_onDestinationChanged);
  }

  @override
  void dispose() {
    _parseDebounce?.cancel();
    _destinationController.removeListener(_onDestinationChanged);
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

    _parseDebounce = Timer(const Duration(milliseconds: 500), () => _parseDestination(text));
  }

  Future<void> _parseDestination(String text) async {
    setState(() => _parsing = true);
    try {
      final parsed = await BreezService.instance.parseInput(text);
      if (!mounted || _destinationController.text.trim() != text) return;
      setState(() {
        _parsedInput = parsed;
        _parseError = null;
      });
    } catch (_) {
      if (!mounted || _destinationController.text.trim() != text) return;
      setState(() {
        _parsedInput = null;
        _parseError = 'Não reconhecemos esse destino. Confira se copiou certinho.';
      });
    } finally {
      if (mounted) setState(() => _parsing = false);
    }
  }

  /// The amount (in sats) the destination already specifies, if any.
  static int? _fixedAmountSatsFor(InputType parsed) => switch (parsed) {
        InputType_Bolt11Invoice(:final field0) =>
          field0.amountMsat != null ? (field0.amountMsat! ~/ BigInt.from(1000)).toInt() : null,
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

  /// Min/max sendable, in sats, for LNURL-style destinations — null if not
  /// applicable or not known.
  static (int, int)? _sendableRangeFor(InputType parsed) {
    final payRequest = BreezService.lnurlPayRequestDetailsFor(parsed);
    if (payRequest == null) return null;
    return ((payRequest.minSendable ~/ BigInt.from(1000)).toInt(), (payRequest.maxSendable ~/ BigInt.from(1000)).toInt());
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    _destinationController.text = text;
    _destinationController.selection = TextSelection.collapsed(offset: text.length);
  }

  Future<void> _showResultDialog({required bool success, required String title, required String message}) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              success ? Icons.check_circle : Icons.error_outline,
              color: success ? const Color(0xFF3FBF6F) : const Color(0xFFD64545),
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
    final fixedAmount = parsed != null ? _fixedAmountSatsFor(parsed) : null;

    int amountSats;
    if (fixedAmount != null) {
      amountSats = fixedAmount;
    } else {
      final amountText = _amountController.text.trim();
      final parsedAmount = int.tryParse(amountText);
      if (amountText.isEmpty || parsedAmount == null || parsedAmount <= 0) {
        await _showResultDialog(
          success: false,
          title: 'Valor necessário',
          message: 'Este destino não tem um valor fixo — informe quantos sats deseja enviar.',
        );
        return;
      }
      amountSats = parsedAmount;
    }

    setState(() => _sending = true);
    try {
      final payment = await BreezService.instance.sendPayment(
        destination,
        amountSats: amountSats,
        parsedInput: parsed,
      );
      if (!mounted) return;
      await _showResultDialog(
        success: true,
        title: 'Pagamento enviado',
        message: '${_formatThousands(payment.amount.toInt())} sats enviados com sucesso.',
      );
      if (!mounted) return;
      Navigator.of(context).pop();
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
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: SatraColors.navy),
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              'FATURA OU ENDEREÇO',
              style: TextStyle(color: SatraColors.medium, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5),
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
                      decoration: const InputDecoration(
                        hintText: 'Fatura Lightning, endereço Lightning, Bitcoin ou Spark',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.all(16),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.content_paste, color: SatraColors.medium, size: 20),
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
                    child: CircularProgressIndicator(strokeWidth: 2, color: SatraColors.medium),
                  ),
                  SizedBox(width: 8),
                  Text('Identificando destino...', style: TextStyle(color: SatraColors.medium, fontSize: 13)),
                ],
              )
            else if (_parseError != null)
              Row(
                children: [
                  const Icon(Icons.error_outline, color: Color(0xFFD64545), size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(_parseError!, style: const TextStyle(color: Color(0xFFD64545), fontSize: 13)),
                  ),
                ],
              )
            else if (parsed != null)
              Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: SatraColors.medium, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(_labelFor(parsed), style: const TextStyle(color: SatraColors.medium, fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            const SizedBox(height: 20),
            const Text(
              'VALOR EM SATS',
              style: TextStyle(color: SatraColors.medium, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5),
            ),
            const SizedBox(height: 8),
            if (fixedAmount != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: SatraColors.light.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: SatraColors.light),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lock_outline, size: 16, color: SatraColors.navy),
                    const SizedBox(width: 8),
                    Text(
                      '${_formatThousands(fixedAmount)} sats (valor fixo do destino)',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: SatraColors.navy),
                    ),
                  ],
                ),
              )
            else ...[
              TextField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: SatraColors.navy),
                decoration: InputDecoration(
                  hintText: 'Necessário para este destino',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: SatraColors.light),
                  ),
                ),
              ),
              if (sendableRange != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Entre ${_formatThousands(sendableRange.$1)} e ${_formatThousands(sendableRange.$2)} sats',
                  style: const TextStyle(color: SatraColors.medium, fontSize: 12),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                ),
                child: _sending
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Confirmar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
