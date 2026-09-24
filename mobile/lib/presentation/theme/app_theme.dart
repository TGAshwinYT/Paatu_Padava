import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Centralized Design System & Theme for Paatu Padava
/// Matching the glowing Neon Violet/Purple (#A855F7) and Cyan (#06B6D4) logo theme.
class AppColors {
  // Deep Dark Backgrounds
  static const Color bgDark = Color(0xFF0D0B14);
  static const Color surfaceDark = Color(0xFF120E1C);
  static const Color surfaceElevated = Color(0xFF1A1626);
  static const Color surfaceBorder = Color(0x1FFFFFFF); // 12% White
  static const Color surfaceBorderHighlight = Color(0x33A855F7); // 20% Violet

  // Neon Logo Accents
  static const Color neonViolet = Color(0xFFA855F7);
  static const Color primaryPurple = Color(0xFF9333EA);
  static const Color deepPurple = Color(0xFF7C3AED);
  static const Color electricCyan = Color(0xFF06B6D4);
  static const Color cyanLight = Color(0xFF22D3EE);

  // Typography Colors
  static const Color textWhite = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF9CA3AF);
  static const Color textMuted = Color(0xFF6B7280);

  // Gradients
  static const LinearGradient neonGradient = LinearGradient(
    colors: [neonViolet, electricCyan],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient purpleGradient = LinearGradient(
    colors: [primaryPurple, deepPurple],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cyanGradient = LinearGradient(
    colors: [electricCyan, cyanLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [surfaceElevated, surfaceDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.bgDark,
      primaryColor: AppColors.neonViolet,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.neonViolet,
        secondary: AppColors.electricCyan,
        surface: AppColors.surfaceDark,
        surfaceContainerHighest: AppColors.surfaceElevated,
        onPrimary: AppColors.textWhite,
        onSecondary: AppColors.bgDark,
        onSurface: AppColors.textWhite,
      ),
      textTheme: GoogleFonts.outfitTextTheme(
        ThemeData(brightness: Brightness.dark).textTheme,
      ).apply(
        bodyColor: AppColors.textWhite,
        displayColor: AppColors.textWhite,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: AppColors.bgDark,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
      ),
      iconTheme: const IconThemeData(
        color: AppColors.textWhite,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceElevated,
        selectedColor: AppColors.neonViolet.withOpacity(0.25),
        secondarySelectedColor: AppColors.electricCyan.withOpacity(0.25),
        labelStyle: const TextStyle(color: AppColors.textWhite, fontSize: 13),
        side: const BorderSide(color: AppColors.surfaceBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceElevated,
        contentTextStyle: const TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.surfaceBorderHighlight),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      useMaterial3: true,
    );
  }
}
