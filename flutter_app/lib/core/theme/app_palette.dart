import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Every colour a widget is allowed to use, resolved per brightness.
///
/// [AppColors] holds the light values as `const`s — they cannot change at
/// runtime, which is exactly why widgets must not read them directly: a
/// `const` white card stays white in dark mode. Widgets read this palette
/// instead (`context.palette.surface`), the palette is registered in
/// [ThemeData.extensions], and the switch between the two instances is
/// Flutter's own brightness machinery.
///
/// Field names match [AppColors] one-for-one so a migration is a pure rename.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.primary,
    required this.primaryLight,
    required this.primaryDark,
    required this.coralGlow,
    required this.purpleGlow,
    required this.amberGlow,
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.glassWhite,
    required this.glassCard,
    required this.glassBorder,
    required this.glassBorderSubtle,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.tagBg,
    required this.tagText,
    required this.cardBorder,
    required this.divider,
    required this.success,
    required this.danger,
  });

  // Brand Radiant Accents
  final Color primary;
  final Color primaryLight;
  final Color primaryDark;

  // Luxury Ambient Gradients
  final Color coralGlow;
  final Color purpleGlow;
  final Color amberGlow;

  // Backgrounds & Canvas
  final Color background;
  final Color surface;
  final Color surfaceElevated;

  // Glass Tint Layers
  final Color glassWhite;
  final Color glassCard;
  final Color glassBorder;
  final Color glassBorderSubtle;

  // Text Colors
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  // Card Accents
  final Color tagBg;
  final Color tagText;
  final Color cardBorder;
  final Color divider;

  // Status Accents
  final Color success;
  final Color danger;

  /// The palette the app has always shipped with — values come from
  /// [AppColors] so there is one place to edit a brand colour.
  static const AppPalette light = AppPalette(
    primary: AppColors.primary,
    primaryLight: AppColors.primaryLight,
    primaryDark: AppColors.primaryDark,
    coralGlow: AppColors.coralGlow,
    purpleGlow: AppColors.purpleGlow,
    amberGlow: AppColors.amberGlow,
    background: AppColors.background,
    surface: AppColors.surface,
    surfaceElevated: AppColors.surfaceElevated,
    glassWhite: AppColors.glassWhite,
    glassCard: AppColors.glassCard,
    glassBorder: AppColors.glassBorder,
    glassBorderSubtle: AppColors.glassBorderSubtle,
    textPrimary: AppColors.textPrimary,
    textSecondary: AppColors.textSecondary,
    textMuted: AppColors.textMuted,
    tagBg: AppColors.tagBg,
    tagText: AppColors.tagText,
    cardBorder: AppColors.cardBorder,
    divider: AppColors.divider,
    success: AppColors.success,
    danger: AppColors.danger,
  );

  /// Dark counterpart. Same hue family as the brand, lifted off the canvas:
  /// the coral is brightened (the light-mode coral loses contrast on a dark
  /// background), surfaces are warm-tinted charcoals rather than pure greys so
  /// the light theme's warmth survives, and the white glass layers become
  /// faint light-tinted glass.
  static const AppPalette dark = AppPalette(
    primary: Color(0xFFFF6B47),
    primaryLight: Color(0xFF2A1B16),
    primaryDark: Color(0xFFE04420),
    coralGlow: coralGlowDark,
    purpleGlow: purpleGlowDark,
    amberGlow: amberGlowDark,
    background: Color(0xFF0F1115),
    surface: Color(0xFF171A21),
    surfaceElevated: Color(0xFF1E232B),
    glassWhite: Color(0xF2161A20),
    glassCard: Color(0xE8171B22),
    glassBorder: Color(0xCC2C323E),
    glassBorderSubtle: Color(0x1FFFFFFF),
    textPrimary: Color(0xFFF3F5F9),
    textSecondary: Color(0xFFA9B1BE),
    textMuted: Color(0xFF737D8C),
    tagBg: Color(0xFF232833),
    tagText: Color(0xFFCBD3DF),
    cardBorder: Color(0xFF272D38),
    divider: Color(0xFF232833),
    success: Color(0xFF34D399),
    danger: Color(0xFFFF6B6B),
  );

  // Glows are translucent brand tints; on a dark canvas they need a little
  // more presence to read as ambient light instead of mud.
  static const Color coralGlowDark = Color(0x40FF5B37);
  static const Color purpleGlowDark = Color(0x33833AB4);
  static const Color amberGlowDark = Color(0x2EF59E0B);

  /// True when this palette is the dark one — for the handful of places where
  /// a blend factor or an image scrim has to differ, not for picking colours.
  bool get isDark => background.computeLuminance() < 0.2;

  @override
  AppPalette copyWith({
    Color? primary,
    Color? primaryLight,
    Color? primaryDark,
    Color? coralGlow,
    Color? purpleGlow,
    Color? amberGlow,
    Color? background,
    Color? surface,
    Color? surfaceElevated,
    Color? glassWhite,
    Color? glassCard,
    Color? glassBorder,
    Color? glassBorderSubtle,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? tagBg,
    Color? tagText,
    Color? cardBorder,
    Color? divider,
    Color? success,
    Color? danger,
  }) {
    return AppPalette(
      primary: primary ?? this.primary,
      primaryLight: primaryLight ?? this.primaryLight,
      primaryDark: primaryDark ?? this.primaryDark,
      coralGlow: coralGlow ?? this.coralGlow,
      purpleGlow: purpleGlow ?? this.purpleGlow,
      amberGlow: amberGlow ?? this.amberGlow,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      glassWhite: glassWhite ?? this.glassWhite,
      glassCard: glassCard ?? this.glassCard,
      glassBorder: glassBorder ?? this.glassBorder,
      glassBorderSubtle: glassBorderSubtle ?? this.glassBorderSubtle,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      tagBg: tagBg ?? this.tagBg,
      tagText: tagText ?? this.tagText,
      cardBorder: cardBorder ?? this.cardBorder,
      divider: divider ?? this.divider,
      success: success ?? this.success,
      danger: danger ?? this.danger,
    );
  }

  @override
  AppPalette lerp(covariant AppPalette? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      primary: mix(primary, other.primary),
      primaryLight: mix(primaryLight, other.primaryLight),
      primaryDark: mix(primaryDark, other.primaryDark),
      coralGlow: mix(coralGlow, other.coralGlow),
      purpleGlow: mix(purpleGlow, other.purpleGlow),
      amberGlow: mix(amberGlow, other.amberGlow),
      background: mix(background, other.background),
      surface: mix(surface, other.surface),
      surfaceElevated: mix(surfaceElevated, other.surfaceElevated),
      glassWhite: mix(glassWhite, other.glassWhite),
      glassCard: mix(glassCard, other.glassCard),
      glassBorder: mix(glassBorder, other.glassBorder),
      glassBorderSubtle: mix(glassBorderSubtle, other.glassBorderSubtle),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      textMuted: mix(textMuted, other.textMuted),
      tagBg: mix(tagBg, other.tagBg),
      tagText: mix(tagText, other.tagText),
      cardBorder: mix(cardBorder, other.cardBorder),
      divider: mix(divider, other.divider),
      success: mix(success, other.success),
      danger: mix(danger, other.danger),
    );
  }
}

/// `context.palette.surface` — the one-liner widgets should use.
///
/// Falls back to the light palette if the extension is missing (a widget
/// pumped in a test without [AppTheme]), so a half-configured theme degrades
/// to today's colours instead of throwing.
extension AppPaletteContext on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.light;
}
