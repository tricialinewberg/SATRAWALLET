import 'package:flutter/material.dart';

import '../services/nostr_service.dart';
import '../theme/colors.dart';

/// "Rede de confiança": add/remove the npubs that receive the NIP-17
/// escape alert. Deliberately simple, matching [WalletBackupScreen]'s style.
class TrustedContactsScreen extends StatefulWidget {
  const TrustedContactsScreen({super.key});

  @override
  State<TrustedContactsScreen> createState() => _TrustedContactsScreenState();
}

class _TrustedContactsScreenState extends State<TrustedContactsScreen> {
  List<TrustedContact>? _contacts;
  bool _adding = false;
  String? _testingNpub;
  final _labelController = TextEditingController();
  final _npubController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  @override
  void dispose() {
    _labelController.dispose();
    _npubController.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    final contacts = await NostrService.instance.getContacts();
    if (!mounted) return;
    setState(() => _contacts = contacts);
  }

  Future<void> _addContact() async {
    final npub = _npubController.text.trim();
    final label = _labelController.text.trim();

    if (!NostrService.isValidNpub(npub)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Essa npub não parece válida')),
      );
      return;
    }
    if (label.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dê um nome para esse contato')),
      );
      return;
    }

    setState(() => _adding = true);
    try {
      await NostrService.instance.addContact(npub, label);
      _labelController.clear();
      _npubController.clear();
      await _loadContacts();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível adicionar: $e')),
      );
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _removeContact(TrustedContact contact) async {
    await NostrService.instance.removeContact(contact.npub);
    await _loadContacts();
  }

  Future<void> _testContact(TrustedContact contact) async {
    setState(() => _testingNpub = contact.npub);
    try {
      final delivery = await NostrService.instance.sendContactTest(contact);
      await NostrService.instance.recordContactTest(contact.npub, delivery);
      await _loadContacts();
      if (!mounted) return;
      final message = delivery.accepted
          ? 'Teste aceito por ${delivery.acceptedRelays.length} relay(s): '
              '${delivery.acceptedRelays.join(', ')}'
          : delivery.error ?? 'Não foi possível entregar o teste.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _testingNpub = null);
    }
  }

  Future<void> _editInboxRelays(TrustedContact contact) async {
    final controller =
        TextEditingController(text: contact.inboxRelays.join('\n'));
    final relays = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Relays de mensagens'),
        content: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 5,
          autocorrect: false,
          decoration: const InputDecoration(
            hintText: 'wss://relay.exemplo.com\nUm relay por linha',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(
              controller.text
                  .split(RegExp(r'\s+'))
                  .where((value) => value.trim().isNotEmpty)
                  .toList(),
            ),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (relays == null) return;
    try {
      await NostrService.instance.setContactInboxRelays(contact.npub, relays);
      await _loadContacts();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _confirmContactCode(TrustedContact contact) async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmar contato'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(
            hintText: 'Código recebido pela pessoa',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (code == null) return;
    final verified =
        await NostrService.instance.verifyContactCode(contact.npub, code);
    await _loadContacts();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          verified
              ? 'Contato verificado com sucesso.'
              : 'Código inválido ou expirado.',
        ),
      ),
    );
  }

  static String _shortenNpub(String npub) {
    if (npub.length <= 20) return npub;
    return '${npub.substring(0, 12)}…${npub.substring(npub.length - 6)}';
  }

  @override
  Widget build(BuildContext context) {
    final contacts = _contacts;
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
                    'Rede de confiança',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: SatraColors.navy),
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: SatraColors.errorBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: SatraColors.errorBorder),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_rounded,
                      color: SatraColors.error, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Essas pessoas recebem um alerta discreto quando você ativa o '
                      'modo de escape. Adicione só quem for realmente de confiança.',
                      style: TextStyle(
                          color: SatraColors.errorDark, fontSize: 13, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'CONTATOS ADICIONADOS',
              style: TextStyle(
                  color: SatraColors.medium,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 0.5),
            ),
            const SizedBox(height: 8),
            if (contacts == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (contacts.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: SatraColors.light),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.people_outline,
                        color: SatraColors.light, size: 32),
                    SizedBox(height: 10),
                    Text('Nenhum contato adicionado ainda',
                        style: TextStyle(color: Colors.black54)),
                  ],
                ),
              )
            else
              for (final contact in contacts)
                Dismissible(
                  key: ValueKey(contact.npub),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: SatraColors.error,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child:
                        const Icon(Icons.delete_outline, color: Colors.white),
                  ),
                  onDismissed: (_) => _removeContact(contact),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: SatraColors.light),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                contact.label,
                                style: const TextStyle(
                                    color: SatraColors.navy,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _shortenNpub(contact.npub),
                                style: const TextStyle(
                                    color: SatraColors.medium, fontSize: 12),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                contact.verifiedAt != null
                                    ? 'Contato verificado'
                                    : contact.lastTestAccepted == true
                                        ? 'Teste aceito · aguardando código'
                                        : contact.lastTestAccepted == false
                                            ? 'Teste falhou: ${contact.lastTestError ?? 'erro desconhecido'}'
                                            : 'Contato ainda não testado',
                                style: TextStyle(
                                  color: contact.verifiedAt != null
                                      ? SatraColors.successDark
                                      : contact.lastTestAccepted == true
                                          ? SatraColors.successDark
                                          : contact.lastTestAccepted == false
                                              ? SatraColors.error
                                              : SatraColors.medium,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (contact.verificationChallengeHash != null)
                          IconButton(
                            tooltip: 'Informar código de confirmação',
                            onPressed: () => _confirmContactCode(contact),
                            icon: const Icon(
                              Icons.verified_user_outlined,
                              color: SatraColors.medium,
                            ),
                          ),
                        IconButton(
                          tooltip: 'Configurar relay manual',
                          onPressed: () => _editInboxRelays(contact),
                          icon: const Icon(
                            Icons.settings_input_antenna,
                            color: SatraColors.medium,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Enviar mensagem de teste',
                          onPressed: _testingNpub == null
                              ? () => _testContact(contact)
                              : null,
                          icon: _testingNpub == contact.npub
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: SatraColors.medium,
                                  ),
                                )
                              : const Icon(
                                  Icons.send_outlined,
                                  color: SatraColors.medium,
                                ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: SatraColors.medium),
                          onPressed: () => _removeContact(contact),
                        ),
                      ],
                    ),
                  ),
                ),
            const SizedBox(height: 24),
            const Divider(color: SatraColors.light),
            const SizedBox(height: 16),
            const Text(
              'ADICIONAR CONTATO',
              style: TextStyle(
                  color: SatraColors.medium,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 0.5),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _labelController,
              style: const TextStyle(color: SatraColors.navy),
              decoration: InputDecoration(
                hintText: 'Nome (ex: Amiga Ana)',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: SatraColors.light),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _npubController,
              autocorrect: false,
              style: const TextStyle(color: SatraColors.navy),
              decoration: InputDecoration(
                hintText: 'npub1...',
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
                onPressed: _adding ? null : _addContact,
                style: ElevatedButton.styleFrom(
                  backgroundColor: SatraColors.navy,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26)),
                ),
                child: _adding
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Adicionar contato',
                        style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
