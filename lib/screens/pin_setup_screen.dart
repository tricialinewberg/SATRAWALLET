import 'package:flutter/material.dart';

import '../routes.dart';
import '../services/pin_service.dart';
import '../theme/colors.dart';

/// One-time initial setup screen where the user defines her personal PIN.
/// Reused later from the side menu for "Trocar PIN" (change PIN).
class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key});

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  static const _pinLength = 4;

  final PinService _pinService = PinService();
  String _pin = '';
  bool _saving = false;

  void _addDigit(String digit) {
    if (_pin.length >= _pinLength || _saving) return;
    setState(() => _pin += digit);
  }

  void _backspace() {
    if (_pin.isEmpty || _saving) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _confirm() async {
    if (_pin.length != _pinLength || _saving) return;
    setState(() => _saving = true);

    await _pinService.savePin(_pin);
    if (!mounted) return;

    Navigator.of(context).pushNamedAndRemoveUntil(
      SatraRoutes.walletHome,
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isComplete = _pin.length == _pinLength;

    return Scaffold(
      backgroundColor: SatraColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'CONFIGURAÇÃO INICIAL',
                style: TextStyle(
                  color: SatraColors.medium,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Defina seu PIN',
                style: TextStyle(
                  color: SatraColors.navy,
                  fontWeight: FontWeight.w800,
                  fontSize: 32,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 20),
              _WarningCard(
                title: 'Não conte pra ninguém',
                message: 'Esse PIN é só seu. Nunca compartilhe, nem com pessoas de confiança.',
              ),
              const SizedBox(height: 12),
              _WarningCard(
                title: 'Evite sequências óbvias',
                message: 'Nada de datas óbvias. Você vai usar esse PIN toda vez que acessar a carteira.',
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(_pinLength, (index) {
                  final filled = index < _pin.length;
                  return _PinBox(
                    digit: filled ? _pin[index] : null,
                    active: index == _pin.length,
                  );
                }),
              ),
              const Spacer(),
              _Keypad(onDigit: _addDigit, onBackspace: _backspace),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: isComplete ? _confirm : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SatraColors.navy,
                    disabledBackgroundColor: SatraColors.navy.withValues(alpha: 0.4),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Confirmar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WarningCard extends StatelessWidget {
  final String title;
  final String message;

  const _WarningCard({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFDECEC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF3B9B9)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_rounded, color: Color(0xFFD64545), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF7A1F1F))),
                const SizedBox(height: 4),
                Text(message, style: const TextStyle(color: Color(0xFF7A1F1F), fontSize: 13, height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PinBox extends StatelessWidget {
  final String? digit;
  final bool active;

  const _PinBox({required this.digit, required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 68,
      height: 68,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active || digit != null ? SatraColors.navy : SatraColors.light,
          width: active ? 2 : 1,
        ),
      ),
      child: Text(
        digit ?? '',
        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: SatraColors.navy),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  const _Keypad({required this.onDigit, required this.onBackspace});

  @override
  Widget build(BuildContext context) {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
    ];

    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: row.map((d) => _KeypadButton(label: d, onTap: () => onDigit(d))).toList(),
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const SizedBox(width: 96, height: 56),
            _KeypadButton(label: '0', onTap: () => onDigit('0')),
            _KeypadButton(icon: Icons.backspace_outlined, onTap: onBackspace),
          ],
        ),
      ],
    );
  }
}

class _KeypadButton extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final VoidCallback onTap;

  const _KeypadButton({this.label, this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 96,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: SatraColors.light),
          ),
          child: icon != null
              ? Icon(icon, color: SatraColors.navy)
              : Text(
                  label!,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: SatraColors.navy),
                ),
        ),
      ),
    );
  }
}
