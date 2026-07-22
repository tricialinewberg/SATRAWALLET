import 'package:flutter/material.dart';

import '../services/inheritance_service.dart';
import '../services/nostr_service.dart';
import '../theme/colors.dart';

/// "Herança": configure the inactivity-triggered inheritance feature —
/// enable/disable, register heirs (same npub+label shape as
/// [TrustedContactsScreen]'s trusted contacts, just a separate list), pick
/// the inactivity and grace periods, and set the password used to encrypt
/// the seed released to heirs. See [InheritanceService] for the state
/// machine this screen configures and its important limitations.
class InheritanceSetupScreen extends StatefulWidget {
  const InheritanceSetupScreen({super.key});

  @override
  State<InheritanceSetupScreen> createState() => _InheritanceSetupScreenState();
}

class _InheritanceSetupScreenState extends State<InheritanceSetupScreen> {
  InheritanceState? _state;
  bool _hasPassword = false;
  bool _toggling = false;
  bool _addingHeir = false;
  bool _savingPassword = false;

  final _heirLabelController = TextEditingController();
  final _heirNpubController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _customInactivityController = TextEditingController();
  final _customGraceController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _heirLabelController.dispose();
    _heirNpubController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _customInactivityController.dispose();
    _customGraceController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final state = await InheritanceService.instance.getState();
    final hasPassword = await InheritanceService.instance.hasPassword();
    if (!mounted) return;
    setState(() {
      _state = state;
      _hasPassword = hasPassword;
    });
  }

  Future<void> _toggleEnabled(bool value) async {
    setState(() => _toggling = true);
    try {
      await InheritanceService.instance.setEnabled(value);
      await _load();
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  Future<void> _addHeir() async {
    final npub = _heirNpubController.text.trim();
    final label = _heirLabelController.text.trim();

    if (!NostrService.isValidNpub(npub)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Essa npub não parece válida')),
      );
      return;
    }
    if (label.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dê um nome para esse herdeiro')),
      );
      return;
    }

    setState(() => _addingHeir = true);
    try {
      await InheritanceService.instance.addHeir(npub, label);
      _heirLabelController.clear();
      _heirNpubController.clear();
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível adicionar: $e')),
      );
    } finally {
      if (mounted) setState(() => _addingHeir = false);
    }
  }

  Future<void> _removeHeir(TrustedContact heir) async {
    await InheritanceService.instance.removeHeir(heir.npub);
    await _load();
  }

  Future<void> _setInactivityDays(int days) async {
    await InheritanceService.instance.setInactivityDays(days);
    await _load();
  }

  Future<void> _applyCustomInactivityDays() async {
    final days = int.tryParse(_customInactivityController.text.trim());
    if (days == null || days <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe um número de dias válido')),
      );
      return;
    }
    _customInactivityController.clear();
    await _setInactivityDays(days);
  }

  Future<void> _setGraceDays(int days) async {
    await InheritanceService.instance.setGraceDays(days);
    await _load();
  }

  Future<void> _applyCustomGraceDays() async {
    final days = int.tryParse(_customGraceController.text.trim());
    if (days == null || days <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe um número de dias válido')),
      );
      return;
    }
    _customGraceController.clear();
    await _setGraceDays(days);
  }

  Future<void> _savePassword() async {
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    if (password.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A senha precisa ter pelo menos 8 caracteres.')),
      );
      return;
    }
    if (password != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('As senhas não coincidem.')),
      );
      return;
    }

    setState(() => _savingPassword = true);
    try {
      await InheritanceService.instance.setPassword(password);
      _passwordController.clear();
      _confirmController.clear();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Senha de liberação salva.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _savingPassword = false);
    }
  }

  static String _shortenNpub(String npub) {
    if (npub.length <= 20) return npub;
    return '${npub.substring(0, 12)}…${npub.substring(npub.length - 6)}';
  }

  static String _daysLabel(int days) {
    if (days % 365 == 0 && days >= 365) return '${days ~/ 365} ano(s)';
    if (days % 30 == 0 && days >= 30) return '${days ~/ 30} mes(es)';
    return '$days dia(s)';
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
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
                    'Herança',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: SatraColors.navy),
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
            const SizedBox(height: 16),
            if (state == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              _buildStatusCard(state),
              const SizedBox(height: 20),
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
                        'Se a carteira ficar sem uso pelo período configurado, seus herdeiros são '
                        'avisados. Se não houver atividade durante o período de carência que segue, '
                        'a frase de recuperação (cifrada com a senha definida aqui) é enviada a eles.',
                        style: TextStyle(color: Color(0xFF7A1F1F), fontSize: 13, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: SatraColors.light),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        state.enabled ? 'Herança ativada' : 'Ativar herança',
                        style: const TextStyle(color: SatraColors.navy, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                    if (_toggling)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: SatraColors.medium),
                      )
                    else
                      Switch(
                        value: state.enabled,
                        activeThumbColor: SatraColors.navy,
                        onChanged: (value) => _toggleEnabled(value),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Divider(color: SatraColors.light),
              const SizedBox(height: 16),
              const Text(
                'PERÍODO DE INATIVIDADE',
                style: TextStyle(color: SatraColors.medium, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5),
              ),
              const SizedBox(height: 4),
              const Text(
                'Quanto tempo sem abrir o app até o processo de herança começar.',
                style: TextStyle(color: SatraColors.medium, fontSize: 12),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in InheritanceService.inactivityPresetDays)
                    ChoiceChip(
                      label: Text(_daysLabel(preset)),
                      selected: state.inactivityDays == preset,
                      selectedColor: SatraColors.navy,
                      labelStyle: TextStyle(
                        color: state.inactivityDays == preset ? Colors.white : SatraColors.navy,
                        fontWeight: FontWeight.w600,
                      ),
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: SatraColors.light),
                      onSelected: (_) => _setInactivityDays(preset),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _customInactivityController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: SatraColors.navy),
                      decoration: InputDecoration(
                        hintText: 'Número de dias personalizado',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: SatraColors.light),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _applyCustomInactivityDays,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: SatraColors.navy),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('Aplicar', style: TextStyle(color: SatraColors.navy, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Divider(color: SatraColors.light),
              const SizedBox(height: 16),
              const Text(
                'PERÍODO DE CARÊNCIA',
                style: TextStyle(color: SatraColors.medium, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5),
              ),
              const SizedBox(height: 4),
              const Text(
                'Quanto tempo os herdeiros esperam, após o aviso, antes de receber a recuperação.',
                style: TextStyle(color: SatraColors.medium, fontSize: 12),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in InheritanceService.gracePresetDays)
                    ChoiceChip(
                      label: Text(_daysLabel(preset)),
                      selected: state.graceDays == preset,
                      selectedColor: SatraColors.navy,
                      labelStyle: TextStyle(
                        color: state.graceDays == preset ? Colors.white : SatraColors.navy,
                        fontWeight: FontWeight.w600,
                      ),
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: SatraColors.light),
                      onSelected: (_) => _setGraceDays(preset),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _customGraceController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: SatraColors.navy),
                      decoration: InputDecoration(
                        hintText: 'Número de dias personalizado',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: SatraColors.light),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _applyCustomGraceDays,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: SatraColors.navy),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('Aplicar', style: TextStyle(color: SatraColors.navy, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Divider(color: SatraColors.light),
              const SizedBox(height: 16),
              const Text(
                'HERDEIROS',
                style: TextStyle(color: SatraColors.medium, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5),
              ),
              const SizedBox(height: 8),
              if (state.heirs.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: SatraColors.light),
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.family_restroom_outlined, color: SatraColors.light, size: 32),
                      SizedBox(height: 10),
                      Text('Nenhum herdeiro adicionado ainda', style: TextStyle(color: Colors.black54)),
                    ],
                  ),
                )
              else
                for (final heir in state.heirs)
                  Dismissible(
                    key: ValueKey(heir.npub),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD64545),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.delete_outline, color: Colors.white),
                    ),
                    onDismissed: (_) => _removeHeir(heir),
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
                                  heir.label,
                                  style: const TextStyle(color: SatraColors.navy, fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _shortenNpub(heir.npub),
                                  style: const TextStyle(color: SatraColors.medium, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: SatraColors.medium),
                            onPressed: () => _removeHeir(heir),
                          ),
                        ],
                      ),
                    ),
                  ),
              const SizedBox(height: 12),
              TextField(
                controller: _heirLabelController,
                style: const TextStyle(color: SatraColors.navy),
                decoration: InputDecoration(
                  hintText: 'Nome (ex: Filho João)',
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
                controller: _heirNpubController,
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
                  onPressed: _addingHeir ? null : _addHeir,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SatraColors.navy,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                  ),
                  child: _addingHeir
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Adicionar herdeiro', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 24),
              const Divider(color: SatraColors.light),
              const SizedBox(height: 16),
              const Text(
                'SENHA DE LIBERAÇÃO',
                style: TextStyle(color: SatraColors.medium, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5),
              ),
              const SizedBox(height: 4),
              Text(
                _hasPassword
                    ? 'Uma senha já está configurada. Salvar novamente a substitui.'
                    : 'Necessária antes de ativar. Combine-a com seus herdeiros por fora do app — '
                        'sem ela, a frase de recuperação enviada a eles não pode ser lida.',
                style: const TextStyle(color: SatraColors.medium, fontSize: 12, height: 1.3),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                style: const TextStyle(color: SatraColors.navy),
                decoration: InputDecoration(
                  labelText: 'Senha de liberação',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: SatraColors.medium),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _confirmController,
                obscureText: _obscurePassword,
                style: const TextStyle(color: SatraColors.navy),
                decoration: InputDecoration(
                  labelText: 'Confirmar senha',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _savingPassword ? null : _savePassword,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SatraColors.navy,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                  ),
                  child: _savingPassword
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Salvar senha de liberação', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(InheritanceState state) {
    final (String title, String subtitle, Color color, IconData icon) = switch (state.status) {
      InheritanceStatus.disabled => (
          'Herança desativada',
          'Ative para configurar o processo de herança.',
          SatraColors.medium,
          Icons.pause_circle_outline,
        ),
      InheritanceStatus.healthy => (
          'Ativa e saudável',
          'Faltam ${_daysLabel(state.timeUntilInactivityThreshold.inDays)} até o limite de inatividade.',
          const Color(0xFF3FBF6F),
          Icons.check_circle_outline,
        ),
      InheritanceStatus.gracePeriod => (
          'Período de carência ativo',
          'Faltam ${_daysLabel(state.timeUntilGraceDeadline?.inDays ?? 0)} para a liberação — '
              'abra o app normalmente para cancelar.',
          const Color(0xFFD68A00),
          Icons.hourglass_bottom,
        ),
      InheritanceStatus.released => (
          'Informações liberadas',
          'A frase de recuperação já foi enviada aos herdeiros.',
          const Color(0xFFD64545),
          Icons.lock_open_outlined,
        ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(color: SatraColors.navy, fontSize: 13, height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
