import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTypography {
  AppTypography._();

  static const String _inter   = 'Inter';
  static const String _poppins = 'Poppins';

  // ═══════════════════════════════════════════════════════
  // PRIMITIVE BUILDERS
  // Low-level — prefer the semantic styles below.
  // ═══════════════════════════════════════════════════════

  static TextStyle inter({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    Color color = AppColors.textPrimary,
    double? height,
    double? letterSpacing,
    TextDecoration? decoration,
  }) =>
      TextStyle(
        fontFamily: _inter,
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
        decoration: decoration,
      );

  static TextStyle poppins({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    Color color = AppColors.textPrimary,
    double? height,
    double? letterSpacing,
    TextDecoration? decoration,
  }) =>
      TextStyle(
        fontFamily: _poppins,
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
        decoration: decoration,
      );

  // ═══════════════════════════════════════════════════════
  // SEMANTIC STYLES — use these in your widgets
  // ═══════════════════════════════════════════════════════

  // ── Display / Headings ────────────────────────────────

  /// Large screen title — login, onboarding hero text
  static TextStyle displayLg({Color color = AppColors.textPrimary}) =>
      inter(size: 28, weight: FontWeight.w800, color: color, letterSpacing: -0.5);

  /// Section heading — screen titles, card headers
  static TextStyle heading({
    double size = 18,
    Color color = AppColors.textPrimary,
    FontWeight weight = FontWeight.w700,
  }) =>
      inter(size: size, weight: FontWeight.w800, color: color, letterSpacing: -0.3);

  /// Sub-heading — secondary labels, group headers
  static TextStyle subheading({
    double size = 15,
    Color color = AppColors.textPrimary,
  }) =>
      inter(size: size, weight: FontWeight.w600, color: color, letterSpacing: -0.1);

  // ── Body ─────────────────────────────────────────────

  /// Default body text
  static TextStyle body({
    double size = 14,
    Color color = AppColors.textSecondary,
  }) =>
      inter(size: size, weight: FontWeight.w400, color: color, height: 1.5);

  /// Body with emphasis
  static TextStyle bodyMedium({
    double size = 14,
    Color color = AppColors.textPrimary,
  }) =>
      inter(size: size, weight: FontWeight.w500, color: color, height: 1.5);

  /// Bold body — action text, values
  static TextStyle bodyBold({
    double size = 14,
    Color color = AppColors.textPrimary,
  }) =>
      inter(size: size, weight: FontWeight.w700, color: color, height: 1.5);

  // ── Labels & Captions ────────────────────────────────

  /// Small label — metadata, timestamps, hints
  static TextStyle label({
    double size = 12,
    Color color = AppColors.textDisabled,
  }) =>
      inter(size: size, weight: FontWeight.w600, color: color, letterSpacing: 0.3);

  /// Uppercase badge / tag text
  static TextStyle badge({
    double size = 11,
    Color color = AppColors.textPrimary,
  }) =>
      inter(
        size: size,
        weight: FontWeight.w800,
        color: color,
        letterSpacing: 1.2,
      );

  /// Caption / fine print
  static TextStyle caption({Color color = AppColors.textDisabled}) =>
      inter(size: 11, weight: FontWeight.w400, color: color, height: 1.4);

  // ── Navigation ───────────────────────────────────────

  static TextStyle navSelected() =>
      poppins(size: 14, weight: FontWeight.w600, color: AppColors.primary);

  static TextStyle navUnselected() =>
      poppins(size: 14, weight: FontWeight.w500, color: AppColors.textSecondary);

  // ── Buttons ──────────────────────────────────────────

  static TextStyle buttonPrimary() =>
      inter(size: 15, weight: FontWeight.w700, color: AppColors.textOnDark);

  static TextStyle buttonSecondary({Color color = AppColors.primary}) =>
      inter(size: 15, weight: FontWeight.w600, color: color);

  static TextStyle buttonSmall({Color color = AppColors.primary}) =>
      inter(size: 13, weight: FontWeight.w600, color: color);

  // ── App-specific ─────────────────────────────────────

  /// App bar / header title
  static TextStyle appTitle() =>
      inter(size: 22, weight: FontWeight.w700, color: AppColors.primary);

  /// Large numeric values — CPR depth, score, stats
  static TextStyle numericDisplay({
    double size = 32,
    Color color = AppColors.textPrimary,
  }) =>
      inter(size: size, weight: FontWeight.w800, color: color, letterSpacing: -1.0);

  /// Snackbar message text
  static TextStyle snackbar() =>
      inter(size: 14, weight: FontWeight.w500, color: AppColors.textOnDark);

  // ═══════════════════════════════════════════════════════
  // THEME WIRING — used by app_theme.dart only
  // ═══════════════════════════════════════════════════════

  static TextTheme get textTheme => TextTheme(
    displayLarge:  displayLg(),
    titleLarge:    heading(),
    titleMedium:   subheading(),
    bodyLarge:     bodyMedium(),
    bodyMedium:    body(),
    bodySmall:     caption(),
    labelLarge:    buttonPrimary(),
    labelMedium:   label(),
    labelSmall:    badge(),
  );
}