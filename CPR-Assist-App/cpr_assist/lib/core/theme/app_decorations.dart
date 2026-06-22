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
    Color color = AppColors.white,
    double radius = AppSpacing.cardRadius,
    double shadowOpacity = 0.05,  // ← add this
  }) =>
      BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, shadowOpacity),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      );

  /// Tinted blue card — used for info/neutral list items.
  static BoxDecoration tintedCard({
    double radius = AppSpacing.cardRadius,
  }) =>
      BoxDecoration(
        color: AppColors.screenBgGrey,
        borderRadius: BorderRadius.circular(radius),
      );


  /// Bordered info box — used inside dialogs for reference tables and explanatory blocks.
  static BoxDecoration infoBox({
    double radius = AppSpacing.cardRadiusMd,
  }) =>
      BoxDecoration(
        color:        AppColors.white,
        borderRadius: BorderRadius.circular(radius),
        border:       Border.all(color: AppColors.divider),
      );

  /// Grey info box — subdued background block inside dialogs (no border).
  static BoxDecoration greyInfoBox({
    double radius = AppSpacing.cardRadiusMd,
  }) =>
      BoxDecoration(
        color:        AppColors.screenBgGrey,
        borderRadius: BorderRadius.circular(radius),
      );


  /// Chart plot area — rounded top corners only, screenBgGrey fill.
  static BoxDecoration chartArea() => BoxDecoration(
    color: AppColors.screenBgGrey.withValues(alpha: 0.5),
    borderRadius: const BorderRadius.only(
      topLeft:     Radius.circular(AppSpacing.cardRadiusMd),
      topRight:    Radius.circular(AppSpacing.cardRadiusMd),
    ),
  );

  /// Inline success banner — soft green background, no border.
  static BoxDecoration successBanner() => BoxDecoration(
    color: AppColors.successBg,
    borderRadius: BorderRadius.circular(AppSpacing.cardRadiusMd),
  );

  /// Card with a colored left accent border.
  static BoxDecoration accentCard({
    required Color accentColor,
    Color bg = AppColors.white,
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
        color: AppColors.errorBg,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.emergency.withValues(alpha: 0.3)),
      );

  static BoxDecoration successCard({double radius = AppSpacing.cardRadius}) =>
      BoxDecoration(
        color: AppColors.successBg,
        borderRadius: BorderRadius.circular(radius),
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

  static BoxDecoration primaryCard({
    double radius = AppSpacing.cardRadius,
    bool bordered = true,
  }) =>
      BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(radius),
        border: bordered
            ? Border.all(color: AppColors.primary.withValues(alpha: 0.2))
            : null,
        boxShadow: bordered
            ? null
            : [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
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

  /// CPR grade/score panel.
  static BoxDecoration primaryGradientCard({
    double radius = AppSpacing.cardRadiusLg,
  }) =>
      BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(radius),
      );

  /// Solid dark-blue card — stats header, session detail grade panel.
  static BoxDecoration primaryAltCard({
    double radius = AppSpacing.cardRadius,
  }) =>
      BoxDecoration(
        color: AppColors.primaryAlt,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadowDefault,
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      );

  /// Card for the leaderboard podium and personal best highlight.
  static BoxDecoration podiumGradientCard({
    double radius = AppSpacing.cardRadius,
  }) =>
      BoxDecoration(
        color: AppColors.cprCardBg,
        borderRadius: BorderRadius.circular(radius),
      );

  // ═══════════════════════════════════════════════════════
  // DIALOGS & SHEETS
  // ═══════════════════════════════════════════════════════

  static BoxDecoration dialog() => BoxDecoration(
    color: AppColors.white,
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
    color: AppColors.white,
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
    color: AppColors.white,
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
      );

  /// Selected segment inside a segmented control (e.g. cm/in, Adult/Pediatric).
  static BoxDecoration segmentSelected({
    double radius = AppSpacing.cardRadiusLg,
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
    color: AppColors.white,
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
    color: AppColors.white,
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


  // ── Chart infra (cpr_chart_helpers) ──────────────────────────────────────
  static BoxDecoration dropdownPill() => BoxDecoration(
    color: AppColors.primaryLight,
    borderRadius: BorderRadius.circular(AppSpacing.buttonRadiusLg),
  );

  static BoxDecoration scrollTrack() => BoxDecoration(
    color: AppColors.divider,
    borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
  );

  static BoxDecoration scrollThumb() => BoxDecoration(
    color: AppColors.primary.withValues(alpha: 0.55),
    borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
  );

  static BoxDecoration iconChipPrimary() => BoxDecoration(
    color: AppColors.primaryLight,
    borderRadius: BorderRadius.circular(AppSpacing.cardRadiusSm),
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
    color: AppColors.primaryLight,
    boxShadow: [
      BoxShadow(
        color:      AppColors.shadowDefault,
        blurRadius: 10,
        spreadRadius: 1,
        offset:     Offset(0, 4),
      ),
    ],
  );

  /// Small edit badge overlaid on an avatar circle.
  static BoxDecoration avatarEditBadge() => BoxDecoration(
    color:  AppColors.primary,
    shape:  BoxShape.circle,
    border: Border.all(color: AppColors.white, width: AppSpacing.xxs),
  );

  /// Corner mode badge on the account avatar button.
  static BoxDecoration avatarModeBadge({required bool isTraining}) => BoxDecoration(
    color:  isTraining ? AppColors.primaryLight : AppColors.emergencyModeBg,
    shape:  BoxShape.circle,
    border: Border.all(color: AppColors.white, width: AppSpacing.xxs),
  );

  /// Emergency mode green — used in EmergencyHeader.
  static BoxDecoration emergencyGradient() => const BoxDecoration(
    color: AppColors.emergencyMode,
  );

  /// Thin coloured accent bar — used in chart card titles.
  static BoxDecoration accentBar({required Color color}) => BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(AppSpacing.xxs),
  );

  /// Semi-transparent overlay tile — used inside dark gradient cards.
  static BoxDecoration darkOverlayTile({
    double radius = AppSpacing.cardRadius,
  }) => BoxDecoration(
    color: AppColors.textOnDark.withValues(alpha: 0.10),
    borderRadius: BorderRadius.circular(radius),
  );

  /// Grade card on session results — blue-brand card background.
  static BoxDecoration gradeCard({
    double radius = AppSpacing.cardRadiusLg,
  }) => BoxDecoration(
    color: AppColors.cprCardBg,
    borderRadius: BorderRadius.circular(radius),
  );
  /// Legend card with a colored top accent bar — used in session compare screen.
  static BoxDecoration legendCard({required Color topColor}) => BoxDecoration(
    color: AppColors.white,
    borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
    boxShadow: const [
      BoxShadow(
        color: AppColors.shadowDefault,
        blurRadius: 10,
        offset: Offset(0, 2),
      ),
    ],
  );

  /// Highlighted best-value cell — used in metrics comparison rows.
  static BoxDecoration bestValueHighlight() => BoxDecoration(
    color: AppColors.primaryLight,
    borderRadius: BorderRadius.circular(AppSpacing.cardRadiusSm),
  );

  /// Pill badge — dynamically colored background, fully rounded.
  static BoxDecoration trendPill(Color bg) => BoxDecoration(
    color: bg,
    borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
  );

  /// Achievement unlock banner — green tint with border.
  static BoxDecoration achievementUnlockBanner() => BoxDecoration(
    color: AppColors.successBg,
    borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
    border: Border.all(color: AppColors.success.withValues(alpha: 0.35)),
  );

  /// Certificate card footer — earned warm amber tint.
  static BoxDecoration certFooterEarned() => BoxDecoration(
    color: AppColors.warningBg,
    borderRadius: const BorderRadius.only(
      bottomLeft:  Radius.circular(AppSpacing.cardRadius),
      bottomRight: Radius.circular(AppSpacing.cardRadius),
    ),
    border: Border(
      top:   BorderSide(color: AppColors.warning.withValues(alpha: 0.35)),
    ),
  );

  /// Certificate card footer — locked grey tint.
  static BoxDecoration certFooterLocked() => BoxDecoration(
    color: AppColors.screenBgGrey,
    borderRadius: const BorderRadius.only(
      bottomLeft:  Radius.circular(AppSpacing.cardRadius),
      bottomRight: Radius.circular(AppSpacing.cardRadius),
    ),
    border: Border(
      top: BorderSide(color: AppColors.divider),
    ),
  );

  /// Certificate card — earned has gold border, locked is plain.
  static BoxDecoration certificateCardV2({required bool earned}) => earned
      ? BoxDecoration(
    color:        AppColors.white,
    borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
    border:       Border.all(color: AppColors.warning.withValues(alpha: 0.6), width: 1),
    boxShadow: [
      BoxShadow(
        color:      AppColors.warning.withValues(alpha: 0.08),
        blurRadius: 10,
        offset:     const Offset(0, 2),
      ),
    ],
  )
      : BoxDecoration(
    color:        AppColors.white,
    borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
    border:       Border.all(color: AppColors.divider),
  );

  /// Achievement list item — earned green tint.
  static BoxDecoration achievementItemEarned({bool isStreak = false}) =>
      BoxDecoration(
        color:        isStreak ? AppColors.warningBg : AppColors.successBg,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(
          color: isStreak
              ? AppColors.warning.withValues(alpha: 0.35)
              : AppColors.success.withValues(alpha: 0.35),
        ),
      );

  /// Achievement list item — locked state.
  static BoxDecoration achievementItemLocked() => BoxDecoration(
    color:        AppColors.white,
    borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
    border:       Border.all(color: AppColors.divider),
  );

  /// Dark-surface trend pill — used on cprCardBg / primaryAlt cards.
  static BoxDecoration darkTrendPill(Color c) => BoxDecoration(
    color:        c.withValues(alpha: 0.18),
    borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
    border:       Border.all(color: c.withValues(alpha: 0.35)),
  );

  static BoxDecoration selectedCard({double shadowOpacity = 0.10}) =>
      card(shadowOpacity: shadowOpacity).copyWith(
        color: AppColors.primaryLight,
      );

  // ═══════════════════════════════════════════════════════
  // SESSION HISTORY
  // ═══════════════════════════════════════════════════════

  /// Generic flat coloured pill — used for icon toggles, sort dropdowns,
  /// and small inline badges on light or dark surfaces.
  static BoxDecoration pill({
    required Color bg,
    double radius = AppSpacing.cardRadiusSm,
  }) =>
      BoxDecoration(
        color:        bg,
        borderRadius: BorderRadius.circular(radius),
      );

  /// Bottom-sheet / dialog drag handle bar.
  static BoxDecoration dragHandle() => BoxDecoration(
    color:        AppColors.divider,
    borderRadius: BorderRadius.circular(2),
  );

  /// Thin coloured accent strip rounded only on the top corners,
  /// used on the top edge of session cards.
  static BoxDecoration cardTopAccent({required Color color}) => BoxDecoration(
    color: color,
    borderRadius: const BorderRadius.only(
      topLeft:  Radius.circular(AppSpacing.cardRadius),
      topRight: Radius.circular(AppSpacing.cardRadius),
    ),
  );

  /// Dark stats summary header card (session history top banner).
  static BoxDecoration statsHeaderCard() => BoxDecoration(
    color:        AppColors.cprCardBg,
    borderRadius: BorderRadius.circular(AppSpacing.cardRadiusLg),
  );

  /// Colored dot — used for bullet points in guide lists.
  static BoxDecoration dot(Color c) => BoxDecoration(
    color: c,
    shape: BoxShape.circle,
  );

}
