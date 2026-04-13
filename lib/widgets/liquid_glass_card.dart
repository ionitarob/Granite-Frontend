import 'dart:ui';
import 'package:flutter/material.dart';

class LiquidGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final double blur;
  final bool elevated;
  final VoidCallback? onTap;
  final Color? tint; // opcional: forzar tinte
  final Color? borderColor;

  const LiquidGlassCard({
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = 18,
    this.blur = 18,
    this.elevated = true,
    this.onTap,
    this.tint,
    this.borderColor,
    super.key,
  });

  @override
  Widget build(BuildContext ctx) {
    final theme = Theme.of(ctx);
    final isDark = theme.brightness == Brightness.dark;

    final base =
        tint ??
        (isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.white.withValues(alpha: 0.72));

    final border = borderColor ?? (isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.06));

    final shadow = isDark
        ? Colors.black.withValues(alpha: 0.45)
        : Colors.black.withValues(alpha: 0.12);

    final content = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: border, width: 1),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                base,
                base.withValues(alpha: isDark ? 0.03 : 0.52),
              ],
            ),
            boxShadow: elevated
                ? [
                    BoxShadow(
                      color: shadow,
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    )
                  ]
                : null,
          ),
          child: child,
        ),
      ),
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: content,
      );
    }

    return content;
  }
}
