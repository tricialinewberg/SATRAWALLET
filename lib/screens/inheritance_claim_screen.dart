import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nostr/nostr.dart' show Bech32Entity, Nip19Prefix;

import '../services/nfc_credential_crypto.dart';
import '../services/nostr_service.dart';
import '../theme/colors.dart';
import '../widgets/glass_widgets.dart';

/// "Decifrar herança": independent screen used by an heir to recover the
/// wallet's recovery phrase from the encrypted envelope the wallet owner
/// pre-published to Nostr (see `InheritanceService._publishInheritanceVaults`).
///
/// This screen is intentionally decoupled from everything else in the app —
/// it does NOT touch `BreezService`, `NostrService`, secure storage, or any
/// wallet state. The heir pastes the envelope JSON (which they obtained
/// from their own Nostr client after the owner's heartbeat went silent)
/// and the release password (shared out-of-band in life, e.g. on a sealed
/// card). Decryption happens purely in-memory via [NfcCredentialCrypto],
/// the same Argon2id + AES-GCM scheme used for the physical NFC recovery
/// key, so the security properties are identical.
///
/// Because this screen needs no wallet connection, it works for an heir
/// who installed the Satra app on a fresh phone solely to decrypt an
/// inheritance envelope — even if the owner's own phone is destroyed or
/// never opens again. That is the property that makes the inheritance
/// feature real and honest: the owner's death can't prevent recovery.
///
/// Visually it lives in the same "azul vidro" space as the rest of the
/// inheritance screens — the heir's recovery moment is part of the same
/// language the owner configured, not a foreign surface.
class InheritanceClaimScreen extends StatefulWidget {
  const InheritanceClaimScreen({super.key});

  @override
  State<InheritanceClaimScreen> createState() => _InheritanceClaimScreenState();
}

class _InheritanceClaimScreenState extends State<InheritanceClaimScreen> {
  final _envelopeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _ownerNpubController = TextEditingController();
  bool _obscurePassword = true;
  bool _decrypting = false;
  bool _fetching = false;
  bool _mnemonicRevealed = false;
  String? _decryptedMnemonic;
  String? _error;

  @override
  void dispose() {
    _envelopeController.dispose();
    _passwordController.dispose();
    _ownerNpubController.dispose();
    super.dispose();
  }

  Future<void> _fetchFromNostr() async {
    final npub = _ownerNpubController.text.trim();
    if (npub.isEmpty) {
      setState(() => _error = 'Digite o npub da titular da carteira.');
      return;
    }
    String ownerHex;
    try {
      final decoded = Bech32Entity.decode(payload: npub);
      if (decoded.prefix != Nip19Prefix.npub) {
        throw const FormatException('not an npub');
      }
      ownerHex = decoded.data;
    } catch (_) {
      setState(() => _error = 'npub inválido. Confira os caracteres.');
      return;
    }

    setState(() {
      _fetching = true;
      _error = null;
    });

    try {
      final envelope =
          await NostrService.instance.fetchInheritanceVault(ownerHex);
      if (!mounted) return;
      if (envelope == null || envelope.isEmpty) {
        setState(
            () => _error = 'Nenhum cofre encontrado nos relays para este npub. '
                'Verifique se o npub está correto ou se a titular já ativou a herança.');
      } else {
        _envelopeController.text = envelope;
        setState(() => _error = null);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Envelope encontrado no Nostr.')),
        );
      }
    } catch (e) {
      setState(() => _error = 'Erro ao buscar no Nostr: $e');
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  Future<void> _decrypt() async {
    final envelope = _envelopeController.text.trim();
    final password = _passwordController.text;

    if (envelope.isEmpty) {
      setState(() => _error = 'Cole o envelope cifrado recebido via Nostr.');
      return;
    }
    if (password.isEmpty) {
      setState(() =>
          _error = 'Digite a senha de liberação combinada com o titular.');
      return;
    }

    setState(() {
      _decrypting = true;
      _error = null;
      _decryptedMnemonic = null;
      _mnemonicRevealed = false;
    });

    try {
      final mnemonic = await NfcCredentialCrypto.decrypt(
        envelopeJson: envelope,
        password: password,
      );
      setState(() => _decryptedMnemonic = mnemonic);
    } on NfcCredentialException {
      setState(() => _error =
          'Não foi possível decifrar. Verifique a senha e o envelope.');
    } catch (e) {
      setState(() => _error = 'Erro: $e');
    } finally {
      if (mounted) setState(() => _decrypting = false);
    }
  }

  Future<void> _copyMnemonic() async {
    final mnemonic = _decryptedMnemonic;
    if (mnemonic == null) return;
    await Clipboard.setData(ClipboardData(text: mnemonic));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Frase copiada para a área de transferência')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mnemonic = _decryptedMnemonic;
    final maskedMnemonic = mnemonic == null
        ? null
        : List<String>.filled(
            mnemonic.split(RegExp(r'\s+')).length,
            '••••',
          ).join('  ');
    return Scaffold(
      backgroundColor: SatraColors.glassVoid,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GlassHeader(title: 'Decifrar herança'),
              const SizedBox(height: 18),
              _hero(),
              const SizedBox(height: 20),
              const Text(
                'Recuperação independente',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: SatraColors.glassBone,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Use esta tela se você foi indicado como herdeiro de uma Satra '
                'Wallet e já recebeu o envelope cifrado via Nostr. Cole o '
                'envelope abaixo e digite a senha combinada em vida com o '
                'titular para revelar a frase de recuperação da carteira.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: SatraColors.glassBoneDim,
                ),
              ),
              const SizedBox(height: 20),
              // Optional: fetch the envelope directly from Nostr if the heir
              // has their own Satra wallet configured (so we can derive their
              // Nostr keys and decrypt the NIP-44 layer). If the heir has no
              // wallet (fresh install via 589301=), they skip this and paste
              // the envelope they got from their DMs in Damus/Primal.
              ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: SatraColors.glassFrost),
                ),
                collapsedShape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: SatraColors.glassFrost),
                ),
                backgroundColor: SatraColors.glass,
                collapsedBackgroundColor: SatraColors.glass,
                iconColor: SatraColors.glassBoneDim,
                collapsedIconColor: SatraColors.glassBoneDim,
                title: const Text(
                  'Buscar no Nostr (opcional)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: SatraColors.glassBone,
                  ),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Se você tem sua própria Satra Wallet configurada e a '
                          'titular cadastrou seu npub como herdeiro, digite o npub '
                          'dela para buscar o envelope automaticamente nos relays.',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: SatraColors.glassBoneDim,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _ownerNpubController,
                                autocorrect: false,
                                enableSuggestions: false,
                                style: const TextStyle(
                                    color: SatraColors.glassBone,
                                    fontFamily: 'monospace',
                                    fontSize: 12),
                                decoration: glassInputDecoration(
                                  labelText: 'npub da titular',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: SatraColors.glassAqua,
                                foregroundColor: SatraColors.glassVoid,
                                disabledBackgroundColor:
                                    SatraColors.glassAqua.withValues(alpha: 0.25),
                                disabledForegroundColor:
                                    SatraColors.glassBoneDim,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: _fetching ? null : _fetchFromNostr,
                              child: _fetching
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: SatraColors.glassVoid,
                                      ),
                                    )
                                  : const Text('Buscar'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _envelopeController,
                minLines: 4,
                maxLines: 8,
                autocorrect: false,
                enableSuggestions: false,
                style: const TextStyle(
                    color: SatraColors.glassBone,
                    fontFamily: 'monospace',
                    fontSize: 12),
                decoration: glassInputDecoration(
                  labelText: 'Envelope cifrado',
                  hintText: '{"version":1,"walletType":"breez-spark",...}',
                  alignLabelWithHint: true,
                  hintStyle: const TextStyle(
                      color: SatraColors.glassBoneDim, fontSize: 12),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                style: const TextStyle(color: SatraColors.glassBone),
                decoration: glassInputDecoration(
                  labelText: 'Senha de liberação',
                  alignLabelWithHint: true,
                  prefixIcon: const Icon(Icons.lock_outline,
                      color: SatraColors.glassBoneDim),
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword
                        ? 'Mostrar senha'
                        : 'Ocultar senha',
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: SatraColors.glassBoneDim,
                    ),
                    onPressed: () => setState(
                        () => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: SatraColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: SatraColors.error.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          size: 18, color: SatraColors.error),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: SatraColors.error,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: SatraColors.glassAqua,
                    foregroundColor: SatraColors.glassVoid,
                    disabledBackgroundColor:
                        SatraColors.glassAqua.withValues(alpha: 0.25),
                    disabledForegroundColor: SatraColors.glassBoneDim,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _decrypting ? null : _decrypt,
                  child: _decrypting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: SatraColors.glassVoid,
                          ),
                        )
                      : const Text('Decifrar'),
                ),
              ),
              if (_decryptedMnemonic != null) ...[
                const SizedBox(height: 24),
                _mnemonicCard(mnemonic!, maskedMnemonic ?? ''),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Glass hero — same luminous panel style as the rest of the inheritance
  /// flow. The heir's first impression here is the same visual language
  /// the owner configured in, which makes the recovery moment feel
  /// continuous with the setup moment rather than a separate tool.
  Widget _hero() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: glassHeroGradient,
        border: Border.all(color: SatraColors.glassFrost, width: 1),
        boxShadow: [
          BoxShadow(
            color: SatraColors.navy.withValues(alpha: 0.10),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const GlassIconChip(
            icon: Icons.lock_open_outlined,
            accent: SatraColors.glassAqua,
            size: 52,
            iconSize: 28,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Acesso de herdeiro',
                  style: TextStyle(
                    color: SatraColors.glassBone,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Decifre o envelope recebido via Nostr.',
                  style: TextStyle(
                    color: SatraColors.glassBoneDim,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Revealed recovery phrase card. Renders as a glass card with an aqua
  /// accent (the "decryption succeeded" light) — never the old success-
  /// green border on white, which read as a different app's surface.
  /// The warning callout at the bottom uses a translucent amber tint so
  /// the caution survives the dark background.
  Widget _mnemonicCard(String mnemonic, String masked) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const GlassIconChip(
                icon: Icons.lock_open_outlined,
                accent: SatraColors.glassAqua,
                size: 32,
                iconSize: 18,
              ),
              const SizedBox(width: 10),
              const Text(
                'Frase de recuperação',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: SatraColors.glassBone,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(
                  _mnemonicRevealed
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                  color: SatraColors.glassBoneDim,
                ),
                tooltip: _mnemonicRevealed ? 'Ocultar frase' : 'Revelar frase',
                onPressed: () =>
                    setState(() => _mnemonicRevealed = !_mnemonicRevealed),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _mnemonicRevealed ? mnemonic : masked,
            style: const TextStyle(
              color: SatraColors.glassBone,
              fontFamily: 'monospace',
              fontSize: 15,
              height: 1.6,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          if (_mnemonicRevealed)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: SatraColors.glassAqua,
                ),
                icon: const Icon(Icons.copy_outlined, size: 18),
                label: const Text('Copiar frase'),
                onPressed: _copyMnemonic,
              ),
            ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: SatraColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: SatraColors.warning.withValues(alpha: 0.4)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 16, color: SatraColors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Guarde esta frase com segurança. Restaure a carteira '
                    'em um app Satra novo usando "Traga sua carteira" → '
                    '"Restaurar com seed".',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: SatraColors.warning.withValues(alpha: 0.95),
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
