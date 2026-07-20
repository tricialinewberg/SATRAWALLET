import 'package:flutter/material.dart';

import '../routes.dart';
import '../theme/colors.dart';
import 'side_menu_screen.dart';

/// Main wallet screen (UI only — no Breez/Nostr wiring yet).
/// Placeholder balance mirrors the Figma reference; real data comes later
/// from services/breez_service.dart.
class WalletHomeScreen extends StatefulWidget {
  const WalletHomeScreen({super.key});

  @override
  State<WalletHomeScreen> createState() => _WalletHomeScreenState();
}

class _WalletHomeScreenState extends State<WalletHomeScreen> {
  bool _balanceHidden = false;

  static const _placeholderSats = '128.500';
  static const _placeholderFiat = 'R\$ 642,50';

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
    Navigator.of(context).pushNamedAndRemoveUntil(
      SatraRoutes.escapeConfirmation,
      (route) => false,
    );
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
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: _balanceHidden ? '*****' : _placeholderSats,
                        style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: SatraColors.navy),
                      ),
                      const TextSpan(text: '  Sats', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: SatraColors.navy)),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '≈ ${_balanceHidden ? 'R\$ ****' : _placeholderFiat}',
                  style: const TextStyle(color: SatraColors.medium, fontWeight: FontWeight.w600),
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
                          onPressed: () {},
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
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.history, color: SatraColors.light, size: 32),
                        SizedBox(height: 10),
                        Text('Nenhuma transação ainda', style: TextStyle(color: Colors.black54)),
                      ],
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
/// drag to the end (not a tap) so it can't be triggered by accident.
class _EscapeSlider extends StatefulWidget {
  final VoidCallback onConfirmed;

  const _EscapeSlider({required this.onConfirmed});

  @override
  State<_EscapeSlider> createState() => _EscapeSliderState();
}

class _EscapeSliderState extends State<_EscapeSlider> {
  double _dragFraction = 0;
  static const _trackHeight = 56.0;
  static const _handleSize = 44.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxDrag = constraints.maxWidth - _handleSize - 8;
        return Container(
          height: _trackHeight,
          decoration: BoxDecoration(
            color: Color.lerp(Colors.white, SatraColors.navy, _dragFraction),
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
                    color: Color.lerp(SatraColors.navy, Colors.white, _dragFraction),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(4),
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      _dragFraction = ((_dragFraction * maxDrag) + details.delta.dx) / maxDrag;
                      _dragFraction = _dragFraction.clamp(0.0, 1.0);
                    });
                  },
                  onHorizontalDragEnd: (details) {
                    if (_dragFraction > 0.85) {
                      widget.onConfirmed();
                    }
                    setState(() => _dragFraction = 0);
                  },
                  child: Transform.translate(
                    offset: Offset(_dragFraction * maxDrag, 0),
                    child: Container(
                      width: _handleSize,
                      height: _handleSize,
                      decoration: const BoxDecoration(color: SatraColors.navy, shape: BoxShape.circle),
                      child: const Icon(Icons.arrow_forward, color: Colors.white, size: 20),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
