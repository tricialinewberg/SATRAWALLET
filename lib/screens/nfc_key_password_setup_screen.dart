import 'package:flutter/material.dart';

import '../services/nfc_credential_crypto.dart';
import '../services/nfc_key_password_service.dart';
import '../theme/colors.dart';

/// Lets the user set (or change) the password used to encrypt whatever
/// gets written to the physical NFC recovery key.
///
/// Must be configured ahead of time for the escape flow's automatic write
/// to work at all — that write can't interactively prompt for a password,
/// since the whole point of the escape gesture is that nothing further
/// needs to happen after it (see
/// `WalletHomeScreen._sweepToNewWalletAndWriteTag`). Screens that write or
/// read the key interactively (`NfcTransferScreen`,
/// `PendingEscapeRecoveryScreen`) still prompt for a password each time,
/// independent of whatever is saved here.
class NfcKeyPasswordSetupScreen extends StatefulWidget {
  const NfcKeyPasswordSetupScreen({super.key});

  @override
  State<NfcKeyPasswordSetupScreen> createState() => _NfcKeyPasswordSetupScreenState();
}

class _NfcKeyPasswordSetupScreenState extends State<NfcKeyPasswordSetupScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  late Future<bool> _hasPasswordFuture;
  bool _obscure = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _hasPasswordFuture = NfcKeyPasswordService.instance.hasPassword();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    if (password.length < NfcCredentialCrypto.minPasswordLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'A senha precisa ter pelo menos ${NfcCredentialCrypto.minPasswordLength} caracteres.',
          ),
        ),
      );
      return;
    }
    if (password != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('As senhas não coincidem.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await NfcKeyPasswordService.instance.setPassword(password);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Senha da chave física salva.')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
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
                    'Senha da chave física',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: SatraColors.navy),
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
            const SizedBox(height: 20),
            FutureBuilder<bool>(
              future: _hasPasswordFuture,
              builder: (context, snapshot) {
                final hasPassword = snapshot.data ?? false;
                return Text(
                  hasPassword
                      ? 'Uma senha já está configurada. Salvar uma nova substitui a anterior.'
                      : 'Nenhuma senha configurada ainda — o escape não vai conseguir gravar a chave automaticamente até que uma seja definida.',
                  style: const TextStyle(color: SatraColors.medium, fontSize: 13, height: 1.3),
                );
              },
            ),
            const SizedBox(height: 20),
            const Text(
              'Essa senha protege o conteúdo gravado na chave física caso ela seja perdida ou roubada. '
              'Guarde-a em um lugar seguro — sem ela, não é possível ler a chave depois.',
              style: TextStyle(color: SatraColors.navy, fontSize: 13, height: 1.3),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _passwordController,
              obscureText: _obscure,
              style: const TextStyle(color: SatraColors.navy),
              decoration: InputDecoration(
                labelText: 'Nova senha',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: SatraColors.medium),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmController,
              obscureText: _obscure,
              style: const TextStyle(color: SatraColors.navy),
              decoration: InputDecoration(
                labelText: 'Confirmar senha',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: SatraColors.navy,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Salvar senha', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
