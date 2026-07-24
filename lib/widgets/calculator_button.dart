import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/colors.dart';

class CalculatorButton extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final VoidCallback onPressed;
  final VoidCallback? onLongPress;
  final Color backgroundColor;
  final Color foregroundColor;

  const CalculatorButton({
    super.key,
    this.label,
    this.icon,
    required this.onPressed,
    this.onLongPress,
    this.backgroundColor = SatraColors.calculatorBg,
    this.foregroundColor = Colors.white,
  }) : assert(label != null || icon != null);

  void _handleTap() {
    HapticFeedback.lightImpact();
    onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final semantic = label ?? 'Botão';
    return Semantics(
      button: true,
      label: semantic,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _handleTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(28),
          child: Container(
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(28),
            ),
            alignment: Alignment.center,
            child: icon != null
                ? Icon(icon, size: 26, color: foregroundColor)
                : Text(
                    label!,
                    style: TextStyle(
                      fontSize: 28,
                      color: foregroundColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
