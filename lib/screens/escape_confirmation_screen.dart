import 'package:flutter/material.dart';

import '../routes.dart';
import '../theme/colors.dart';

/// Shown right after the escape gesture completes. UI only — no real funds
/// are moved and no Nostr alert is sent yet, that lives in services/ later.
/// Per the product spec, the app quietly returns to looking like a plain
/// calculator a few seconds after this screen is shown.
class EscapeConfirmationScreen extends StatefulWidget {
  const EscapeConfirmationScreen({super.key});

  @override
  State<EscapeConfirmationScreen> createState() => _EscapeConfirmationScreenState();
}

class _EscapeConfirmationScreenState extends State<EscapeConfirmationScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 4), () {
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(
        SatraRoutes.calculator,
        (route) => false,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SatraColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 3),
              Container(
                width: 96,
                height: 96,
                decoration: const BoxDecoration(color: Color(0xFF3FBF6F), shape: BoxShape.circle),
                child: const Icon(Icons.check, color: Colors.white, size: 48),
              ),
              const SizedBox(height: 28),
              const Text(
                'Saldo enviado para sua chave física',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: SatraColors.navy),
              ),
              const SizedBox(height: 10),
              const Text(
                'Sua rede de confiança foi notificada',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: SatraColors.medium, fontWeight: FontWeight.w600),
              ),
              const Spacer(flex: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: SatraColors.light),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shield_outlined, size: 16, color: SatraColors.medium),
                    SizedBox(width: 8),
                    Text('PROTOCOLO DE SEGURANÇA ATIVO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: SatraColors.medium)),
                  ],
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
