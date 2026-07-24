import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/colors.dart';

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  static const _contributors = [
    ('Trícia Linewberg', 'https://github.com/tricialinewberg/'),
    ('Gio Gardinali', 'https://github.com/GioGardinali'),
    ('Raios Gama', 'https://github.com/raiosgama'),
  ];

  Future<void> _openLink(BuildContext context, String link) async {
    final opened = await launchUrl(
      Uri.parse(link),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível abrir o GitHub neste aparelho.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SatraColors.background,
      appBar: AppBar(
        title: const Text('Suporte e projeto'),
        backgroundColor: SatraColors.background,
        foregroundColor: SatraColors.navy,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [SatraColors.navy, SatraColors.medium],
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.bolt, color: Colors.white, size: 38),
                SizedBox(height: 14),
                Text(
                  'Satra Wallet',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 27,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Uma carteira construída para unir autonomia, privacidade '
                  'e segurança em momentos que realmente importam.',
                  style: TextStyle(
                    color: Colors.white70,
                    height: 1.45,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'UM PROJETO ABERTO',
            style: TextStyle(
              color: SatraColors.medium,
              fontSize: 12,
              letterSpacing: .8,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'A Satra é open source: o código pode ser estudado, auditado e '
            'melhorado pela comunidade. Não compartilhe PIN, senha ou frase '
            'de recuperação ao pedir ajuda — ninguém da equipe precisa desses '
            'dados para oferecer suporte.',
            style: TextStyle(color: SatraColors.navy, height: 1.5),
          ),
          const SizedBox(height: 24),
          const Text(
            'Equipe e contato',
            style: TextStyle(
              color: SatraColors.navy,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          for (final contributor in _contributors)
            Card(
              color: Colors.white,
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                side: const BorderSide(color: SatraColors.light),
                borderRadius: BorderRadius.circular(16),
              ),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: SatraColors.navy,
                  child: Icon(Icons.code, color: Colors.white),
                ),
                title: Text(
                  contributor.$1,
                  style: const TextStyle(
                    color: SatraColors.navy,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  contributor.$2,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(
                  Icons.open_in_new,
                  color: SatraColors.medium,
                ),
                onTap: () => _openLink(context, contributor.$2),
              ),
            ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: SatraColors.warningBg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.shield_outlined, color: SatraColors.warningDark),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Antes de atualizar ou reinstalar o aplicativo, confirme '
                    'que sua frase de recuperação está guardada em segurança.',
                    style: TextStyle(
                      color: SatraColors.warningDark,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
