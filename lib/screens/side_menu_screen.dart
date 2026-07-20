import 'package:flutter/material.dart';

import '../routes.dart';
import '../theme/colors.dart';

/// Right-side drawer opened from [WalletHomeScreen]'s hamburger icon.
/// Only "Traga sua carteira" (NFC restore) and "Trocar PIN" are wired —
/// the rest are placeholders until their screens/services exist.
class SideMenuScreen extends StatelessWidget {
  const SideMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: SatraColors.navy,
      width: 300,
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: SatraColors.medium,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'LIGHTNING ADDRESS',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11, letterSpacing: 0.5),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'alice@satra.io',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.copy_outlined, color: Colors.white70, size: 18),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Divider(color: Colors.white24, height: 1),
            _MenuTile(
              icon: Icons.credit_card,
              label: 'Traga sua carteira',
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).pushNamed(SatraRoutes.nfcTransfer);
              },
            ),
            _MenuTile(icon: Icons.people_outline, label: 'Rede de confiança', onTap: () => Navigator.of(context).pop()),
            _MenuTile(
              icon: Icons.lock_outline,
              label: 'Trocar PIN',
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).pushNamed(SatraRoutes.pinSetup);
              },
            ),
            _MenuTile(icon: Icons.headset_mic_outlined, label: 'Support', onTap: () => Navigator.of(context).pop()),
            _MenuTile(icon: Icons.info_outline, label: 'Sobre o app', onTap: () => Navigator.of(context).pop()),
            _MenuTile(icon: Icons.settings_outlined, label: 'Configurações', onTap: () => Navigator.of(context).pop()),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.bolt, color: Colors.white54, size: 18),
                  const SizedBox(width: 6),
                  Text('SATRA', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontWeight: FontWeight.bold, letterSpacing: 1)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MenuTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Colors.white, size: 22),
      title: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
      onTap: onTap,
    );
  }
}
