import 'package:flutter/material.dart';
import 'colors.dart';

class SoloDeskTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: SoloDeskColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: SoloDeskColors.primary,
        surface: SoloDeskColors.surface,
        onSurface: SoloDeskColors.ink,
        primary: SoloDeskColors.primary,
      ),
      fontFamily: 'Segoe UI',
      dividerTheme: const DividerThemeData(
        color: SoloDeskColors.borderLine,
        thickness: 1,
        space: 1,
      ),
      cardTheme: const CardThemeData(
        color: SoloDeskColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          side: BorderSide(color: SoloDeskColors.borderLine),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: SoloDeskColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: SoloDeskColors.borderLine),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: SoloDeskColors.borderLine),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: SoloDeskColors.primaryLight, width: 1.5),
        ),
        hintStyle: const TextStyle(
          color: SoloDeskColors.muted,
          fontSize: 13,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: SoloDeskColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: SoloDeskColors.ink,
          side: const BorderSide(color: SoloDeskColors.borderLine),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontSize: 27,
          fontWeight: FontWeight.w800,
          color: SoloDeskColors.ink,
          letterSpacing: -0.9,
        ),
        titleLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: SoloDeskColors.ink,
        ),
        titleMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: SoloDeskColors.ink,
        ),
        bodyMedium: TextStyle(
          fontSize: 13,
          color: SoloDeskColors.ink,
          height: 1.45,
        ),
        bodySmall: TextStyle(
          fontSize: 11,
          color: SoloDeskColors.muted,
        ),
        labelSmall: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
          color: SoloDeskColors.primary,
        ),
      ),
    );
  }
}
