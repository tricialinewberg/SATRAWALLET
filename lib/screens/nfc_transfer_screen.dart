import 'package:flutter/material.dart';

import '../theme/colors.dart';

/// UI-only recovery screen shown when a physical NFC key is detected.
/// Reading the chip and performing the actual transfer will be wired up
/// later in services/nfc_service.dart.
class NfcTransferScreen extends StatelessWidget {
  const NfcTransferScreen({super.key});

  static const _placeholderSats = '328.041 Sats';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SatraColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            children: [
              const Spacer(flex: 2),
              Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(color: SatraColors.light.withValues(alpha: 0.35), shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(color: SatraColors.light.withValues(alpha: 0.7), shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: const Icon(Icons.nfc, size: 44, color: SatraColors.navy),
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Chave física detectada',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: SatraColors.navy),
              ),
              const SizedBox(height: 8),
              const Text(
                'Encontramos Sats guardados nessa chave.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: SatraColors.medium, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: SatraColors.light),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: SatraColors.background, borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.account_balance_wallet_outlined, color: SatraColors.navy, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('SALDO ESTIMADO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54)),
                        SizedBox(height: 2),
                        Text(_placeholderSats, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: SatraColors.navy)),
                      ],
                    ),
                  ],
                ),
              ),
              const Spacer(flex: 2),
              const Text(
                'Deseja transferir para esta carteira?',
                style: TextStyle(color: SatraColors.medium, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SatraColors.navy,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                  ),
                  child: const Text('Transferir', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: SatraColors.navy,
                    side: const BorderSide(color: SatraColors.light),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                  ),
                  child: const Text('Cancelar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
