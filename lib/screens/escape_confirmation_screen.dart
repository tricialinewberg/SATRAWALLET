import 'package:flutter/material.dart';

import '../routes.dart';
import '../theme/colors.dart';

/// Shown right after the escape gesture completes. By the time this screen
/// is on screen, [WalletHomeScreen] has already fired off the balance send
/// and the NIP-17 alert to trusted contacts in the background — this
/// screen itself is purely the confirmation UI. Per the product spec, the
/// app quietly returns to looking like a plain calculator a few seconds
/// after this screen is shown.
class EscapeConfirmationScreen extends StatefulWidget {
  const EscapeConfirmationScreen({super.key});

  @override
  State<EscapeConfirmationScreen> createState() => _EscapeConfirmationScreenState();
}

class _EscapeConfirmationScreenState extends State<EscapeConfirmationScreen>
    with SingleTickerProviderStateMixin {
  static const _entranceDuration = Duration(milliseconds: 380);

  late final AnimationController _entranceController;
  late final Animation<double> _entranceOpacity;
  late final Animation<double> _entranceScale;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(vsync: this, duration: _entranceDuration);
    final curved = CurvedAnimation(parent: _entranceController, curve: Curves.easeOut);
    _entranceOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(curved);
    _entranceScale = Tween<double>(begin: 0.8, end: 1.0).animate(curved);
    _entranceController.forward();

    Future.delayed(const Duration(seconds: 4), () {
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(
        SatraRoutes.calculator,
        (route) => false,
      );
    });
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
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
              FadeTransition(
                opacity: _entranceOpacity,
                child: ScaleTransition(
                  scale: _entranceScale,
                  child: Column(
                    children: [
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
                    ],
                  ),
                ),
              ),
              const Spacer(flex: 4),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: SatraColors.light),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(Icons.shield_outlined, size: 16, color: SatraColors.medium),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'PROTOCOLO DE SEGURANÇA ATIVO',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: SatraColors.medium),
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
