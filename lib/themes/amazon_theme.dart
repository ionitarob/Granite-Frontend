import 'package:flutter/material.dart';

/// A small theme wrapper for Amazon screens.
///
/// - Forces a brand orange primary color for Amazon-related screens.
/// - When the app brightness is dark, sets a near-black scaffold background
///   so text and controls remain legible in night mode.
class AmazonTheme extends StatelessWidget {
  final Widget child;
  const AmazonTheme({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final isDark = base.brightness == Brightness.dark;

    // Amazon/orange brand color. Adjust shade if you prefer a different tone.
    final Color amazonPrimary = Colors.orange.shade700;

    final ColorScheme cs = base.colorScheme.copyWith(
      primary: amazonPrimary,
      onPrimary: isDark ? Colors.black : Colors.white,
    );

    final ThemeData theme = base.copyWith(
      colorScheme: cs,
      // Make the scaffold background dark in night mode so text is readable.
      scaffoldBackgroundColor: isDark
          ? const Color(0xFF0B0B0D)
          : base.scaffoldBackgroundColor,
      // AppBar tint: use the amazonPrimary but keep elevation and other defaults.
      appBarTheme: base.appBarTheme.copyWith(backgroundColor: amazonPrimary),
      // Card color: keep contrast depending on brightness
      cardColor: isDark ? const Color(0xFF111213) : Colors.white,
    );

    return Theme(data: theme, child: child);
  }
}
