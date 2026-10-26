import 'package:flutter/material.dart';

/// Paird palette, taken from the original sign-in / sign-up screens.
class AppColors {
  AppColors._();

  static const background = Color(0xFF121816); // Dark teal / charcoal
  static const surface = Color(0xFF1A2321);
  static const surfaceRaised = Color(0xFF212C29);
  static const border = Color(0xFF2A3835);
  static const gold = Color(0xFFE2C078); // Elegant gold
  static const goldDeep = Color(0xFFC9A24A);
  static const textPrimary = Color(0xFFF5F5F0);
  static const textLabel = Color(0xFFD1D5DB);
  static const textSecondary = Color(0xFF9CA3AF);
  static const textMuted = Color(0xFF6B7280);
  static const success = Color(0xFF4DB6AC);
  static const error = Color(0xFFEF9A9A);
  static const errorBorder = Color(0xFFC62828);

  static const goldGradient = LinearGradient(
    colors: [gold, goldDeep],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
