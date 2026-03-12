import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// **AppTheme — Wires all design tokens into Flutter's ThemeData**
///
/// Usage:
///   MaterialApp(theme: AppTheme.light)
///
/// Rules:
///   - No color values here — import from AppColors.
///   - No text styles here — import from AppTypography.
///   - No spacing values here — import from AppSpacing.
class AppTheme {
  AppTheme._();

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    fontFamily: 'Inter',
    colorScheme: _colorScheme,
    textTheme: AppTypography.textTheme,
    scaffoldBackgroundColor: AppColors.screenBg,
    appBarTheme: _appBarTheme,
    cardTheme: _cardTheme,
    elevatedButtonTheme: _elevatedButtonTheme,
    outlinedButtonTheme: _outlinedButtonTheme,
    textButtonTheme: _textButtonTheme,
    inputDecorationTheme: _inputDecorationTheme,
    dividerTheme: _dividerTheme,
    snackBarTheme: _snackBarTheme,
    bottomNavigationBarTheme: _bottomNavTheme,
    dialogTheme: _dialogTheme,
    chipTheme: _chipTheme,
  );

  // ═══════════════════════════════════════════════════════
  // COLOR SCHEME
  // ═══════════════════════════════════════════════════════

  static const ColorScheme _colorScheme = ColorScheme.light(
    primary:          AppColors.primary,
    primaryContainer: AppColors.primaryLight,
    secondary:        AppColors.info,
    error:            AppColors.error,
    surface:          AppColors.surfaceWhite,
    onPrimary:        AppColors.textOnDark,
    onSecondary:      AppColors.textOnDark,
    onSurface:        AppColors.textPrimary,
    onError:          AppColors.textOnDark,
    outline:          AppColors.divider,
  );

  // ═══════════════════════════════════════════════════════
  // APP BAR
  // ═══════════════════════════════════════════════════════

  static const AppBarTheme _appBarTheme = AppBarTheme(
    backgroundColor:  AppColors.headerBg,
    foregroundColor:  AppColors.textPrimary,
    elevation:        0,
    scrolledUnderElevation: 0,
    centerTitle:      false,
    systemOverlayStyle: SystemUiOverlayStyle(
      statusBarColor:           Colors.transparent,
      statusBarIconBrightness:  Brightness.dark,
      statusBarBrightness:      Brightness.light,
    ),
  );

  // ═══════════════════════════════════════════════════════
  // CARD
  // ═══════════════════════════════════════════════════════

  static final CardThemeData _cardTheme = CardThemeData(
    color:     AppColors.surfaceWhite,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
    ),
    margin: const EdgeInsets.only(bottom: AppSpacing.cardSpacing),
  );

  // ═══════════════════════════════════════════════════════
  // BUTTONS
  // ═══════════════════════════════════════════════════════

  static final ElevatedButtonThemeData _elevatedButtonTheme =
  ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor:   AppColors.primary,
      foregroundColor:   AppColors.textOnDark,
      elevation:         0,
      minimumSize:       const Size(double.infinity, AppSpacing.touchTargetLarge),
      padding:           const EdgeInsets.symmetric(
        horizontal: AppSpacing.buttonPaddingH,
        vertical:   AppSpacing.buttonPaddingV,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
      ),
      textStyle:         AppTypography.buttonPrimary(),
    ),
  );

  static final OutlinedButtonThemeData _outlinedButtonTheme =
  OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: AppColors.primary,
      side:            const BorderSide(color: AppColors.primary),
      minimumSize:     const Size(double.infinity, AppSpacing.touchTargetLarge),
      padding:         const EdgeInsets.symmetric(
        horizontal: AppSpacing.buttonPaddingH,
        vertical:   AppSpacing.buttonPaddingV,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
      ),
      textStyle:       AppTypography.buttonSecondary(),
    ),
  );

  static final TextButtonThemeData _textButtonTheme = TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: AppColors.primary,
      textStyle:       AppTypography.buttonSecondary(),
      padding:         const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical:   AppSpacing.xs,
      ),
    ),
  );

  // ═══════════════════════════════════════════════════════
  // INPUT
  // ═══════════════════════════════════════════════════════

  static final InputDecorationTheme _inputDecorationTheme =
  InputDecorationTheme(
    filled:            true,
    fillColor:         AppColors.screenBgGrey,
    contentPadding:    const EdgeInsets.symmetric(
      horizontal: AppSpacing.inputPaddingH,
      vertical:   AppSpacing.inputPaddingV,
    ),
    border: OutlineInputBorder(
      borderRadius:  BorderRadius.circular(AppSpacing.inputRadius),
      borderSide:    const BorderSide(color: AppColors.divider),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius:  BorderRadius.circular(AppSpacing.inputRadius),
      borderSide:    const BorderSide(color: AppColors.divider),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius:  BorderRadius.circular(AppSpacing.inputRadius),
      borderSide:    const BorderSide(color: AppColors.primary, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius:  BorderRadius.circular(AppSpacing.inputRadius),
      borderSide:    const BorderSide(color: AppColors.error),
    ),
    hintStyle:         AppTypography.body(color: AppColors.textHint),
    labelStyle:        AppTypography.label(color: AppColors.textSecondary),
    errorStyle:        AppTypography.caption(color: AppColors.error),
  );

  // ═══════════════════════════════════════════════════════
  // DIVIDER
  // ═══════════════════════════════════════════════════════

  static const DividerThemeData _dividerTheme = DividerThemeData(
    color:     AppColors.divider,
    thickness: AppSpacing.dividerThickness,
    space:     0,
  );

  // ═══════════════════════════════════════════════════════
  // SNACK BAR
  // ═══════════════════════════════════════════════════════

  static final SnackBarThemeData _snackBarTheme = SnackBarThemeData(
    backgroundColor:  AppColors.primary,
    contentTextStyle: AppTypography.snackbar(),
    behavior:         SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppSpacing.buttonRadiusSm),
    ),
  );

  // ═══════════════════════════════════════════════════════
  // BOTTOM NAV
  // ═══════════════════════════════════════════════════════

  static const BottomNavigationBarThemeData _bottomNavTheme =
  BottomNavigationBarThemeData(
    backgroundColor:       AppColors.surfaceWhite,
    selectedItemColor:     AppColors.primary,
    unselectedItemColor:   AppColors.textDisabled,
    elevation:             0,
    type:                  BottomNavigationBarType.fixed,
    showSelectedLabels:    true,
    showUnselectedLabels:  true,
  );

  // ═══════════════════════════════════════════════════════
  // DIALOG
  // ═══════════════════════════════════════════════════════

  static final DialogThemeData _dialogTheme = DialogThemeData(
    backgroundColor:  AppColors.surfaceWhite,
    elevation:        0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppSpacing.dialogRadius),
    ),
  );

  // ═══════════════════════════════════════════════════════
  // CHIP
  // ═══════════════════════════════════════════════════════

  static final ChipThemeData _chipTheme = ChipThemeData(
    backgroundColor:      AppColors.primaryLight,
    selectedColor:        AppColors.primary,
    labelStyle:           AppTypography.label(color: AppColors.textSecondary),
    padding:              const EdgeInsets.symmetric(
      horizontal: AppSpacing.chipPaddingH,
      vertical:   AppSpacing.chipPaddingV,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
    ),
  );
}