import 'package:flutter/material.dart';

import '../services/inheritance_service.dart';
import '../services/nostr_service.dart';
import '../theme/colors.dart';
import '../widgets/glass_widgets.dart';

class InheritanceMessageTestScreen extends StatefulWidget {
  const InheritanceMessageTestScreen({super.key});

  @override
  State<InheritanceMessageTestScreen> createState() =>
      _InheritanceMessageTestScreenState();
}

class _InheritanceMessageTestScreenState
    extends State<InheritanceMessageTestScreen> {
  final _message = TextEditingController();
  InheritanceState? _state;
  bool _saving = false;
  bool _sending = false;
  String? _testingNpub;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final state = await InheritanceService.instance.getState();
    if (!mounted) return;
    _message.text = state.inheritanceMessage;
    setState(() => _state = state);
  }

  Future<bool> _saveMessage() async {
    setState(() => _saving = true);
    try {
      await InheritanceService.instance.setInheritanceMessage(_message.text);
      await _load();
      return true;
    } catch (error) {
      if (mounted) _notice('$error');
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _sendVerification(TrustedContact heir) async {
    setState(() => _testingNpub = heir.npub);
    try {
      final delivery =
          await InheritanceService.instance.sendHeirVerification(heir.npub);
      await _load();
      if (!mounted) return;
      if (!delivery.accepted) {
        _notice(
          delivery.error ?? 'Nenhum relay do herdeiro confirmou o recebimento.',
        );
        return;
      }
      await _askVerificationCode(heir);
    } catch (error) {
      if (mounted) _notice('$error');
    } finally {
      if (mounted) setState(() => _testingNpub = null);
    }
  }

  Future<void> _askVerificationCode(TrustedContact heir) async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: SatraColors.glass,
        title: const Text(
          'Confirmar herdeiro',
          style: TextStyle(color: SatraColors.glassBone),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Peça para ${heir.label} abrir o Nostr e informar o código de 6 dígitos recebido.',
              style: const TextStyle(color: SatraColors.glassBoneDim),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              maxLength: 6,
              autofocus: true,
              style: const TextStyle(color: SatraColors.glassBone),
              decoration: glassInputDecoration(labelText: 'Código recebido'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Depois'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: SatraColors.glassAqua,
              foregroundColor: SatraColors.glassVoid,
            ),
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (code == null || code.isEmpty) return;
    final verified =
        await InheritanceService.instance.verifyHeirCode(heir.npub, code);
    await _load();
    if (mounted) {
      _notice(verified
          ? 'Herdeiro verificado com sucesso.'
          : 'Código inválido ou expirado.');
    }
  }

  Future<void> _sendMessageTest() async {
    if (!await _saveMessage()) return;
    setState(() => _sending = true);
    try {
      final result =
          await InheritanceService.instance.sendInheritanceMessageTest();
      if (!mounted) return;
      final ok = result.delivered > 0;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: SatraColors.glass,
          icon: Icon(
            ok ? Icons.mark_email_read : Icons.cloud_off,
            color: ok ? SatraColors.glassAqua : SatraColors.error,
          ),
          title: Text(
            ok ? 'Teste aceito pela rede' : 'Entrega não confirmada',
            style: const TextStyle(color: SatraColors.glassBone),
          ),
          content: Text(
            '${result.delivered} de ${result.recipients} herdeiro(s) tiveram '
            'a mensagem aceita por pelo menos um relay.\n\n'
            'Peça ao herdeiro para conferir as mensagens no aplicativo Nostr. '
            'A confirmação do relay não comprova que a mensagem foi aberta.',
            style: const TextStyle(color: SatraColors.glassBoneDim, height: 1.45),
          ),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: SatraColors.glassAqua,
                foregroundColor: SatraColors.glassVoid,
              ),
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Entendi'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) _notice('$error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _notice(String text) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    return Scaffold(
      backgroundColor: SatraColors.glassVoid,
      body: state == null
          ? const Center(
              child:
                  CircularProgressIndicator(color: SatraColors.glassAqua))
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  GlassHeader(title: 'Mensagem e teste'),
                  const SizedBox(height: 18),
                  const _EncryptionInfo(),
                  const SizedBox(height: 20),
                  const Text(
                    'Mensagem para os herdeiros',
                    style: TextStyle(
                      color: SatraColors.glassBone,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _message,
                    minLines: 4,
                    maxLines: 8,
                    maxLength: 2000,
                    style: const TextStyle(color: SatraColors.glassBone),
                    decoration: glassInputDecoration(
                      hintText:
                          'Escreva uma orientação pessoal para seus herdeiros…',
                      alignLabelWithHint: true,
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : _saveMessage,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: SatraColors.glassAqua,
                        side: BorderSide(
                            color: SatraColors.glassAqua.withValues(alpha: 0.5)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: SatraColors.glassAqua))
                          : const Icon(Icons.save_outlined),
                      label: const Text('Salvar mensagem'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Verificação dos destinatários',
                    style: TextStyle(
                      color: SatraColors.glassBone,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'O herdeiro precisa confirmar uma vez o código recebido no '
                    'Nostr antes do teste completo.',
                    style:
                        TextStyle(color: SatraColors.glassBoneDim, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  if (state.heirs.isEmpty)
                    GlassCard(
                      child: Row(
                        children: [
                          const Icon(Icons.person_off_outlined,
                              color: SatraColors.glassBoneDim),
                          const SizedBox(width: 12),
                          Expanded(
                            child: const Text(
                              'Nenhum herdeiro cadastrado.',
                              style:
                                  TextStyle(color: SatraColors.glassBoneDim),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    for (final heir in state.heirs) ...[
                      _HeirVerificationTile(
                        heir: heir,
                        testing: _testingNpub == heir.npub,
                        disabled: _testingNpub != null && _testingNpub != heir.npub,
                        onSend: () => _sendVerification(heir),
                      ),
                      const SizedBox(height: 10),
                    ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _sending ? null : _sendMessageTest,
                      style: FilledButton.styleFrom(
                        backgroundColor: SatraColors.glassAqua,
                        foregroundColor: SatraColors.glassVoid,
                        disabledBackgroundColor:
                            SatraColors.glassAqua.withValues(alpha: 0.25),
                        disabledForegroundColor: SatraColors.glassBoneDim,
                        minimumSize: const Size.fromHeight(54),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: SatraColors.glassVoid))
                          : const Icon(Icons.send_outlined),
                      label: const Text('Enviar mensagem de teste'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Encryption callout rendered as a glass card with an aqua-tinted
/// security chip — the same "this is encrypted end-to-end" promise,
/// now reading as light through the tinted glass rather than a navy slab.
class _EncryptionInfo extends StatelessWidget {
  const _EncryptionInfo();

  @override
  Widget build(BuildContext context) => GlassCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const GlassIconChip(
              icon: Icons.enhanced_encryption_outlined,
              accent: SatraColors.glassAqua,
              size: 40,
              iconSize: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: const Text(
                'O teste envia somente esta mensagem, criptografada para o '
                'npub do herdeiro com NIP-17/NIP-59. Seed, saldo e senha não '
                'fazem parte do teste.',
                style: TextStyle(color: SatraColors.glassBone, height: 1.45),
              ),
            ),
          ],
        ),
      );
}

/// A glass card showing a single heir's verification status. The leading
/// avatar flips from frost (pending) to aqua (verified) — the same light
/// metaphor as everywhere else in the inheritance flow.
class _HeirVerificationTile extends StatelessWidget {
  const _HeirVerificationTile({
    required this.heir,
    required this.testing,
    required this.disabled,
    required this.onSend,
  });

  final TrustedContact heir;
  final bool testing;
  final bool disabled;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final verified = heir.verifiedAt != null;
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (verified ? SatraColors.glassAqua : SatraColors.glassFrost)
                  .withValues(alpha: verified ? 0.18 : 0.5),
              shape: BoxShape.circle,
              border: Border.all(
                color: verified
                    ? SatraColors.glassAqua.withValues(alpha: 0.4)
                    : SatraColors.glassFrost,
              ),
            ),
            child: Icon(
              verified ? Icons.verified : Icons.person_outline,
              color: verified ? SatraColors.glassAqua : SatraColors.glassBoneDim,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  heir.label,
                  style: const TextStyle(
                    color: SatraColors.glassBone,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                Text(
                  verified
                      ? 'Destino Nostr verificado'
                      : 'Aguardando verificação',
                  style: const TextStyle(
                      color: SatraColors.glassBoneDim, fontSize: 12),
                ),
              ],
            ),
          ),
          if (verified)
            const Icon(Icons.check, color: SatraColors.glassAqua, size: 20)
          else if (testing)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: SatraColors.glassAqua),
            )
          else
            TextButton(
              onPressed: disabled ? null : onSend,
              style: TextButton.styleFrom(
                foregroundColor: SatraColors.glassAqua,
                disabledForegroundColor: SatraColors.glassBoneDim,
              ),
              child: const Text('Enviar código'),
            ),
        ],
      ),
    );
  }
}
