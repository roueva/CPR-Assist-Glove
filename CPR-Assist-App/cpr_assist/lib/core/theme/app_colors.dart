import 'package:flutter/material.dart';

/// **AppColors — Single source of truth for all colors**
///
/// Rules:
///   - NEVER hardcode a color value anywhere else in the app.
///   - app_theme.dart, widgets, screens all import from here.
///   - Semantic names only — name by PURPOSE, not by hex value.
class AppColors {
  AppColors._();

  // ═══════════════════════════════════════════════════════
  // BRAND
  // ═══════════════════════════════════════════════════════

  static const Color primary        = Color(0xFF194E9D); // Main brand blue
  static const Color primaryLight   = Color(0xFFEDF4F9); // Light blue bg / card tint
  static const Color primaryMid     = Color(0xFFE3EFF8); // Mid-tone blue (dividers, hover)
  static const Color primaryDark     = Color(0xFF335484); // Dark blue — stats header, podium bg
  static const Color primaryAlt      = Color(0xFF355CA9); // Gradient end stop (grade card, leaderboard)

  // ═══════════════════════════════════════════════════════
  // SEMANTIC — Success / Warning / Error / Info
  // ═══════════════════════════════════════════════════════

  static const Color success        = Color(0xFF2E7D32); // Green 700
  static const Color successBg      = Color(0xFFEDF7F2); // Light green tint
  static const Color warning        = Color(0xFFF57C00); // Orange 700
  static const Color warningBg      = Color(0xFFFFF8EC); // Light orange tint
  static const Color error          = Color(0xFFD32F2F); // Red 700
  static const Color errorBg        = Color(0xFFFDF0F0); // Light red tint — use instead of emergencyBg
  static const Color info           = Color(0xFF1976D2); // Blue 700

  // ═══════════════════════════════════════════════════════
  // EMERGENCY / CPR
  // ═══════════════════════════════════════════════════════

  static const Color emergencyRed   = Color(0xFFB71C1C); // Emergency call banner
  static const Color emergencyBg    = Color(0xFFFDF0F0); // = errorBg (alias kept for clarity)
  static const Color emergencyDark   = Color(0xFF8B0000); // Dark red — emergency header gradient end
  static const Color cprGreen       = Color(0xFF2E7D32); // Correct compression
  static const Color cprOrange      = Color(0xFFF57C00); // Needs improvement
  static const Color cprRed         = Color(0xFFD32F2F); // Incorrect compression


  // ═══════════════════════════════════════════════════════
  // TEXT HIERARCHY
  // ═══════════════════════════════════════════════════════

  static const Color textPrimary    = Color(0xFF111827); // Near-black
  static const Color textSecondary  = Color(0xFF4B5563); // Mid grey
  static const Color textDisabled   = Color(0xFF9CA3AF); // Disabled
  static const Color textHint       = Color(0xFFBDBDBD); // Placeholder
  static const Color textOnDark     = Color(0xFFFFFFFF); // White text on dark bg

  static const Color vitalsValue  = Color(0xFF4D4A4A); // Vitals reading text
  static const Color statCardBg   = Color(0xFF315FA3); // Small stat card inside dark hub
  // ═══════════════════════════════════════════════════════
  // BACKGROUNDS & SURFACES
  // ═══════════════════════════════════════════════════════

  static const Color transparent = Color(0x00000000); //Transparent
  static const Color screenBg       = Color(0xFFFFFFFF); // Default screen background
  static const Color screenBgGrey   = Color(0xFFF4F7FB); // Neutral grey screen bg
  static const Color cardBg         = Color(0xFFEDF4F9); // = primaryLight
  static const Color surfaceWhite   = Color(0xFFFFFFFF); // Cards, dialogs, sheets
  static const Color headerBg       = Color(0xFFFFFFFF); // Universal header
  static const Color divider        = Color(0xFFEEF2F7); // Dividers, borders

  // Overlays
  static const Color overlayDark    = Color(0x80000000); // Modal barrier (50% black)
  static const Color overlayLight   = Color(0x1A000000); // Subtle scrim (10% black)

  // ═══════════════════════════════════════════════════════
  // AED MAP
  // ═══════════════════════════════════════════════════════

  static const Color clusterGreen   = Color(0xFF2E7D32);
  static const Color aedOpenBorder  = Color(0xFF2E7D32);
  static const double aedClosedOpacity = 0.5;
  static const Color aedNavGreen       = Color(0xFF006636); // Darker green for navigation/transport icons
  static const Color scrollThumb       = Color(0xFFBDD8F0); // Scrollbar thumb in AED panels

  // ═══════════════════════════════════════════════════════
  // BLE STATUS
  // ═══════════════════════════════════════════════════════

  static const Color bleConnected    = Color(0xFF2E7D32);
  static const Color bleDisconnected = Color(0xFF757575);
  static const Color bleScanning     = Color(0xFFF57C00);

  // ═══════════════════════════════════════════════════════
  // SHADOWS
  // Used via AppDecorations — don't use directly in widgets.
  // ═══════════════════════════════════════════════════════

  static const Color shadowDefault  = Color(0x0D000000); // 5% black
  static const Color shadowMedium   = Color(0x1A000000); // 10% black
  static const Color shadowStrong   = Color(0x1F000000); // 12% black
}