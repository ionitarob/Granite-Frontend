import 'package:flutter/material.dart';

/// Provides a themed color palette for the Igualdad glass panels so the
/// composable widgets can adapt to light and dark modes without duplicating
/// raw color constants.
class FormPalette {
  final bool isDark;
  final Color panelGradientStart;
  final Color panelGradientEnd;
  final Color panelBorder;
  final Color panelShadow;
  final Color textPrimary;
  final Color textMuted;
  final Color divider;
  final Color fieldFill;
  final Color fieldBorder;
  final Color fieldFocusedBorder;
  final Color fieldLabel;
  final Color fieldIcon;
  final Color dropdownBackground;
  final Color toggleBorder;
  final Color segmentedSelectedBackground;
  final Color segmentedUnselectedBackground;
  final Color segmentedSelectedForeground;
  final Color segmentedUnselectedForeground;
  final Color segmentedBorder;
  final Color chipBackground;
  final Color chipBorder;
  final Color chipSelectedBackground;
  final Color chipSelectedForeground;
  final Color chipUnselectedForeground;
  final Color infoBackground;
  final Color infoBorder;
  final Color neutralCardBackground;
  final Color neutralCardBorder;
  final Color warningBackground;
  final Color warningBorder;
  final Color placeholderBackground;

  const FormPalette({
    required this.isDark,
    required this.panelGradientStart,
    required this.panelGradientEnd,
    required this.panelBorder,
    required this.panelShadow,
    required this.textPrimary,
    required this.textMuted,
    required this.divider,
    required this.fieldFill,
    required this.fieldBorder,
    required this.fieldFocusedBorder,
    required this.fieldLabel,
    required this.fieldIcon,
    required this.dropdownBackground,
    required this.toggleBorder,
    required this.segmentedSelectedBackground,
    required this.segmentedUnselectedBackground,
    required this.segmentedSelectedForeground,
    required this.segmentedUnselectedForeground,
    required this.segmentedBorder,
    required this.chipBackground,
    required this.chipBorder,
    required this.chipSelectedBackground,
    required this.chipSelectedForeground,
    required this.chipUnselectedForeground,
    required this.infoBackground,
    required this.infoBorder,
    required this.neutralCardBackground,
    required this.neutralCardBorder,
    required this.warningBackground,
    required this.warningBorder,
    required this.placeholderBackground,
  });

  factory FormPalette.fromTheme(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final scheme = theme.colorScheme;

    Color blend(Color overlay, Color base) => Color.alphaBlend(overlay, base);

  final panelGradientStart = blend(
    Colors.white.withValues(alpha: isDark ? .05 : .6),
      scheme.surface,
    );
    final panelGradientEnd = blend(
    isDark
      ? Colors.black.withValues(alpha: .2)
      : Colors.white.withValues(alpha: .4),
    scheme.surfaceContainerHighest,
    );
    final panelBorder = isDark
    ? Colors.white.withValues(alpha: .16)
    : scheme.outline.withValues(alpha: .18);
    final panelShadow = isDark
    ? Colors.black.withValues(alpha: .5)
    : Colors.black.withValues(alpha: .12);
    final textPrimary = isDark
    ? Colors.white.withValues(alpha: .95)
    : scheme.onSurface.withValues(alpha: .95);
    final textMuted = isDark
    ? Colors.white.withValues(alpha: .72)
    : scheme.onSurfaceVariant.withValues(alpha: .85);
    final divider = isDark
    ? Colors.white.withValues(alpha: .14)
    : scheme.outline.withValues(alpha: .2);
    final fieldFill = isDark
    ? scheme.surfaceContainerHighest.withValues(alpha: .28)
    : Colors.white.withValues(alpha: .9);
    final fieldBorder = isDark
    ? Colors.white.withValues(alpha: .2)
    : scheme.outline.withValues(alpha: .18);
  final fieldFocusedBorder =
    scheme.primary.withValues(alpha: isDark ? .9 : .8);
    final fieldLabel = textMuted;
    final fieldIcon = isDark
    ? Colors.white.withValues(alpha: .78)
    : scheme.onSurfaceVariant.withValues(alpha: .8);
    final dropdownBackground = isDark
    ? scheme.surfaceContainerHighest.withValues(alpha: .95)
        : Colors.white;
    final toggleBorder = isDark
    ? Colors.white.withValues(alpha: .35)
    : scheme.outline.withValues(alpha: .28);
    final segmentedSelectedBackground =
    scheme.primary.withValues(alpha: isDark ? .32 : .2);
    final segmentedUnselectedBackground = blend(
    isDark
      ? Colors.black.withValues(alpha: .3)
      : Colors.white.withValues(alpha: .6),
    scheme.surfaceContainerHighest,
    );
    final segmentedSelectedForeground = scheme.onPrimary;
    final segmentedUnselectedForeground = textPrimary;
    final segmentedBorder = isDark
        ? Colors.white.withValues(alpha: .24)
        : scheme.outline.withValues(alpha: .18);
    final chipBackground = blend(
      isDark
          ? Colors.black.withValues(alpha: .25)
          : Colors.white.withValues(alpha: .6),
      scheme.surfaceContainerHighest,
    );
    final chipBorder = isDark
        ? Colors.white.withValues(alpha: .18)
        : scheme.outline.withValues(alpha: .14);
    final chipSelectedBackground =
        scheme.primary.withValues(alpha: isDark ? .45 : .35);
    final chipSelectedForeground = scheme.onPrimary;
    final chipUnselectedForeground = textPrimary;
    final infoBackground = blend(
      isDark
          ? Colors.black.withValues(alpha: .35)
          : Colors.white.withValues(alpha: .6),
      scheme.surfaceContainerHighest,
    );
    final infoBorder = isDark
        ? Colors.white.withValues(alpha: .2)
        : scheme.outline.withValues(alpha: .18);
    final neutralCardBackground = blend(
      isDark
          ? Colors.black.withValues(alpha: .3)
          : Colors.white.withValues(alpha: .65),
      scheme.surfaceContainerHighest,
    );
    final neutralCardBorder = infoBorder;
    final warningBackground = blend(
      isDark
          ? Colors.black.withValues(alpha: .36)
          : Colors.white.withValues(alpha: .8),
      scheme.errorContainer,
    );
    final warningBorder =
        scheme.error.withValues(alpha: isDark ? .45 : .4);
    final placeholderBackground = scheme.surfaceContainerHighest
        .withValues(alpha: isDark ? .25 : .5);

    return FormPalette(
      isDark: isDark,
      panelGradientStart: panelGradientStart,
      panelGradientEnd: panelGradientEnd,
      panelBorder: panelBorder,
      panelShadow: panelShadow,
      textPrimary: textPrimary,
      textMuted: textMuted,
      divider: divider,
      fieldFill: fieldFill,
      fieldBorder: fieldBorder,
      fieldFocusedBorder: fieldFocusedBorder,
      fieldLabel: fieldLabel,
      fieldIcon: fieldIcon,
      dropdownBackground: dropdownBackground,
      toggleBorder: toggleBorder,
      segmentedSelectedBackground: segmentedSelectedBackground,
      segmentedUnselectedBackground: segmentedUnselectedBackground,
      segmentedSelectedForeground: segmentedSelectedForeground,
      segmentedUnselectedForeground: segmentedUnselectedForeground,
      segmentedBorder: segmentedBorder,
      chipBackground: chipBackground,
      chipBorder: chipBorder,
      chipSelectedBackground: chipSelectedBackground,
      chipSelectedForeground: chipSelectedForeground,
      chipUnselectedForeground: chipUnselectedForeground,
      infoBackground: infoBackground,
      infoBorder: infoBorder,
      neutralCardBackground: neutralCardBackground,
      neutralCardBorder: neutralCardBorder,
      warningBackground: warningBackground,
      warningBorder: warningBorder,
      placeholderBackground: placeholderBackground,
    );
  }
}
