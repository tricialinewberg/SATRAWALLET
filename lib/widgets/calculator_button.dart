import 'package:flutter/material.dart';

class CalculatorButton extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final VoidCallback onPressed;
  final Color backgroundColor;
  final Color foregroundColor;

  const CalculatorButton({
    super.key,
    this.label,
    this.icon,
    required this.onPressed,
    this.backgroundColor = const Color(0xFF2C2C2C),
    this.foregroundColor = Colors.white,
  }) : assert(label != null || icon != null);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
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
    );
  }
}
