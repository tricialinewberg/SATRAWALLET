import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/breez_service.dart';
import '../theme/colors.dart';

/// Receive screen backed by the real Breez SDK: shows the wallet's actual
/// Lightning Address as a QR by default, and swaps to a real fixed-amount
/// BOLT11 invoice QR when an amount is requested via "Adicionar valor".
class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({super.key});

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  late final Future<String> _addressFuture;
  late final Future<String> _bitcoinAddressFuture;
  String? _fixedInvoice;
  int? _fixedInvoiceAmount;
  bool _generatingInvoice = false;
  bool _receiveOnchain = false;

  @override
  void initState() {
    super.initState();
    _addressFuture = BreezService.instance.initialize().then(
          (_) => BreezService.instance.getLightningAddress(),
        );
    _bitcoinAddressFuture = BreezService.instance.initialize().then(
          (_) => BreezService.instance.getBitcoinAddress(),
        );
  }

  Future<void> _copyToClipboard(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copiado para a área de transferência')),
    );
  }

  Future<void> _promptForAmount() async {
    final controller = TextEditingController();
    final amount = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Adicionar valor'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: SatraColors.navy),
          decoration: const InputDecoration(labelText: 'Valor em sats'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              final value = int.tryParse(controller.text.trim());
              Navigator.of(context).pop(value);
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (amount == null || amount <= 0) return;

    setState(() => _generatingInvoice = true);
    try {
      final invoice = await BreezService.instance.createInvoice(amount);
      if (!mounted) return;
      setState(() {
        _fixedInvoice = invoice;
        _fixedInvoiceAmount = amount;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível gerar a fatura: $e')),
      );
    } finally {
      if (mounted) setState(() => _generatingInvoice = false);
    }
  }

  void _clearFixedInvoice() {
    setState(() {
      _fixedInvoice = null;
      _fixedInvoiceAmount = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SatraColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: SatraColors.navy),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Expanded(
                    child: Text(
                      'Receber',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 22,
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
                selected: {_receiveOnchain},
                onSelectionChanged: (selection) {
                  setState(() {
                    _receiveOnchain = selection.first;
                    if (_receiveOnchain) {
                      _fixedInvoice = null;
                      _fixedInvoiceAmount = null;
                    }
                  });
                },
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: FutureBuilder<String>(
                    future: _receiveOnchain
                        ? _bitcoinAddressFuture
                        : _addressFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 60),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (snapshot.hasError) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Text(
                            'Não foi possível carregar seu endereço: ${snapshot.error}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.red),
                          ),
                        );
                      }

                      final address = snapshot.data!;
                      final qrData = _receiveOnchain
                          ? address
                          : (_fixedInvoice ?? address);

                      return Column(
                        children: [
                          AspectRatio(
                            aspectRatio: 1,
                            child: Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: SatraColors.light),
                              ),
                              child: _generatingInvoice
                                  ? const Center(
                                      child: CircularProgressIndicator())
                                  : QrImageView(
                                      data: qrData, version: QrVersions.auto),
                            ),
                          ),
                          const SizedBox(height: 20),
                          if (!_receiveOnchain && _fixedInvoice != null) ...[
                            Text(
                              'FATURA DE ${_fixedInvoiceAmount ?? ''} SATS',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: SatraColors.medium,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            GestureDetector(
                              onTap: () => _copyToClipboard(_fixedInvoice!),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: SatraColors.background,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: SatraColors.light),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('copiar fatura',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: SatraColors.navy)),
                                    SizedBox(width: 8),
                                    Icon(Icons.copy_outlined,
                                        size: 16, color: SatraColors.navy),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: _clearFixedInvoice,
                              child: const Text(
                                  'Voltar para o endereço Lightning'),
                            ),
                          ] else ...[
                            Text(
                              _receiveOnchain
                                  ? 'ENDEREÇO BITCOIN ON-CHAIN'
                                  : 'ENDEREÇO LIGHTNING',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: SatraColors.medium,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  letterSpacing: 0.5),
                            ),
                            const SizedBox(height: 8),
                            GestureDetector(
                              onTap: () => _copyToClipboard(address),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: SatraColors.background,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: SatraColors.light),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        address,
                                        softWrap: true,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: SatraColors.navy),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Icon(Icons.copy_outlined,
                                        size: 16, color: SatraColors.navy),
                                  ],
                                ),
                              ),
                            ),
                            if (_receiveOnchain) ...[
                              const SizedBox(height: 10),
                              const Text(
                                'Recebimentos on-chain aguardam 3 confirmações '
                                'antes da reivindicação.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: SatraColors.medium,
                                  fontSize: 12,
                                  height: 1.35,
                                ),
                              ),
                              if (BreezService
                                      .instance.lastBitcoinReceiveFeeSats !=
                                  null)
                                Text(
                                  'Taxa informada pela Breez: '
                                  '${BreezService.instance.lastBitcoinReceiveFeeSats} sats.',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: SatraColors.medium,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ],
                          const SizedBox(height: 24),
                          if (!_receiveOnchain)
                            SizedBox(
                              height: 52,
                              child: OutlinedButton.icon(
                                onPressed: _generatingInvoice
                                    ? null
                                    : _promptForAmount,
                                icon: const Icon(Icons.add,
                                    color: SatraColors.navy),
                                label: const Text('Adicionar valor',
                                    style: TextStyle(
                                        color: SatraColors.navy,
                                        fontWeight: FontWeight.w600)),
                                style: OutlinedButton.styleFrom(
                                  side:
                                      const BorderSide(color: SatraColors.navy),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(26)),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
