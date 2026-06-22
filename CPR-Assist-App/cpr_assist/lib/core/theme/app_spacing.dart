/// **AppSpacing — Single source of truth for spacing, radius, and sizing**
///
/// Rules:
///   - Use these constants for ALL padding, margin, gap, and border-radius values.
///   - NEVER hardcode a number like `SizedBox(height: 16)` — use `AppSpacing.md`.
///   - AED map-specific panel sizes live in AEDMapUIConstants (app_constants.dart).
library;

class AppSpacing {
  AppSpacing._();

  // ═══════════════════════════════════════════════════════
  // BASE SCALE
  // ═══════════════════════════════════════════════════════

  static const double xxs  = 2.0;
  static const double xs   = 4.0;
  static const double sm   = 8.0;
  static const double md   = 16.0;  // Standard padding
  static const double lg   = 24.0;
  static const double xl   = 32.0;
  static const double xxl  = 48.0;

  // ═══════════════════════════════════════════════════════
  // COMPONENT-SPECIFIC (named for intent)
  // ═══════════════════════════════════════════════════════

  // Cards
  static const double cardPadding      = md;       // 16
  static const double cardSpacing      = 6.0;      // Gap between cards in a list
  static const double cardRadiusSm     = 8.0;
  static const double cardRadiusMd     = 10.0;     // Mid-size radius (info banners, map chips)
  static const double cardRadius       = 14.0;     // Default card radius
  static const double cardRadiusLg     = 20.0;

  // Dialogs
  static const double dialogRadius     = 20.0;
  static const double dialogPaddingH   = 24.0;
  static const double dialogPaddingTop = 28.0;
  static const double dialogInsetH     = 28.0;
  static const double dialogInsetV     = 48.0;

  // Buttons
  static const double buttonRadiusSm   = 8.0;
  static const double buttonRadius     = 12.0;
  static const double buttonRadiusLg   = 999.0;    // Fully rounded (pill)
  static const double buttonPaddingH   = 20.0;
  static const double buttonPaddingV   = 14.0;
  static const double buttonSizeMd     = 48.0;     // Square icon button (map controls)


  // Chips & badges
  static const double chipRadius       = 999.0;
  static const double chipPaddingH     = 12.0;
  static const double chipPaddingV     = 4.0;

  static const double chipPaddingHSm = 6.0;
  static const double chipPaddingVSm = 2.0;
  static const double iconTiny        = 10.0;
  static const double iconXxs         = 12.0;
  static const double xxxs            = 3.0;

  // Inputs
  static const double inputRadius      = 12.0;
  static const double radiusXs = 2.0; // hairline radius (scrollbars, micro-pills)
  static const double inputPaddingH    = 16.0;
  static const double inputPaddingV    = 14.0;

  // Bottom sheets & panels
  static const double sheetRadius      = 20.0;
  static const double dragHandleWidth  = 40.0;
  static const double dragHandleHeight = 4.0;
  static const double dragHandleWidthWide = 56.0; // Wider handle variant (AED sheet)


  // ── Guide screen visual constants ────────────────────────────────────────────
  static const double guideHeroImageH    = 160.0;  // standard hero image
  static const double guideStepNumber    = 28.0;   // numbered step circle
  static const double guideChainIcon     = 36.0;   // chain-of-survival circle
  static const double guideStepRail      = 32.0;   // left rail width for numbered steps
  static const double guideSchematicH    = 190.0;  // AED schematic painter height
  static const double guideChainRowH     = 80.0;   // chain-of-survival icon row

  static const double guideHubHeroH        = 160.0;  // hero card on hub
  static const double guideHubSmH          = 120.0;  // small 2-col card on hub
  static const double guideChainBannerH    = 150.0;  // chain-of-survival photo banner
  static const double guideDetailImageH    = 160.0;  // photo inside detail screens
  static const double guideSmallPhotoH     = 100.0;  // labelled photo pair (pediatric)
  static const double guideAccentBarW      =  48.0;  // colored accent strip under appbar title
  static const double guideSchematicPadW   =  44.0;  // AED schematic pad rectangle width
  static const double guideSchematicPadH   =  32.0;  // AED schematic pad rectangle height
  static const double guideSchematicLabelSize = 13.0; // AED schematic pad label font size

  // ═══════════════════════════════════════════════════════
  // TOUCH TARGETS (WCAG / accessibility)
  // ═══════════════════════════════════════════════════════

  static const double touchTargetMin   = 44.0;   // WCAG minimum
  static const double touchTargetLarge = 56.0;   // Emergency actions (112 call, nav)

  // ═══════════════════════════════════════════════════════
  // ICON & AVATAR SIZES
  // ═══════════════════════════════════════════════════════

  static const double iconXs   = 14.0;
  static const double iconSm   = 18.0;
  static const double iconMd   = 24.0;  // Default icon size
  static const double iconLg   = 32.0;
  static const double iconXl   = 48.0;

  static const double avatarSm = 32.0;
  static const double avatarMd = 44.0;
  static const double avatarLg = 64.0;
  static const double avatarXl = 88.0;  // Hero stats ring
  static const double iconBoxSize   = 36.0;  // Icon container (touchTargetMin − sm)

  // Live CPR widget dimensions
  static const double sessionDotSize   = 10.0;

  static const double arcWidth  = 300.0;
  static const double arcHeight = 300.0;

  // ═══════════════════════════════════════════════════════
  // LAYOUT
  // ═══════════════════════════════════════════════════════

  static const double headerHeight      = 60.0;
  static const double emergencyBannerH  = 56.0;
  static const double bottomNavHeight   = 64.0;
  static const double dividerThickness  = 1.0;
  static const double depthBarWidth    = 114.0;
  static const double depthBarHeight   = 200.0;

  static const double vitalsItemHeight = 44.0; // Divider height in VitalsCard

  static const double scrollEndPad = 100.0;

  static const double statusBarHeight = 32.0; // Live CPR mode/scenario status bar
  static const double iconButtonMin   = 32.0; // Minimum size for small icon buttons
}