import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_spacing.dart';

class AppDecorations {
  AppDecorations._();

  // ═══════════════════════════════════════════════════════
  // CARDS
  // ═══════════════════════════════════════════════════════

  /// Standard white card with a soft drop shadow.
  static BoxDecoration card({
    Color color = AppColors.surfaceWhite,
    double radius = AppSpacing.cardRadius,
  }) =>
      BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadowDefault,
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      );

  /// Tinted blue card — used for info/neutral list items.
  static BoxDecoration tintedCard({
    double radius = AppSpacing.cardRadius,
  }) =>
      BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(radius),
      );

  /// Card with a colored left accent border.
  static BoxDecoration accentCard({
    required Color accentColor,
    Color bg = AppColors.surfaceWhite,
    double radius = AppSpacing.cardRadius,
  }) =>
      BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
        border: Border(
          left: BorderSide(color: accentColor, width: 3),
        ),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadowDefault,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      );

  // ═══════════════════════════════════════════════════════
  // SEMANTIC CARDS
  // ═══════════════════════════════════════════════════════

  static BoxDecoration emergencyCard({double radius = AppSpacing.cardRadius}) =>
      BoxDecoration(
        color: AppColors.emergencyBg,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.emergencyRed.withValues(alpha: 0.3)),
      );

  static BoxDecoration successCard({double radius = AppSpacing.cardRadius}) =>
      BoxDecoration(
        color: AppColors.successBg,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
      );

  static BoxDecoration warningCard({double radius = AppSpacing.cardRadius}) =>
      BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      );

  static BoxDecoration errorCard({double radius = AppSpacing.cardRadius}) =>
      BoxDecoration(
        color: AppColors.errorBg,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      );

  static BoxDecoration primaryCard({double radius = AppSpacing.cardRadius}) =>
      BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      );

  /// Brand gradient card — used for the CPR grade/score panel.
  /// Start: AppColors.primary (#194E9D), End: a slightly lighter brand blue.
  static BoxDecoration primaryGradientCard({
    double radius = AppSpacing.cardRadiusLg,
  }) =>
      BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryAlt],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(radius),
      );

  /// Solid dark-blue card — stats header, session detail grade panel.
  static BoxDecoration primaryDarkCard({
    double radius = AppSpacing.cardRadius,
  }) =>
      BoxDecoration(
        color: AppColors.primaryDark,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadowDefault,
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      );

  /// Gradient card for the leaderboard podium and personal best highlight.
  static BoxDecoration podiumGradientCard({
    double radius = AppSpacing.cardRadius,
  }) =>
      BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryAlt],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(radius),
      );

  // ═══════════════════════════════════════════════════════
  // DIALOGS & SHEETS
  // ═══════════════════════════════════════════════════════

  static BoxDecoration dialog() => BoxDecoration(
    color: AppColors.surfaceWhite,
    borderRadius: BorderRadius.circular(AppSpacing.dialogRadius),
    boxShadow: const [
      BoxShadow(
        color: AppColors.shadowStrong,
        blurRadius: 30,
        offset: Offset(0, 8),
      ),
    ],
  );

  static BoxDecoration bottomSheet() => const BoxDecoration(
    color: AppColors.surfaceWhite,
    borderRadius: BorderRadius.vertical(
      top: Radius.circular(AppSpacing.sheetRadius),
    ),
  );

  // ═══════════════════════════════════════════════════════
  // INPUTS
  // ═══════════════════════════════════════════════════════

  static BoxDecoration inputDefault() => BoxDecoration(
    color: AppColors.screenBgGrey,
    borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
    border: Border.all(color: AppColors.divider),
  );

  static BoxDecoration inputFocused() => BoxDecoration(
    color: AppColors.surfaceWhite,
    borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
    border: Border.all(color: AppColors.primary, width: 1.5),
  );

  static BoxDecoration inputError() => BoxDecoration(
    color: AppColors.errorBg,
    borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
    border: Border.all(color: AppColors.error),
  );

  // ═══════════════════════════════════════════════════════
  // CHIPS & BADGES
  // ═══════════════════════════════════════════════════════

  static BoxDecoration chip({
    required Color color,
    required Color bg,
  }) =>
      BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      );

  // ═══════════════════════════════════════════════════════
  // ICON CONTAINERS
  // ═══════════════════════════════════════════════════════

  static BoxDecoration iconCircle({required Color bg}) => BoxDecoration(
    color: bg,
    shape: BoxShape.circle,
  );

  static BoxDecoration iconRounded({
    required Color bg,
    double radius = AppSpacing.cardRadiusSm,
  }) =>
      BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
      );

  // ═══════════════════════════════════════════════════════
  // MISC
  // ═══════════════════════════════════════════════════════

  /// Subtle divider/separator container
  static BoxDecoration dividerBox() => const BoxDecoration(
    border: Border(
      bottom: BorderSide(color: AppColors.divider, width: 1),
    ),
  );

  /// Map control buttons (recenter, map type toggle)
  static BoxDecoration mapControl() => const BoxDecoration(
    color: AppColors.surfaceWhite,
    shape: BoxShape.circle,
    boxShadow: [
      BoxShadow(
        color: AppColors.shadowMedium,
        blurRadius: 8,
        offset: Offset(0, 2),
      ),
    ],
  );

  static BoxDecoration dialogHeader() => const BoxDecoration(
    color: AppColors.primary,
    borderRadius: BorderRadius.vertical(
      top: Radius.circular(AppSpacing.dialogRadius),
    ),
  );

  /// Account panel — right-to-left slide-in panel with rounded left corners.
  static BoxDecoration sidePanel() => const BoxDecoration(
    color: AppColors.surfaceWhite,
    borderRadius: BorderRadius.only(
      topLeft:    Radius.circular(AppSpacing.cardRadiusLg),
      bottomLeft: Radius.circular(AppSpacing.cardRadiusLg),
    ),
    boxShadow: [
      BoxShadow(
        color:      AppColors.shadowStrong,
        blurRadius: AppSpacing.xl,
        offset:     Offset(-AppSpacing.xs, 0),
      ),
    ],
  );

  /// Pulsing session dot on the Live CPR card.
  /// [glow] adds a coloured spread shadow when the session is active.
  static BoxDecoration sessionDot({required Color color, bool glow = false}) =>
      BoxDecoration(
        color:  color,
        shape:  BoxShape.circle,
        boxShadow: glow
            ? [
          BoxShadow(
            color:        color.withValues(alpha: 0.5),
            blurRadius:   AppSpacing.sm,
            spreadRadius: AppSpacing.xxs,
          ),
        ]
            : const [],
      );

  /// Subtle dark inner container — status bar and gauge overlays on the
  /// dark CPR metrics card.
  static BoxDecoration darkInnerContainer({
    double radius = AppSpacing.cardRadius,
  }) =>
      BoxDecoration(
        color:        AppColors.textOnDark.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(radius),
      );

  /// Small dark stat tile — used inside dark gradient/solid cards.
  static BoxDecoration darkStatTile({
    double radius = AppSpacing.cardRadiusSm,
  }) =>
      BoxDecoration(
        color:        AppColors.textOnDark.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(radius),
      );
}