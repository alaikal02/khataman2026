import 'package:flutter/material.dart';

class AppTheme {
  // Colors
  static const Color primaryGreen = Color(0xFF2ECC71);
  static const Color darkGreen = Color(0xFF1A8A4A);
  static const Color bgDark = Color(0xFF0D1117);
  static const Color bgCard = Color(0xFF161B22);
  static const Color bgCardLight = Color(0xFF1F2937);
  static const Color textPrimary = Color(0xFFE6EDF3);
  static const Color textSecondary = Color(0xFF8B949E);
  static const Color accentGold = Color(0xFFD4AF37);
  static const Color accentTeal = Color(0xFF00BCD4);

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF2ECC71), Color(0xFF1A8A4A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Dark theme gradient (current bgGradient)
  static const LinearGradient darkBgGradient = LinearGradient(
    colors: [Color(0xFF0D1117), Color(0xFF161B22)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // Light theme gradient
  static const LinearGradient lightBgGradient = LinearGradient(
    colors: [Color(0xFFF5F5F5), Color(0xFFEEEEEE)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgDark,
      fontFamily: 'sans-serif',
      colorScheme: const ColorScheme.dark(
        primary: primaryGreen,
        secondary: accentGold,
        surface: bgCard,
        surfaceContainerHighest: bgCardLight,
        onSurface: textPrimary,
        onSurfaceVariant: textSecondary, // used for secondary text
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: bgDark,
        elevation: 0,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: textPrimary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryGreen,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgCardLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF30363D)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryGreen, width: 1.5),
        ),
        labelStyle: const TextStyle(color: textSecondary),
        hintStyle: const TextStyle(color: textSecondary),
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF5F5F5),
      fontFamily: 'sans-serif',
      colorScheme: const ColorScheme.light(
        primary: primaryGreen,
        secondary: accentGold,
        surface: Colors.white,
        surfaceContainerHighest: Color(0xFFEEEEEE),
        onSurface: Color(0xFF1A1A2E),
        onSurfaceVariant: Color(0xFF757575),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
        titleTextStyle: TextStyle(
          color: Color(0xFF1A1A2E),
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: Color(0xFF1A1A2E)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryGreen,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFEEEEEE),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFDDDDDD)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryGreen, width: 1.5),
        ),
        hintStyle: const TextStyle(color: Colors.grey),
      ),
    );
  }
}