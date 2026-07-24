import 'package:flutter/material.dart';

import '../routes.dart';
import '../services/pin_service.dart';
import '../theme/colors.dart';

/// One-time initial setup screen where the user defines her personal PIN.
/// Reused later from the side menu for "Trocar PIN" (change PIN).
class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key, this.changing = false});

  final bool changing;

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
    final title = widget.changing ? 'Trocar PIN' : 'Crie seu PIN';
    final eyebrow = widget.changing ? 'SEGURANÇA DA CARTEIRA' : 'PRIMEIRO ACESSO';
    final subtitle = widget.changing
        ? 'Escolha um novo PIN de quatro dígitos para abrir sua carteira.'
        : 'Escolha um PIN de quatro dígitos para abrir sua carteira pela calculadora.';

    return Scaffold(
      backgroundColor: SatraColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (widget.changing)
                    IconButton(
                      tooltip: 'Voltar',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back),
                      color: SatraColors.navy,
                    )
                  else
                    const SizedBox(width: 48),
                  const Spacer(),
                  Icon(Icons.lock_outline_rounded,
                      color: SatraColors.medium, size: 22),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                eyebrow,
                style: TextStyle(
                  color: SatraColors.medium,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  letterSpacing: 0.7,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                style: TextStyle(
                  color: SatraColors.navy,
                  fontWeight: FontWeight.w700,
                  fontSize: 27,
                  letterSpacing: -.2,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              Text(subtitle,
                  style: const TextStyle(
                      color: SatraColors.medium, fontSize: 14, height: 1.35)),
              const SizedBox(height: 22),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: SatraColors.light),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.visibility_off_outlined,
                        color: SatraColors.medium, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.changing
                            ? 'O PIN antigo continua válido até você confirmar o novo.'
                            : 'Não compartilhe seu PIN. Ele nunca sai deste aparelho.',
                        style: const TextStyle(
                            color: SatraColors.navy, fontSize: 12, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
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
                height: 52,
                child: ElevatedButton(
                  onPressed: isComplete ? _confirm : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SatraColors.navy,
                    disabledBackgroundColor:
                        SatraColors.navy.withValues(alpha: 0.4),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Confirmar',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
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
      width: 62,
      height: 62,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: active || digit != null ? SatraColors.navy : SatraColors.light,
          width: active ? 2 : 1,
        ),
      ),
      child: Text(
        digit ?? '',
        style: const TextStyle(
            fontSize: 23, fontWeight: FontWeight.w800, color: SatraColors.navy),
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
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: row
                  .map((d) => _KeypadButton(label: d, onTap: () => onDigit(d)))
                  .toList(),
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const SizedBox(width: 84, height: 52),
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
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 84,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: SatraColors.light),
          ),
          child: icon != null
              ? Icon(icon, color: SatraColors.navy)
              : Text(
                  label!,
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: SatraColors.navy),
                ),
        ),
      ),
    );
  }
}
