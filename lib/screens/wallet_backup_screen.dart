import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../routes.dart';
import '../services/breez_service.dart';
import '../theme/colors.dart';

/// "Traga sua carteira": view/copy the current wallet's 12-word recovery
/// phrase, or paste an existing one to replace the current wallet with it.
/// Deliberately simple — functional, not polished.
class WalletBackupScreen extends StatefulWidget {
  const WalletBackupScreen({super.key});

  @override
  State<WalletBackupScreen> createState() => _WalletBackupScreenState();
}

class _WalletBackupScreenState extends State<WalletBackupScreen> {
  late final Future<String?> _mnemonicFuture;
  final _restoreController = TextEditingController();
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    _mnemonicFuture = BreezService.instance.getMnemonic();
  }

  @override
  void dispose() {
    _restoreController.dispose();
    super.dispose();
  }

  Future<void> _copyMnemonic(String mnemonic) async {
    await Clipboard.setData(ClipboardData(text: mnemonic));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Frase copiada para a área de transferência')),
    );
  }

  Future<void> _restore() async {
    final pasted = _restoreController.text.trim();
    if (pasted.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length < 12) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cole uma frase de recuperação com 12 palavras')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Substituir carteira atual?'),
        content: const Text(
          'Isso vai desconectar a carteira atual e reconectar usando a frase '
          'que você colou. Essa ação não pode ser desfeita — garanta que a '
          'carteira atual já está salva em algum lugar antes de continuar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Substituir'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _restoring = true);
    try {
      await BreezService.instance.restoreFromMnemonic(pasted);
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(
        SatraRoutes.walletHome,
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível restaurar: $e')),
      );
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    'Traga sua carteira',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: SatraColors.navy),
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              'SUA FRASE DE RECUPERAÇÃO',
              style: TextStyle(color: SatraColors.medium, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFDECEC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFF3B9B9)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_rounded, color: Color(0xFFD64545), size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Quem tiver essas 12 palavras tem acesso total ao seu saldo. '
                      'Nunca fotografe, envie por mensagem ou mostre pra ninguém.',
                      style: TextStyle(color: Color(0xFF7A1F1F), fontSize: 13, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FutureBuilder<String?>(
              future: _mnemonicFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final mnemonic = snapshot.data;
                if (mnemonic == null || mnemonic.isEmpty) {
                  return const Text('Nenhuma carteira ativa ainda.');
                }
                final words = mnemonic.split(RegExp(r'\s+'));
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: SatraColors.light),
                      ),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        children: [
                          for (var i = 0; i < words.length; i++)
                            SizedBox(
                              width: 130,
                              child: Text(
                                '${i + 1}. ${words[i]}',
                                style: const TextStyle(color: SatraColors.navy, fontWeight: FontWeight.w600),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => _copyMnemonic(mnemonic),
                      icon: const Icon(Icons.copy_outlined, color: SatraColors.navy),
                      label: const Text('Copiar frase', style: TextStyle(color: SatraColors.navy, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: SatraColors.navy),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 32),
            const Divider(color: SatraColors.light),
            const SizedBox(height: 16),
            const Text(
              'RESTAURAR DE OUTRA FRASE',
              style: TextStyle(color: SatraColors.medium, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5),
            ),
            const SizedBox(height: 8),
            const Text(
              'Cole uma frase de 12 palavras de outra carteira Satra para substituir a carteira atual neste celular.',
              style: TextStyle(color: SatraColors.navy, fontSize: 13, height: 1.3),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _restoreController,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'palavra1 palavra2 palavra3 ...',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: SatraColors.light),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _restoring ? null : _restore,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD64545),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                ),
                child: _restoring
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Substituir carteira', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
