import 'package:flutter/material.dart';

import '../theme/colors.dart';

/// Shared flat surfaces for the light inheritance screens.
const glassCardGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Colors.white, Colors.white],
);

const glassHeroGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Colors.white, Colors.white],
);

/// A shared white card used across the inheritance flow.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 14,
    this.gradient = glassCardGradient,
    this.boxShadow,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Gradient gradient;
  final List<BoxShadow>? boxShadow;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      gradient: gradient,
      border: Border.all(color: SatraColors.glassFrost, width: 1),
      boxShadow: boxShadow,
    );
    if (onTap == null) {
      return Container(
        padding: padding,
        decoration: decoration,
        child: child,
      );
    }
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        highlightColor: SatraColors.glassAqua.withValues(alpha: 0.08),
        splashColor: SatraColors.glassAqua.withValues(alpha: 0.12),
        child: Container(
          padding: padding,
          decoration: decoration,
          child: child,
        ),
      ),
    );
  }
}

/// Section card with a titled header and an accent-tinted icon chip.
class GlassSection extends StatelessWidget {
  const GlassSection({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.accent = SatraColors.glassBone,
    this.padding = const EdgeInsets.all(16),
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Color accent;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => GlassCard(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GlassIconChip(icon: icon, accent: accent, size: 34),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    color: SatraColors.glassBone,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      );
}

/// A small accent-tinted icon container used inside cards.
class GlassIconChip extends StatelessWidget {
  const GlassIconChip({
    super.key,
    required this.icon,
    this.accent = SatraColors.glassAqua,
    this.size = 34,
    this.iconSize,
    this.borderRadius,
  });

  final IconData icon;
  final Color accent;
  final double size;
  final double? iconSize;
  final double? borderRadius;

  @override
  Widget build(BuildContext context) {
    final r = borderRadius ?? (size * 0.26);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(r),
        border: Border.all(color: accent.withValues(alpha: 0.35), width: 1),
      ),
      child: Icon(icon, color: accent, size: iconSize ?? size * 0.52),
    );
  }
}

/// Shared header for the inheritance screens.
class GlassHeader extends StatelessWidget {
  const GlassHeader({
    super.key,
    required this.title,
    this.onBack,
    this.trailing = const SizedBox(width: 48),
  });

  final String title;
  final VoidCallback? onBack;
  final Widget trailing;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Semantics(
            label: 'Voltar',
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: SatraColors.glassBone),
              onPressed: onBack ?? () => Navigator.of(context).maybePop(),
            ),
          ),
          const Spacer(),
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: SatraColors.glassBoneDim,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.5,
            ),
          ),
          const Spacer(),
          trailing,
        ],
      );
}

/// A filled pill/badge carrying a status word and a colored dot. Used
/// to label the state of something (active, pending, grace…) inside a
/// glass card without raising the visual weight of a full button.
class GlassStatusPill extends StatelessWidget {
  const GlassStatusPill({
    super.key,
    required this.label,
    required this.accent,
    this.showDot = true,
  });

  final String label;
  final Color accent;
  final bool showDot;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accent.withValues(alpha: 0.4), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showDot) ...[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: accent,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
}

/// Shared [InputDecoration] for every text field on a glass screen.
/// Keeps the glass tokens (frost border, aqua focus, dim labels) in one
/// place so all inheritance fields feel like the same surface.
InputDecoration glassInputDecoration({
  String? labelText,
  String? hintText,
  String? helperText,
  String? suffixText,
  Widget? prefixIcon,
  Widget? suffixIcon,
  bool alignLabelWithHint = false,
  TextStyle? labelStyle,
  TextStyle? hintStyle,
}) =>
    InputDecoration(
      labelText: labelText,
      hintText: hintText,
      helperText: helperText,
      suffixText: suffixText,
      alignLabelWithHint: alignLabelWithHint,
      filled: true,
      fillColor: SatraColors.glass,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      labelStyle: labelStyle ?? const TextStyle(color: SatraColors.glassBoneDim),
      hintStyle: hintStyle ?? const TextStyle(color: SatraColors.glassBoneDim),
      helperStyle: const TextStyle(color: SatraColors.glassBoneDim, fontSize: 12),
      suffixStyle: const TextStyle(color: SatraColors.glassBoneDim),
      counterStyle: const TextStyle(color: SatraColors.glassBoneDim),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: SatraColors.glassFrost),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: SatraColors.glassFrost),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: SatraColors.glassAqua, width: 1.5),
      ),
    );

/// Primary call-to-action button on glass screens: aqua surface, void
/// text — the single luminous accent doing the heavy lifting.
FilledButton glassPrimaryButton({
  required VoidCallback? onPressed,
  required Widget child,
  EdgeInsetsGeometry? padding =
      const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
  double radius = 12,
  bool disabled = false,
}) =>
    FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: SatraColors.glassAqua,
        foregroundColor: SatraColors.glassVoid,
        disabledBackgroundColor:
            SatraColors.glassAqua.withValues(alpha: 0.25),
        disabledForegroundColor: SatraColors.glassBoneDim,
        padding: padding,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      ),
      child: child,
    );

/// Secondary button on glass screens: outlined in aqua (translucent), aqua
/// text — the same accent as the primary button but as a quieter affordance.
OutlinedButton glassSecondaryButton({
  required VoidCallback? onPressed,
  required Widget child,
  EdgeInsetsGeometry? padding =
      const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
  double radius = 12,
}) =>
    OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: SatraColors.glassAqua,
        backgroundColor: Colors.transparent,
        side: BorderSide(color: SatraColors.glassAqua.withValues(alpha: 0.5)),
        padding: padding,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      ),
      child: child,
    );
