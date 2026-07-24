import 'package:flutter/material.dart';

import '../services/inheritance_service.dart';
import '../services/nostr_service.dart';
import '../theme/colors.dart';
import '../widgets/glass_widgets.dart';

class InheritanceHeirsScreen extends StatefulWidget {
  const InheritanceHeirsScreen({super.key});

  @override
  State<InheritanceHeirsScreen> createState() => _InheritanceHeirsScreenState();
}

class _InheritanceHeirsScreenState extends State<InheritanceHeirsScreen> {
  InheritanceState? _state;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = await InheritanceService.instance.getState();
    if (mounted) setState(() => _state = state);
  }

  Future<void> _edit([TrustedContact? heir]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: SatraColors.glassVoid,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _HeirForm(heir: heir),
    );
    if (saved == true) await _load();
  }

  Future<void> _remove(TrustedContact heir) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: SatraColors.glass,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Remover herdeiro?',
          style: TextStyle(color: SatraColors.glassBone),
        ),
        content: Text(
          '${heir.label} será removido da configuração.',
          style: const TextStyle(color: SatraColors.glassBoneDim),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: SatraColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await InheritanceService.instance.removeHeir(heir.npub);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final heirs = _state?.heirs;
    return Scaffold(
      backgroundColor: SatraColors.glassVoid,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _edit,
        backgroundColor: SatraColors.glassAqua,
        foregroundColor: SatraColors.glassVoid,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Adicionar'),
      ),
      body: SafeArea(
        child: heirs == null
            ? const Center(
                child:
                    CircularProgressIndicator(color: SatraColors.glassAqua))
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                children: [
                  GlassHeader(title: 'Herdeiros'),
                  const SizedBox(height: 18),
                  if (heirs.isEmpty)
                    _emptyState()
                  else
                    for (final heir in heirs) ...[
                      _HeirCard(
                        heir: heir,
                        onTap: () => _edit(heir),
                        onRemove: () => _remove(heir),
                      ),
                      const SizedBox(height: 10),
                      ],
                ],
              ),
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: SatraColors.glassFrost.withValues(alpha: 0.4),
              shape: BoxShape.circle,
              border: Border.all(color: SatraColors.glassFrost),
            ),
            child: const Icon(
              Icons.people_outline,
              size: 44,
              color: SatraColors.glassBoneDim,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Nenhum herdeiro cadastrado',
            style: TextStyle(
              color: SatraColors.glassBone,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Adicione as pessoas que poderão recuperar sua carteira '
            'após o prazo de inatividade.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: SatraColors.glassBoneDim,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _edit,
            style: FilledButton.styleFrom(
              backgroundColor: SatraColors.glassAqua,
              foregroundColor: SatraColors.glassVoid,
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.person_add_alt_1, size: 20),
            label: const Text('Adicionar primeiro herdeiro'),
          ),
        ],
      ),
    );
  }
}

/// A single heir rendered as a glass card. The chip is frost (the same
/// surface as the card, just elevated a step), the verified badge is aqua
/// — light through glass confirming the heir can actually be reached.
class _HeirCard extends StatelessWidget {
  const _HeirCard({
    required this.heir,
    required this.onTap,
    required this.onRemove,
  });

  final TrustedContact heir;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final verified = heir.verifiedAt != null;
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: SatraColors.glassFrost.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: SatraColors.glassFrost),
            ),
            child: const Icon(Icons.person_outline,
                color: SatraColors.glassBoneDim, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        heir.label,
                        style: const TextStyle(
                          color: SatraColors.glassBone,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    if (verified) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.verified,
                          size: 16, color: SatraColors.glassAqua),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  _HeirCard._short(heir.npub),
                  style: const TextStyle(
                    color: SatraColors.glassBoneDim,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
                if (heir.relationship != null ||
                    heir.sharePercentage != null) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: [
                      if (heir.relationship?.isNotEmpty == true)
                        _pill(Icons.wc_outlined, heir.relationship!),
                      if (heir.sharePercentage != null)
                        _pill(Icons.pie_chart_outline,
                            '${heir.sharePercentage!.toStringAsFixed(0)}%'),
                    ],
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remover ${heir.label}',
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline,
                color: SatraColors.error, size: 22),
          ),
        ],
      ),
    );
  }

  Widget _pill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: SatraColors.glassVoid.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: SatraColors.glassFrost),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: SatraColors.glassBoneDim),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              color: SatraColors.glassBoneDim,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  static String _short(String npub) => npub.length < 24
      ? npub
      : '${npub.substring(0, 14)}…${npub.substring(npub.length - 6)}';
}

class _HeirForm extends StatefulWidget {
  const _HeirForm({this.heir});
  final TrustedContact? heir;

  @override
  State<_HeirForm> createState() => _HeirFormState();
}

class _HeirFormState extends State<_HeirForm> {
  late final TextEditingController _name;
  late final TextEditingController _npub;
  late final TextEditingController _relationship;
  late final TextEditingController _percentage;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final heir = widget.heir;
    _name = TextEditingController(text: heir?.label);
    _npub = TextEditingController(text: heir?.npub);
    _relationship = TextEditingController(text: heir?.relationship);
    _percentage = TextEditingController(
      text: heir?.sharePercentage?.toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _npub.dispose();
    _relationship.dispose();
    _percentage.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final percentageText = _percentage.text.trim().replaceAll(',', '.');
    final percentage =
        percentageText.isEmpty ? null : double.tryParse(percentageText);
    if (_name.text.trim().isEmpty ||
        !NostrService.isValidNpub(_npub.text.trim()) ||
        (percentageText.isNotEmpty && percentage == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Revise o nome, npub e percentual.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await InheritanceService.instance.addHeir(
        _npub.text,
        _name.text,
        relationship: _relationship.text,
        sharePercentage: percentage,
        replacingNpub: widget.heir?.npub,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            12,
            24,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: SatraColors.glassFrost,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    GlassIconChip(
                      icon: widget.heir == null
                          ? Icons.person_add_alt_1_outlined
                          : Icons.edit_outlined,
                      accent: SatraColors.glassAqua,
                      size: 44,
                      iconSize: 22,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      widget.heir == null
                          ? 'Adicionar herdeiro'
                          : 'Editar herdeiro',
                      style: const TextStyle(
                        color: SatraColors.glassBone,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _field(_name, 'Nome do herdeiro', Icons.person_outline),
                _field(_npub, 'Chave pública Nostr (npub)', Icons.alternate_email,
                    mono: true),
                _field(_relationship, 'Relação (opcional)', Icons.wc_outlined),
                _field(
                  _percentage,
                  'Percentual da herança (opcional)',
                  Icons.pie_chart_outline,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: SatraColors.glassAqua,
                      foregroundColor: SatraColors.glassVoid,
                      disabledBackgroundColor:
                          SatraColors.glassAqua.withValues(alpha: 0.25),
                      disabledForegroundColor: SatraColors.glassBoneDim,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: SatraColors.glassVoid),
                          )
                        : const Text('Salvar'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType? keyboardType,
    bool mono = false,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: controller,
          keyboardType: keyboardType,
          autocorrect: false,
          style: TextStyle(
            color: SatraColors.glassBone,
            fontFamily: mono ? 'monospace' : null,
            fontSize: mono ? 12 : null,
          ),
          decoration: glassInputDecoration(
            labelText: label,
            prefixIcon: Icon(icon, color: SatraColors.glassBoneDim, size: 20),
          ),
        ),
      );
}
