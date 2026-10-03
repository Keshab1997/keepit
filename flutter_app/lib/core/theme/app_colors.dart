import 'package:flutter/material.dart';

/// The light palette's literal values.
///
/// Widgets should **not** read these: a `const` colour cannot change with the
/// brightness, so a direct reference renders light-mode colours on a dark
/// screen. Read `context.palette.x` instead — [AppPalette.light] is built from
/// these constants, [AppPalette.dark] holds the dark counterparts, and the
/// palette in the active theme is what a widget sees. Edit a brand colour here
/// and both themes pick it up.
class AppColors {
  // Brand Radiant Accents
  static const Color primary = Color(
    0xFFFF5B37,
  ); // Warm Coral Orange (mymind signature)
  static const Color primaryLight = Color(0xFFFFECE7);
  static const Color primaryDark = Color(0xFFE04420);

  // Luxury Ambient Gradients
  static const Color coralGlow = Color(0x33FF5B37);
  static const Color purpleGlow = Color(0x28833AB4);
  static const Color amberGlow = Color(0x24F59E0B);

  // Backgrounds & Canvas
  static const Color background = Color(
    0xFFF7F8FA,
  ); // Ultra-clean subtle warm white
  static const Color surface = Colors.white;
  static const Color surfaceElevated = Color(0xFFFFFFFF);

  // Glass Tint Layers
  static const Color glassWhite = Color(0xF2FFFFFF);
  static const Color glassCard = Color(0xE8FFFFFF);
  static const Color glassBorder = Color(0xCCFFFFFF);
  static const Color glassBorderSubtle = Color(0x66FFFFFF);

  // Text Colors
  static const Color textPrimary = Color(0xFF14171F); // Deep Charcoal Slate
  static const Color textSecondary = Color(0xFF6B7280); // Neutral Steel Grey
  static const Color textMuted = Color(0xFF9CA3AF);

  // Card Accents
  static const Color tagBg = Color(0xFFF1F3F6);
  static const Color tagText = Color(0xFF374151);
  static const Color cardBorder = Color(0xFFE5E7EB);

  /// Faint rim used on light cards (20% of the light border).
  static const Color cardBorderSoft = Color(0x33E5E7EB);
  static const Color divider = Color(0xFFF0F1F4);

  // Status Accents
  static const Color success = Color(0xFF10B981);
  static const Color danger = Color(0xFFFF3B30);
}
