import 'package:flutter/material.dart';

import '../services/inheritance_service.dart';
import '../theme/colors.dart';
import '../widgets/glass_widgets.dart';

class InheritancePasswordScreen extends StatefulWidget {
  const InheritancePasswordScreen({super.key});

  @override
  State<InheritancePasswordScreen> createState() =>
      _InheritancePasswordScreenState();
}

class _InheritancePasswordScreenState extends State<InheritancePasswordScreen> {
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _obscure = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _password.addListener(() => setState(() {}));
    _confirmation.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_password.text.length < 8) {
      _message('Use pelo menos 8 caracteres.');
      return;
    }
    if (_password.text != _confirmation.text) {
      _message('As senhas não coincidem.');
      return;
    }
    setState(() => _saving = true);
    try {
      await InheritanceService.instance.setPassword(_password.text);
      if (!mounted) return;
      _message('Senha de liberação salva.');
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) _message('$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  /// Returns a 0-4 strength score based on length + character variety.
  int get _strengthScore {
    final p = _password.text;
    if (p.isEmpty) return 0;
    var score = 0;
    if (p.length >= 8) score++;
    if (p.length >= 12) score++;
    if (p.contains(RegExp(r'[A-Z]')) && p.contains(RegExp(r'[a-z]'))) score++;
    if (p.contains(RegExp(r'[0-9]')) || p.contains(RegExp(r'[^A-Za-z0-9]'))) {
      score++;
    }
    return score;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: SatraColors.glassVoid,
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              GlassHeader(title: 'Senha de liberação'),
              const SizedBox(height: 18),
              _hero(),
              const SizedBox(height: 18),
              _infoCard(),
              const SizedBox(height: 24),
              _passwordField(_password, 'Definir senha'),
              if (_password.text.isNotEmpty) ...[
                const SizedBox(height: 10),
                _strengthIndicator(),
              ],
              const SizedBox(height: 14),
              _passwordField(_confirmation, 'Confirmar senha'),
              if (_confirmation.text.isNotEmpty &&
                  _password.text != _confirmation.text) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.error_outline,
                        size: 15, color: SatraColors.error),
                    const SizedBox(width: 6),
                    const Text(
                      'As senhas não coincidem.',
                      style:
                          TextStyle(color: SatraColors.error, fontSize: 12),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
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
                      : const Text('Salvar senha'),
                ),
              ),
            ],
          ),
        ),
      );

  /// Glass hero — the deep luminous panel that anchors the screen. The
  /// single aqua accent reads as light refracting through the tinted glass,
  /// replacing the old navy→medium diagonal gradient.
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
          GlassIconChip(
            icon: Icons.key_outlined,
            accent: SatraColors.glassAqua,
            size: 52,
            iconSize: 28,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Senha da herança',
                  style: TextStyle(
                    color: SatraColors.glassBone,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Compartilhada em vida por canal seguro.',
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

  /// An info callout rendered as a glass card with an aqua-tinted icon
  /// chip, replacing the old light-blue EDF2FA container.
  Widget _infoCard() {
    return GlassCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const GlassIconChip(
            icon: Icons.info_outline,
            accent: SatraColors.glassAqua,
            size: 32,
            iconSize: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Esta senha decifra a recuperação entregue aos herdeiros. '
              'Compartilhe-a por um canal separado e seguro (ex.: cartão '
              'lacrado). Sem ela, o conteúdo criptografado da herança não '
              'poderá ser aberto.',
              style: const TextStyle(
                color: SatraColors.glassBone,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _strengthIndicator() {
    const labels = ['Muito fraca', 'Fraca', 'Razoável', 'Boa', 'Forte'];
    // Strength colors that read well on a dark glass surface: keep the
    // semantic gradient (red → amber → green) but pick the luminous variants
    // so they stay visible against the void background.
    const colors = [
      SatraColors.error,
      SatraColors.error,
      SatraColors.warning,
      SatraColors.success,
      SatraColors.success,
    ];
    final score = _strengthScore;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Row(
              children: [
                for (var i = 0; i < 4; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 5,
                      decoration: BoxDecoration(
                        color: i < score
                            ? colors[score]
                            : SatraColors.glassFrost,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          labels[score],
          style: TextStyle(
            color: colors[score],
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _passwordField(TextEditingController controller, String label) =>
      TextField(
        controller: controller,
        obscureText: _obscure,
        style: const TextStyle(color: SatraColors.glassBone),
        decoration: glassInputDecoration(
          labelText: label,
          prefixIcon:
              const Icon(Icons.lock_outline, color: SatraColors.glassBoneDim),
          suffixIcon: IconButton(
            tooltip: _obscure ? 'Mostrar senha' : 'Ocultar senha',
            onPressed: () => setState(() => _obscure = !_obscure),
            icon: Icon(
              _obscure ? Icons.visibility_off : Icons.visibility,
              color: SatraColors.glassBoneDim,
            ),
          ),
        ),
      );
}
