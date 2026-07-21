import 'package:flutter/material.dart';

import '../routes.dart';
import '../services/breez_service.dart';
import '../services/nfc_credential_crypto.dart';
import '../services/nfc_service.dart';
import '../theme/colors.dart';
import '../widgets/nfc_password_prompt.dart';

/// Recovery screen for a physical NFC key: listens for a tag, and on
/// "Transferir" decrypts the credential envelope on it (prompting for its
/// password) and replaces the current wallet with the one it holds.
class NfcTransferScreen extends StatefulWidget {
  const NfcTransferScreen({super.key});

  @override
  State<NfcTransferScreen> createState() => _NfcTransferScreenState();
}

class _NfcTransferScreenState extends State<NfcTransferScreen> {
  bool _unavailable = false;
  String? _detectedEnvelope;
  bool _transferring = false;

  @override
  void initState() {
    super.initState();
    _startListening();
  }

  @override
  void dispose() {
    NfcService.instance.stopListening();
    super.dispose();
  }

  Future<void> _startListening() async {
    final available = await NfcService.instance.isAvailable();
    if (!available) {
      if (mounted) setState(() => _unavailable = true);
      return;
    }

    await NfcService.instance.startListeningForKey(
      onCredentialDetected: (envelopeJson) {
        if (!mounted) return;
        setState(() => _detectedEnvelope = envelopeJson);
      },
      onError: () {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível ler essa chave. Tente encostar novamente.')),
        );
      },
    );
  }

  Future<void> _transfer() async {
    final envelope = _detectedEnvelope;
    if (envelope == null) return;

    final password = await promptForNfcKeyPassword(context);
    if (!mounted || password == null || password.isEmpty) return;

    setState(() => _transferring = true);
    try {
      // Decrypted only in memory, passed straight into restoreFromMnemonic
      // below — never logged, stored, or shown anywhere.
      final mnemonic = await NfcCredentialCrypto.decrypt(envelopeJson: envelope, password: password);
      await BreezService.instance.restoreFromMnemonic(mnemonic);
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(
        SatraRoutes.walletHome,
        (route) => false,
      );
    } on NfcCredentialException {
      // Deliberately generic — see NfcCredentialCrypto.decrypt: a wrong
      // password and a tampered/corrupted tag must be indistinguishable.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Senha incorreta, ou a chave está corrompida.')),
      );
      setState(() => _transferring = false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível transferir: $e')),
      );
      setState(() => _transferring = false);
    }
  }

  void _cancel() {
    NfcService.instance.stopListening();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SatraColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: _unavailable ? _buildUnavailable() : _buildScanOrDetected(),
        ),
      ),
    );
  }

  Widget _buildUnavailable() {
    return Column(
      children: [
        const Spacer(flex: 3),
        const Icon(Icons.nfc, size: 64, color: SatraColors.light),
        const SizedBox(height: 20),
        const Text(
          'Este aparelho não tem NFC',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: SatraColors.navy),
        ),
        const SizedBox(height: 8),
        const Text(
          'Não é possível ler uma chave física neste aparelho.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: SatraColors.medium, fontWeight: FontWeight.w600),
        ),
        const Spacer(flex: 4),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: SatraColors.navy,
              side: const BorderSide(color: SatraColors.light),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            ),
            child: const Text('Voltar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildScanOrDetected() {
    final detected = _detectedEnvelope != null;
    return Column(
      children: [
        const Spacer(flex: 2),
        Container(
          width: 160,
          height: 160,
          decoration: BoxDecoration(color: SatraColors.light.withValues(alpha: 0.35), shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(color: SatraColors.light.withValues(alpha: 0.7), shape: BoxShape.circle),
            alignment: Alignment.center,
            child: const Icon(Icons.nfc, size: 44, color: SatraColors.navy),
          ),
        ),
        const SizedBox(height: 28),
        Text(
          detected ? 'Chave física detectada' : 'Aproxime a chave física',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: SatraColors.navy),
        ),
        const SizedBox(height: 8),
        Text(
          detected
              ? 'Encontramos uma carteira salva nessa chave.'
              : 'Encoste o celular na chave para continuar.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: SatraColors.medium, fontWeight: FontWeight.w600),
        ),
        const Spacer(flex: 2),
        if (detected) ...[
          const Text(
            'Deseja transferir para esta carteira?',
            style: TextStyle(color: SatraColors.medium, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
        ],
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: detected && !_transferring ? _transfer : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: SatraColors.navy,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            ),
            child: _transferring
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Transferir', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: OutlinedButton(
            onPressed: _transferring ? null : _cancel,
            style: OutlinedButton.styleFrom(
              foregroundColor: SatraColors.navy,
              side: const BorderSide(color: SatraColors.light),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            ),
            child: const Text('Cancelar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
