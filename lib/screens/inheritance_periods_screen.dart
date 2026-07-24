import 'package:flutter/material.dart';

import '../services/inheritance_service.dart';
import '../theme/colors.dart';
import '../widgets/glass_widgets.dart';

class InheritancePeriodsScreen extends StatefulWidget {
  const InheritancePeriodsScreen({super.key});

  @override
  State<InheritancePeriodsScreen> createState() =>
      _InheritancePeriodsScreenState();
}

class _InheritancePeriodsScreenState extends State<InheritancePeriodsScreen> {
  final _inactivity = TextEditingController();
  final _grace = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  int _inactivityDays = InheritanceService.defaultInactivityDays;
  int _graceDays = InheritanceService.defaultGraceDays;

  @override
  void initState() {
    super.initState();
    _inactivity.addListener(() => setState(() {}));
    _grace.addListener(() => setState(() {}));
    _load();
  }

  Future<void> _load() async {
    final state = await InheritanceService.instance.getState();
    _inactivityDays = state.inactivityDays;
    _graceDays = state.graceDays;
    _inactivity.text = '${state.inactivityDays}';
    _grace.text = '${state.graceDays}';
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _inactivity.dispose();
    _grace.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final inactivity = int.tryParse(_inactivity.text.trim());
    final grace = int.tryParse(_grace.text.trim());
    if (inactivity == null || grace == null || inactivity <= 0 || grace <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe períodos válidos em dias.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await InheritanceService.instance.setInactivityDays(inactivity);
      await InheritanceService.instance.setGraceDays(grace);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _selectInactivity(int days) {
    setState(() {
      _inactivityDays = days;
      _inactivity.text = '$days';
    });
  }

  void _selectGrace(int days) {
    setState(() {
      _graceDays = days;
      _grace.text = '$days';
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: SatraColors.glassVoid,
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(color: SatraColors.glassAqua))
            : SafeArea(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  children: [
                    GlassHeader(title: 'Carência e inatividade'),
                    const SizedBox(height: 18),
                    _timeline(),
                    const SizedBox(height: 20),
                    const Text(
                      'O período de inatividade determina quanto tempo sem '
                      'prova de vida inicia o processo. A carência é o prazo '
                      'adicional para o titular voltar e cancelar a liberação.',
                      style: TextStyle(
                        color: SatraColors.glassBoneDim,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 22),
                    _periodSection(
                      title: 'Tempo de inatividade',
                      icon: Icons.hourglass_empty,
                      controller: _inactivity,
                      helper: 'Ex.: 180 dias',
                      presets: InheritanceService.inactivityPresetDays,
                      selectedDays: _inactivityDays,
                      onSelect: _selectInactivity,
                      presetLabels: const {
                        90: '3 meses',
                        180: '6 meses',
                        365: '1 ano',
                      },
                    ),
                    const SizedBox(height: 20),
                    _periodSection(
                      title: 'Tempo de carência',
                      icon: Icons.hourglass_top,
                      controller: _grace,
                      helper: 'Ex.: 30 dias',
                      presets: InheritanceService.gracePresetDays,
                      selectedDays: _graceDays,
                      onSelect: _selectGrace,
                      presetLabels: const {
                        7: '7 dias',
                        14: '14 dias',
                        30: '30 dias',
                      },
                    ),
                    const SizedBox(height: 26),
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
                                    strokeWidth: 2,
                                    color: SatraColors.glassVoid),
                              )
                            : const Text('Salvar'),
                      ),
                    ),
                  ],
                ),
              ),
      );

  /// A horizontal visual showing the three phases: inactivity → grace →
  /// release, so the abstract concept becomes concrete at a glance. Each
  /// step is a glass chip and the connectors read as a continuous rail.
  Widget _timeline() {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Como funciona',
            style: TextStyle(
              color: SatraColors.glassBone,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _timelineStep(
                icon: Icons.favorite,
                color: SatraColors.glassAqua,
                label: 'Prova de vida',
              ),
              _timelineConnector(),
              _timelineStep(
                icon: Icons.hourglass_empty,
                color: SatraColors.glassAmber,
                label: 'Inatividade',
              ),
              _timelineConnector(),
              _timelineStep(
                icon: Icons.lock_open,
                color: SatraColors.error,
                label: 'Liberação',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _timelineStep({
    required IconData icon,
    required Color color,
    required String label,
  }) =>
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              color: SatraColors.glassBoneDim,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );

  Widget _timelineConnector() => Expanded(
        child: Container(
          height: 2,
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
            color: SatraColors.glassFrost,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      );

  Widget _periodSection({
    required String title,
    required IconData icon,
    required TextEditingController controller,
    required String helper,
    required List<int> presets,
    required int selectedDays,
    required ValueChanged<int> onSelect,
    required Map<int, String> presetLabels,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: SatraColors.glassBoneDim, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: SatraColors.glassBone,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final days in presets)
                ChoiceChip(
                  label: Text(presetLabels[days] ?? '$days dias'),
                  selected: selectedDays == days &&
                      controller.text.trim() == '$days',
                  selectedColor: SatraColors.glassAqua.withValues(alpha: 0.15),
                  backgroundColor: SatraColors.glass,
                  side: BorderSide(
                    color: selectedDays == days &&
                            controller.text.trim() == '$days'
                        ? SatraColors.glassAqua.withValues(alpha: 0.5)
                        : SatraColors.glassFrost,
                  ),
                  labelStyle: TextStyle(
                    color: selectedDays == days &&
                            controller.text.trim() == '$days'
                        ? SatraColors.glassAqua
                        : SatraColors.glassBoneDim,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  onSelected: (_) => onSelect(days),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: SatraColors.glassBone),
            decoration: glassInputDecoration(
              labelText: 'Personalizado',
              helperText: helper,
              suffixText: 'dias',
              prefixIcon:
                  const Icon(Icons.edit_outlined, color: SatraColors.glassBoneDim),
            ),
          ),
        ],
      );
}
