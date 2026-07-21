import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/breez_service.dart';
import '../services/nfc_service.dart';
import '../theme/colors.dart';
import '../widgets/nfc_password_prompt.dart';

/// Fund-safety net for a failed/interrupted escape NFC write.
///
/// [BreezService.executeEscapeSweep] moves funds to a brand-new wallet
/// before the NFC write is attempted, and that new wallet's mnemonic is
/// saved as "pending" (see [BreezService.savePendingEscapeMnemonic]) right
/// before the write — so if the write times out or fails, those funds
/// aren't stranded with no way back. This screen reads that pending
/// mnemonic (if any), lets the user retry the write without repeating the
/// sweep itself (the funds have already moved — sweeping again would just
/// generate yet another wallet), and as a last resort lets them reveal and
/// copy the 12 words directly, the same blur/reveal pattern
/// [WalletBackupScreen] uses for the primary wallet's own phrase.
class PendingEscapeRecoveryScreen extends StatefulWidget {
  const PendingEscapeRecoveryScreen({super.key});

  @override
  State<PendingEscapeRecoveryScreen> createState() => _PendingEscapeRecoveryScreenState();
}

class _PendingEscapeRecoveryScreenState extends State<PendingEscapeRecoveryScreen> {
  late Future<String?> _pendingFuture;
  bool _writing = false;
  bool _revealed = false;
  NfcWriteResult? _lastResult;

  @override
  void initState() {
    super.initState();
    _pendingFuture = BreezService.instance.getPendingEscapeMnemonic();
  }

  Future<void> _retryWrite(String mnemonic) async {
    final password = await promptForNfcKeyPassword(context, title: 'Senha para gravar a chave');
    if (!mounted || password == null || password.isEmpty) return;

    setState(() {
      _writing = true;
      _lastResult = null;
    });

    final result = await NfcService.instance.writeRecoveryCredential(mnemonic, password: password);
    if (!mounted) return;

    if (result == NfcWriteResult.success) {
      await BreezService.instance.clearPendingEscapeMnemonic();
      if (!mounted) return;
      setState(() {
        _writing = false;
        _lastResult = result;
        _pendingFuture = Future.value(null);
      });
    } else {
      setState(() {
        _writing = false;
        _lastResult = result;
      });
    }
  }

  Future<void> _copyMnemonic(String mnemonic) async {
    await Clipboard.setData(ClipboardData(text: mnemonic));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Frase copiada para a área de transferência')),
    );
  }

  static String _resultLabel(NfcWriteResult result) => switch (result) {
        NfcWriteResult.success => 'Gravado com sucesso na chave física.',
        NfcWriteResult.unavailable => 'NFC indisponível ou desligado neste aparelho.',
        NfcWriteResult.writeNotSupportedOnPlatform => 'Este aparelho não permite gravar chaves NFC.',
        NfcWriteResult.tagNotWritable => 'A chave não aceitou a gravação (bloqueada ou incompatível).',
        NfcWriteResult.timedOut => 'Nenhuma chave foi detectada a tempo. Tente encostar novamente.',
        NfcWriteResult.verificationFailed =>
          'A gravação não pôde ser confirmada. Encoste a chave novamente e tente de novo.',
        NfcWriteResult.failed => 'Falha ao gravar. Tente novamente.',
      };

  Widget _buildHeader() {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back, color: SatraColors.navy),
          onPressed: () => Navigator.of(context).pop(),
        ),
        const Expanded(
          child: Text(
            'Gravação pendente',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: SatraColors.navy),
          ),
        ),
        const SizedBox(width: 48),
      ],
    );
  }

  Widget _buildNothingPending() {
    return Column(
      children: [
        const SizedBox(height: 12),
        _buildHeader(),
        const Spacer(),
        const Icon(Icons.check_circle_outline, size: 64, color: SatraColors.light),
        const SizedBox(height: 16),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'Nenhuma gravação pendente. Se você já passou por um escape e a chave física foi gravada com sucesso, não há nada para fazer aqui.',
            textAlign: TextAlign.center,
            style: TextStyle(color: SatraColors.medium, fontWeight: FontWeight.w600),
          ),
        ),
        const Spacer(flex: 2),
      ],
    );
  }

  Widget _buildPending(String mnemonic) {
    final words = mnemonic.split(RegExp(r'\s+'));
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      children: [
        _buildHeader(),
        const SizedBox(height: 12),
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
                  'Um escape recente moveu fundos para uma nova carteira, mas a gravação na chave física ainda não foi confirmada. Grave a chave assim que possível — até lá, essas 12 palavras são a única forma de acessar esse saldo.',
                  style: TextStyle(color: Color(0xFF7A1F1F), fontSize: 13, height: 1.3),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (_lastResult != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _resultLabel(_lastResult!),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _lastResult == NfcWriteResult.success ? const Color(0xFF3FBF6F) : const Color(0xFFD64545),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        SizedBox(
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _writing ? null : () => _retryWrite(mnemonic),
            icon: _writing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.nfc, color: Colors.white),
            label: Text(
              _writing ? 'Aguardando a chave...' : 'Tentar gravar novamente',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: SatraColors.navy,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
            ),
          ),
        ),
        const SizedBox(height: 32),
        const Divider(color: SatraColors.light),
        const SizedBox(height: 16),
        const Text(
          'ÚLTIMO RECURSO: VER A FRASE MANUALMENTE',
          style: TextStyle(color: SatraColors.medium, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5),
        ),
        const SizedBox(height: 8),
        const Text(
          'Se a chave física continuar falhando, anote essas 12 palavras em papel, em um local seguro. Quem tiver essas palavras acessa o saldo diretamente — nunca as fotografe ou envie por mensagem.',
          style: TextStyle(color: SatraColors.navy, fontSize: 13, height: 1.3),
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
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
              if (!_revealed)
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      color: Colors.white.withValues(alpha: 0.55),
                      alignment: Alignment.center,
                      child: OutlinedButton.icon(
                        onPressed: () => setState(() => _revealed = true),
                        icon: const Icon(Icons.visibility, color: SatraColors.navy),
                        label: const Text(
                          'Revelar',
                          style: TextStyle(color: SatraColors.navy, fontWeight: FontWeight.w600),
                        ),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.white,
                          side: const BorderSide(color: SatraColors.navy),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                        ),
                      ),
                    ),
                  ),
                )
              else
                Positioned(
                  top: 4,
                  right: 4,
                  child: IconButton(
                    icon: const Icon(Icons.visibility_off, color: SatraColors.medium),
                    tooltip: 'Ocultar frase',
                    onPressed: () => setState(() => _revealed = false),
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
        const SizedBox(height: 24),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SatraColors.background,
      body: SafeArea(
        child: FutureBuilder<String?>(
          future: _pendingFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return Column(
                children: [
                  const SizedBox(height: 12),
                  _buildHeader(),
                  const Expanded(child: Center(child: CircularProgressIndicator())),
                ],
              );
            }
            final mnemonic = snapshot.data;
            if (mnemonic == null || mnemonic.isEmpty) {
              return _buildNothingPending();
            }
            return _buildPending(mnemonic);
          },
        ),
      ),
    );
  }
}
