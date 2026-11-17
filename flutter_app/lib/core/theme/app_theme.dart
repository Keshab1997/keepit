import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_palette.dart';

class AppTheme {
  static ThemeData get lightTheme => _build(Brightness.light, AppPalette.light);

  static ThemeData get darkTheme => _build(Brightness.dark, AppPalette.dark);

  static ThemeData _build(Brightness brightness, AppPalette palette) {
    final isDark = brightness == Brightness.dark;
    final baseTextTheme =
        isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: palette.background,
      primaryColor: palette.primary,
      fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
      // material_ui ships its own TextTheme, which google_fonts (still typed
      // against the framework one) cannot fill directly. Starting from the
      // base theme and applying the family is equivalent to
      // GoogleFonts.plusJakartaSansTextTheme(baseTextTheme), and keeps every
      // text style styled instead of just one.
      textTheme: baseTextTheme.apply(
        fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
        bodyColor: palette.textPrimary,
        displayColor: palette.textPrimary,
      ),
      colorScheme: ColorScheme.fromSeed(
        brightness: brightness,
        seedColor: palette.primary,
        primary: palette.primary,
        surface: palette.surface,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        foregroundColor: palette.textPrimary,
        iconTheme: IconThemeData(color: palette.textPrimary),
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        color: palette.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: palette.cardBorder, width: 0.8),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surfaceElevated,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.surface,
      ),
      dividerTheme: DividerThemeData(
        color: palette.divider,
      ),
      extensions: <ThemeExtension<dynamic>>[palette],
    );
  }
}
