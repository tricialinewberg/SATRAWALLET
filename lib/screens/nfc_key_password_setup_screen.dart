import 'package:flutter/material.dart';

import '../services/breez_service.dart';
import '../services/nfc_credential_crypto.dart';
import '../services/nfc_key_password_service.dart';
import '../services/nfc_service.dart';
import '../theme/colors.dart';

/// Sets up the physical NFC recovery key: saves the password used to
/// encrypt it, generates a brand-new FIXED escape wallet, and writes that
/// wallet's mnemonic to the tag — the one and only time it's ever written.
///
/// This moved wallet creation and NFC writing here, out of the escape
/// handler itself, precisely so a real escape never needs to touch NFC at
/// all: it just sweeps funds (see `BreezService.executeEscapeSweep`) to
/// whatever escape wallet was already configured, calmly, ahead of time.
/// [NfcTransferScreen] (reading the key on a different device later) and
/// [PendingEscapeRecoveryScreen] (retrying THIS setup write if it fails)
/// are unaffected by this change.
class NfcKeyPasswordSetupScreen extends StatefulWidget {
  const NfcKeyPasswordSetupScreen({super.key});

  @override
  State<NfcKeyPasswordSetupScreen> createState() => _NfcKeyPasswordSetupScreenState();
}

class _NfcKeyPasswordSetupScreenState extends State<NfcKeyPasswordSetupScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  late Future<bool> _hasEscapeWalletFuture;
  bool _obscure = true;
  bool _saving = false;
  bool _writingToTag = false;
  NfcWriteResult? _writeResult;

  @override
  void initState() {
    super.initState();
    _hasEscapeWalletFuture = BreezService.instance.hasEscapeWallet();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<bool> _confirmReplaceIfNeeded() async {
    final alreadyHasWallet = await BreezService.instance.hasEscapeWallet();
    if (!alreadyHasWallet) return true;
    if (!mounted) return false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Substituir carteira de escape?'),
        content: const Text(
          'Você já tem uma carteira de escape configurada. Continuar cria uma NOVA '
          'carteira e regrava a chave física — qualquer saldo que a carteira anterior '
          'ainda tenha pode ficar inacessível se você não tiver feito backup dela antes. '
          'Essa ação não pode ser desfeita.',
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
    return confirmed == true;
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

    final proceed = await _confirmReplaceIfNeeded();
    if (!mounted || !proceed) return;

    setState(() {
      _saving = true;
      _writeResult = null;
    });

    try {
      await NfcKeyPasswordService.instance.setPassword(password);

      // Generated once, here, and persisted permanently — the escape
      // handler reads it straight from storage at sweep time and never
      // needs to touch this tag again. Saved as "pending" first so a
      // failed/unconfirmed write below doesn't leave this mnemonic
      // unrecoverable — see BreezService.savePendingEscapeMnemonic.
      final escapeMnemonic = await BreezService.instance.createEscapeWallet();
      await BreezService.instance.savePendingEscapeMnemonic(escapeMnemonic);

      if (!mounted) return;
      setState(() => _writingToTag = true);

      final result = await NfcService.instance.writeRecoveryCredential(escapeMnemonic, password: password);
      if (!mounted) return;

      if (result == NfcWriteResult.success) {
        await BreezService.instance.clearPendingEscapeMnemonic();
      }

      setState(() {
        _writeResult = result;
        _writingToTag = false;
        _hasEscapeWalletFuture = Future.value(true);
      });

      if (!mounted) return;
      if (result == NfcWriteResult.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Senha salva e chave física gravada com sucesso.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static String _resultLabel(NfcWriteResult result) => switch (result) {
        NfcWriteResult.success => 'Chave física gravada e confirmada com sucesso.',
        NfcWriteResult.unavailable => 'NFC indisponível ou desligado neste aparelho.',
        NfcWriteResult.writeNotSupportedOnPlatform => 'Este aparelho não permite gravar chaves NFC.',
        NfcWriteResult.tagNotWritable => 'A chave não aceitou a gravação (bloqueada ou incompatível).',
        NfcWriteResult.timedOut => 'Nenhuma chave foi detectada a tempo. Tente novamente.',
        NfcWriteResult.verificationFailed =>
          'A gravação não pôde ser confirmada. Tente novamente — a senha e a carteira já '
              'foram salvas, então "Concluir gravação pendente" no menu também funciona.',
        NfcWriteResult.failed => 'Falha ao gravar. Tente novamente pelo menu > Concluir gravação pendente.',
      };

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
                    'Chave física',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: SatraColors.navy),
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
            const SizedBox(height: 20),
            FutureBuilder<bool>(
              future: _hasEscapeWalletFuture,
              builder: (context, snapshot) {
                final hasWallet = snapshot.data ?? false;
                return Text(
                  hasWallet
                      ? 'Uma carteira de escape já está configurada. Salvar novamente cria uma '
                          'NOVA carteira e regrava a chave física.'
                      : 'Nenhuma carteira de escape configurada ainda — o modo de escape não vai '
                          'conseguir enviar saldo para a chave física até que uma seja criada aqui.',
                  style: const TextStyle(color: SatraColors.medium, fontSize: 13, height: 1.3),
                );
              },
            ),
            const SizedBox(height: 20),
            const Text(
              'Ao salvar, uma carteira nova e independente é criada e gravada (cifrada com a '
              'senha abaixo) na sua chave física. É essa mesma carteira que recebe o saldo toda '
              'vez que o modo de escape é ativado — a chave não precisa ser regravada depois. '
              'Guarde a senha em um lugar seguro: sem ela, não é possível ler a chave depois.',
              style: TextStyle(color: SatraColors.navy, fontSize: 13, height: 1.3),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _passwordController,
              obscureText: _obscure,
              style: const TextStyle(color: SatraColors.navy),
              decoration: InputDecoration(
                labelText: 'Senha da chave física',
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
            if (_writeResult != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _resultLabel(_writeResult!),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _writeResult == NfcWriteResult.success ? const Color(0xFF3FBF6F) : const Color(0xFFD64545),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
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
                    : const Text('Salvar e gravar chave física', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
            if (_writingToTag) ...[
              const SizedBox(height: 12),
              const Text(
                'Encoste a chave física agora para gravar...',
                textAlign: TextAlign.center,
                style: TextStyle(color: SatraColors.medium, fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
