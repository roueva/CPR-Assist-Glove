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

  /// Inline success banner — soft green background, no border.
  static BoxDecoration successBanner() => BoxDecoration(
    color: AppColors.successBg,
    borderRadius: BorderRadius.circular(AppSpacing.cardRadiusMd),
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

  /// Achievement card — unlocked state has a tinted border + subtle shadow.
  static BoxDecoration achievementCard({required bool unlocked}) => unlocked
      ? BoxDecoration(
    color:        AppColors.primaryLight,
    borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
    border:       Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
    boxShadow: [
      BoxShadow(
        color:      AppColors.primary.withValues(alpha: 0.08),
        blurRadius: 8,
        offset:     const Offset(0, 2),
      ),
    ],
  )
      : BoxDecoration(
    color:        AppColors.screenBgGrey,
    borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
    border:       Border.all(color: AppColors.divider),
  );

  /// Certificate row — earned has a warm gold tint.
  static BoxDecoration certificateCard({required bool earned}) => earned
      ? BoxDecoration(
    color:        AppColors.warningBg,
    borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
    border:       Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
    boxShadow: [
      BoxShadow(
        color:      AppColors.warning.withValues(alpha: 0.08),
        blurRadius: 8,
        offset:     const Offset(0, 2),
      ),
    ],
  )
      : BoxDecoration(
    color:        AppColors.screenBgGrey,
    borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
    border:       Border.all(color: AppColors.divider),
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

  /// Selected segment inside a segmented control (e.g. cm/in, Adult/Pediatric).
  static BoxDecoration segmentSelected({
    double radius = AppSpacing.cardRadiusSm,
  }) =>
      BoxDecoration(
        color:        AppColors.primary,
        borderRadius: BorderRadius.circular(radius),
      );

  /// Unselected segment — transparent, same radius.
  static BoxDecoration segmentUnselected({
    double radius = AppSpacing.cardRadiusSm,
  }) =>
      BoxDecoration(
        color:        AppColors.transparent,
        borderRadius: BorderRadius.circular(radius),
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
      // Left/horizontal shadow — panel edge depth
      BoxShadow(
        color:      AppColors.shadowStrong,
        blurRadius: AppSpacing.xl,
        offset:     Offset(-AppSpacing.xs, 0),
      ),
      // Top shadow — sells the "sliding under header" effect
      BoxShadow(
        color:      AppColors.shadowMedium,
        blurRadius: AppSpacing.md,
        offset:     Offset(0, -AppSpacing.xs),
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

  static BoxDecoration statusBanner({required Color color}) => BoxDecoration(
    color:        color.withValues(alpha: 0.08),
    borderRadius: BorderRadius.circular(AppSpacing.cardRadiusSm),
    border:       Border.all(color: color.withValues(alpha: 0.25)),
  );
  static BoxDecoration warningBanner() => BoxDecoration(
    color:        AppColors.warningBg,
    borderRadius: BorderRadius.circular(AppSpacing.cardRadiusSm),
    border:       Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
  );

  static BoxDecoration warningBadge() => BoxDecoration(
    color:        AppColors.warning.withValues(alpha: 0.12),
    borderRadius: BorderRadius.circular(AppSpacing.cardRadiusSm),
    border:       Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
  );

  static BoxDecoration cprStatBlock() => BoxDecoration(
    color:        AppColors.textOnDark.withValues(alpha: 0.10),
    borderRadius: BorderRadius.circular(AppSpacing.cardRadiusSm),
  );

  /// Bordered circle avatar — profile header in account panel.
  static BoxDecoration avatarCircle({Color? borderColor}) => BoxDecoration(
    shape:  BoxShape.circle,
    color:  AppColors.primaryLight,
    border: Border.all(
      color: borderColor ?? AppColors.primaryMid,
      width: 1, // 4px — visible as a ring
    ),
  );

  /// 3D-style avatar — gradient fill + layered shadow depth effect.
  static BoxDecoration avatarCircle3d() => const BoxDecoration(
    shape: BoxShape.circle,
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end:   Alignment.bottomRight,
      colors: [
        AppColors.primaryLight,
        AppColors.primaryMid,
      ],
    ),
    boxShadow: [
      // Outer depth shadow
      BoxShadow(
        color:       AppColors.shadowDefault,
        blurRadius:  10,
        spreadRadius: 1,
        offset:      Offset(0, 4),
      ),
      // Inner highlight (top-left light source illusion)
      BoxShadow(
        color:       AppColors.primaryMid,
        blurRadius:  6,
        spreadRadius: -2,
        offset:      Offset(-2, -2),
      ),
    ],
  );

  /// Small edit badge overlaid on an avatar circle.
  static BoxDecoration avatarEditBadge() => BoxDecoration(
    color:  AppColors.primary,
    shape:  BoxShape.circle,
    border: Border.all(color: AppColors.surfaceWhite, width: AppSpacing.xxs),
  );

  /// Corner mode badge on the account avatar button.
  static BoxDecoration avatarModeBadge({required bool isTraining}) => BoxDecoration(
    color:  isTraining ? AppColors.warningBg : AppColors.primaryLight,
    shape:  BoxShape.circle,
    border: Border.all(color: AppColors.headerBg, width: AppSpacing.xxs),
  );
}