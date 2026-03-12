import 'package:flutter/material.dart';
import 'dart:ui';

class SentinelTheme {
  // Colors
  static const Color bgDark = Color(0xFF050505); // Deep Black
  static const Color bgPanel = Color(0xFF121212); // Panel Black

  static const Color primary = Color(0xFF00E5FF); // Cyan Neon
  static const Color secondary = Color(0xFF2979FF); // Blue Neon
  static const Color success = Color(0xFF00E676); // Green Neon
  static const Color warning = Color(0xFFFFAB00); // Amber Neon
  static const Color error = Color(0xFFFF1744); // Red Neon

  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xB3FFFFFF); // 70% White
  static const Color textDisabled = Color(0x62FFFFFF); // 38% White

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF00E5FF), Color(0xFF2979FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const RadialGradient backgroundGradient = RadialGradient(
    center: Alignment.center,
    radius: 1.5,
    colors: [
      Color(0xFF1A1A2E), // Deep Blue-Black center
      Color(0xFF050505), // Black edges
    ],
  );

  // Decorations
  static BoxDecoration glassDecoration({
    double opacity = 0.1,
    double borderRadius = 12,
    bool border = true,
    Color? borderColor,
  }) {
    return BoxDecoration(
      color: Colors.white.withOpacity(opacity),
      borderRadius: BorderRadius.circular(borderRadius),
      border: border
          ? Border.all(
              color: borderColor ?? Colors.white.withOpacity(0.1),
              width: 1,
            )
          : null,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.2),
          blurRadius: 16,
          spreadRadius: 2,
        ),
      ],
    );
  }

  static BoxDecoration glowDecoration({
    required Color color,
    double opacity = 0.1,
    double glowOpacity = 0.4,
    double borderRadius = 8,
  }) {
    return BoxDecoration(
      color: color.withOpacity(opacity),
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: color.withOpacity(0.5), width: 1),
      boxShadow: [
        BoxShadow(
          color: color.withOpacity(glowOpacity),
          blurRadius: 8,
          spreadRadius: 0,
        ),
      ],
    );
  }

  // Text Styles
  static const TextStyle header = TextStyle(
    color: textPrimary,
    fontSize: 18,
    fontWeight: FontWeight.bold,
    letterSpacing: 1.2,
    fontFamily: 'Segoe UI', // Default Windows font usually looks good
  );

  static const TextStyle subHeader = TextStyle(
    color: textSecondary,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
  );

  static const TextStyle body = TextStyle(
    color: textSecondary,
    fontSize: 13,
    height: 1.4,
  );

  static const TextStyle label = TextStyle(
    color: textSecondary,
    fontSize: 11,
    fontWeight: FontWeight.bold,
    letterSpacing: 0.5,
  );

  static const TextStyle mono = TextStyle(
    color: textSecondary,
    fontSize: 12,
    fontFamily: 'Consolas', // Monospace for IPs
    height: 1.2,
  );
}
