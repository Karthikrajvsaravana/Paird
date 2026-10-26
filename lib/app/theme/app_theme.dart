import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// App-wide theme matching the existing Paird visual identity:
/// dark green surfaces, gold accents, Instrument Serif + Plus Jakarta Sans.
class AppTheme {
  AppTheme._();

  static TextStyle serif({double size = 28, Color color = AppColors.textPrimary, FontWeight? weight}) =>
      GoogleFonts.instrumentSerif(fontSize: size, color: color, fontWeight: weight);

  static TextStyle sans({
    double size = 14,
    Color color = AppColors.textPrimary,
    FontWeight weight = FontWeight.w400,
    double? height,
  }) =>
      GoogleFonts.plusJakartaSans(fontSize: size, color: color, fontWeight: weight, height: height);

  static OutlineInputBorder _border(Color color, [double width = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );

  static ThemeData get dark {
    final base = ThemeData(useMaterial3: true, brightness: Brightness.dark);
    // google_fonts' TextTheme helpers target package:material_ui, so apply
    // the font family to Flutter's own TextTheme instead.
    final textTheme = base.textTheme.apply(
      fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    );
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.gold,
        onPrimary: AppColors.background,
        secondary: AppColors.goldDeep,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        error: AppColors.error,
      ),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: serif(size: 26),
        iconTheme: const IconThemeData(color: AppColors.gold),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        hintStyle: sans(color: Colors.grey.shade600),
        labelStyle: sans(color: AppColors.textLabel, size: 13),
        border: _border(AppColors.border),
        enabledBorder: _border(AppColors.border),
        focusedBorder: _border(AppColors.goldDeep, 1.5),
        errorBorder: _border(AppColors.errorBorder),
        focusedErrorBorder: _border(AppColors.errorBorder, 1.5),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.gold.withValues(alpha: 0.18),
        side: const BorderSide(color: AppColors.border),
        labelStyle: sans(size: 13, color: AppColors.textLabel),
        checkmarkColor: AppColors.gold,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.gold : AppColors.textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.goldDeep.withValues(alpha: 0.4) : AppColors.border,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.gold, textStyle: sans(weight: FontWeight.w600)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          backgroundColor: AppColors.surface,
          side: const BorderSide(color: AppColors.border),
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: sans(weight: FontWeight.w600),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.gold.withValues(alpha: 0.18),
        labelTextStyle: WidgetStatePropertyAll(sans(size: 11, color: AppColors.textLabel, weight: FontWeight.w500)),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? AppColors.gold : AppColors.textSecondary),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceRaised,
        contentTextStyle: sans(color: AppColors.textPrimary),
        behavior: SnackBarBehavior.floating,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.gold),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        titleTextStyle: serif(size: 24),
        contentTextStyle: sans(color: AppColors.textLabel),
      ),
    );
  }
}
