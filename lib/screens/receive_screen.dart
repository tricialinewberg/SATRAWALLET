import 'package:flutter/material.dart';

import '../theme/colors.dart';

/// UI-only receive screen. The QR code is a static placeholder until
/// services/breez_service.dart can generate a real invoice/address.
class ReceiveScreen extends StatelessWidget {
  const ReceiveScreen({super.key});

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
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: SatraColors.navy),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 20),
              AspectRatio(
                aspectRatio: 1,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: SatraColors.light),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const Icon(Icons.qr_code_2, size: 220, color: SatraColors.navy),
                      Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(color: SatraColors.navy, shape: BoxShape.circle),
                        child: const Icon(Icons.bolt, color: Colors.white, size: 22),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'ENDEREÇO LIGHTNING',
                textAlign: TextAlign.center,
                style: TextStyle(color: SatraColors.medium, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.center,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: SatraColors.background,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: SatraColors.light),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('alice@satra.io', style: TextStyle(fontWeight: FontWeight.bold, color: SatraColors.navy)),
                      SizedBox(width: 8),
                      Icon(Icons.copy_outlined, size: 16, color: SatraColors.navy),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.add, color: SatraColors.navy),
                  label: const Text('Adicionar valor', style: TextStyle(color: SatraColors.navy, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: SatraColors.navy),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.share_outlined, color: SatraColors.navy),
                  label: const Text('Compartilhar QR Code', style: TextStyle(color: SatraColors.navy, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: SatraColors.light),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
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
