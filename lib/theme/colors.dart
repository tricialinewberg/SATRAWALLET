import 'package:flutter/material.dart';

class SatraColors {
  SatraColors._();

  static const Color navy = Color(0xFF0B2545);
  static const Color medium = Color(0xFF1B4F8C);
  static const Color light = Color(0xFFA9D6E5);
  static const Color background = Color(0xFFF4F8FB);

  static const Color calculatorBg = Color(0xFF2C2C2C);

  static const Color success = Color(0xFF3FBF6F);
  static const Color successDark = Color(0xFF27864A);

  static const Color error = Color(0xFFD64545);
  static const Color errorDark = Color(0xFF7A1F1F);
  static const Color errorBg = Color(0xFFFDECEC);
  static const Color errorBorder = Color(0xFFF3B9B9);

  static const Color warning = Color(0xFFD68A00);
  static const Color warningAccent = Color(0xFFE0A52B);
  static const Color warningIcon = Color(0xFFD9822B);
  static const Color warningDark = Color(0xFF7A5200);
  static const Color warningBg = Color(0xFFFFF3D6);
  static const Color warningBgAlt = Color(0xFFFFF4DB);

  // Shared light palette for the inheritance flow. These names are kept for
  // source compatibility with the reusable widgets, but the screens are
  // intentionally flat and white (no glass/blur treatment).
  static const Color glassVoid = background;
  static const Color glass = Colors.white;
  static const Color glassFrost = light;
  static const Color glassBone = navy;
  static const Color glassBoneDim = medium;
  static const Color glassAqua = medium;
  static const Color glassAmber = warning;
}
