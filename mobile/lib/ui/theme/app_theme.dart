import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/settings_manager.dart';

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
  static ThemeData get darkTheme => getTheme(SettingsManager.themeMode);

  static ThemeData getTheme(String mode) {
    final bool isAmoled = mode == 'amoled';
    final Color bgColor = isAmoled ? Colors.black : const Color(0xFF0A0E1A);
    final Color surfaceColor = isAmoled ? const Color(0xFF0D0D0D) : const Color(0xFF0F172A);
    final Color surfaceElevated = isAmoled ? const Color(0xFF171717) : const Color(0xFF1E293B);

    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgColor,
      primaryColor: AppColors.neonViolet,
      colorScheme: ColorScheme.dark(
        primary: AppColors.neonViolet,
        secondary: AppColors.electricCyan,
        surface: surfaceColor,
        surfaceContainerHighest: surfaceElevated,
        onPrimary: AppColors.textWhite,
        onSecondary: bgColor,
        onSurface: AppColors.textWhite,
      ),
      textTheme: GoogleFonts.outfitTextTheme(
        ThemeData(brightness: Brightness.dark).textTheme,
      ).apply(
        bodyColor: AppColors.textWhite,
        displayColor: AppColors.textWhite,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: bgColor,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
      ),
      iconTheme: const IconThemeData(
        color: AppColors.textWhite,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceElevated,
        selectedColor: AppColors.neonViolet.withValues(alpha: 0.25),
        secondarySelectedColor: AppColors.electricCyan.withValues(alpha: 0.25),
        labelStyle: const TextStyle(color: AppColors.textWhite, fontSize: 13),
        side: const BorderSide(color: AppColors.surfaceBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceElevated,
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
