import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Identité graphique MYBUDGET — maquette « MyBudget ».
/// Palette bleue : #38BDF8 → #0284C7, fond #F2FAFF, encre #0B3552.
abstract final class AppColors {
  static const deepGreen = Color(0xFF0284C7);
  static const deepGreenDark = Color(0xFF0369A1);
  static const deepGreenLight = Color(0xFF38BDF8);
  static const sky = Color(0xFF38BDF8);
  static const soft = Color(0xFFBAE6FD);
  static const offWhite = Color(0xFFF2FAFF);
  static const cardWhite = Colors.white;
  static const expenseRed = Color(0xFFE11D48);
  static const incomeGreen = Color(0xFF059669);
  static const textDark = Color(0xFF0B3552);
  static const textMuted = Color(0xFF5B7C94);
  static const line = Color(0xFFE0EFF8);
  static const warning = Color(0xFFF59E0B);

  static const darkBg = Color(0xFF071A28);
  static const darkCard = Color(0xFF0F2A3D);
  static const darkInk = Color(0xFFE6F4FF);
  static const darkMuted = Color(0xFF8FB0C6);
  static const darkLine = Color(0xFF1B3D55);
  static const darkSoft = Color(0xFF134563);
}

abstract final class AppTheme {
  static const fontFamily = 'Inter';

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final seed = isDark ? AppColors.deepGreenLight : AppColors.deepGreen;

    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness).copyWith(
      primary: isDark ? AppColors.deepGreenLight : AppColors.deepGreen,
      onPrimary: isDark ? const Color(0xFF05202F) : Colors.white,
      secondary: AppColors.sky,
      onSecondary: isDark ? const Color(0xFF05202F) : AppColors.textDark,
      surface: isDark ? AppColors.darkCard : Colors.white,
      onSurface: isDark ? AppColors.darkInk : AppColors.textDark,
      onSurfaceVariant: isDark ? AppColors.darkMuted : AppColors.textMuted,
      outline: isDark ? AppColors.darkLine : AppColors.line,
      outlineVariant: isDark ? AppColors.darkLine : AppColors.line,
      error: isDark ? const Color(0xFFFB7185) : AppColors.expenseRed,
      onError: Colors.white,
      tertiary: isDark ? const Color(0xFF34D399) : AppColors.incomeGreen,
      onTertiary: Colors.white,
    );

    final bg = isDark ? AppColors.darkBg : AppColors.offWhite;
    final fieldBg = isDark ? AppColors.darkBg : AppColors.offWhite;

    return ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontFamily: fontFamily,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? AppColors.darkInk : AppColors.textDark,
        contentTextStyle: TextStyle(
          color: isDark ? AppColors.darkBg : Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: scheme.outline,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surface,
        selectedColor: scheme.primary,
        side: BorderSide(color: scheme.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        labelStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: TextStyle(
          color: scheme.onPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fieldBg,
        hintStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
        prefixIconColor: scheme.onSurfaceVariant,
        suffixIconColor: scheme.onSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outline),
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1, space: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? scheme.onPrimary : Colors.white,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? scheme.primary : scheme.outline,
        ),
      ),
    );
  }
}
