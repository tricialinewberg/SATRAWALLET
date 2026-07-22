import 'package:flutter/material.dart';

import '../theme/colors.dart';

/// Wraps [child] in a [Scrollbar] with a permanently visible thumb (Flutter's
/// default only appears while actively dragging) themed with the app's
/// medium-blue accent, so every scrollable screen gets the same scroll
/// affordance instead of each one styling its own.
class AppScrollbar extends StatelessWidget {
  final Widget child;
  final ScrollController? controller;

  const AppScrollbar({super.key, required this.child, this.controller});

  @override
  Widget build(BuildContext context) {
    return ScrollbarTheme(
      data: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(SatraColors.medium),
        thickness: WidgetStateProperty.all(6),
        radius: const Radius.circular(8),
      ),
      child: Scrollbar(
        controller: controller,
        thumbVisibility: true,
        child: child,
      ),
    );
  }
}
