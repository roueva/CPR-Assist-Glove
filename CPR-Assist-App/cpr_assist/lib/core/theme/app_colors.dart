import 'package:flutter/material.dart';

/// **AppColors — Single source of truth for all colors**
///
/// Rules:
///   - NEVER hardcode a color anywhere else in the app.
///   - Name by PURPOSE, never by hex value.
///   - One import: `package:cpr_assist/core/core.dart`
///
/// Dark-surface palette (used on cprCardBg #163872):
///   Text/icons:  textOnDark     (#FFFFFF)
///   Good:        feedbackGood   (#4CD966) — vivid green,  readable on dark blue
///   Warning:     feedbackWarn   (#FFB347) — warm amber,   readable on dark blue
///   Error/bad:   feedbackBad    (#FF6B6B) — soft red,     readable on dark blue
///   Arc green:   arcGood        (#4CD966) — teal-green arc zone
///   Arc red:     arcBad         (#F87171) — muted red arc zones
///   Needle:      needleFill     (#93C5FD) — cool blue needle body
///   Needle tip:  needleTip      (#DBEAFE) — near-white blue tip
class AppColors {
  AppColors._();

  // ═══════════════════════════════════════════════════════
  // BRAND BLUE RAMP
  // A coherent scale from the darkest surface to the lightest tint.
  // ═══════════════════════════════════════════════════════

  /// Depth-bar pill inactive fill — very deep navy.
  static const Color blue900 = Color(0xFF0F2D5C);

  /// Live CPR card background — the main dark surface.
  static const Color cprCardBg = Color(0xFF163872);

  /// Primary brand blue — buttons, icons, active states, links.
  static const Color primary = Color(0xFF1E4D96);

  /// Gradient end / dark header stop — slightly lighter than primary.
  static const Color primaryAlt = Color(0xFF2D62B8);

  /// Stat tiles inside the CPR dark card.
  static const Color statTileBg = Color(0xFF3870C0);

  /// Selected chip / scrollbar / hover state — clear presence on white.
  static const Color primaryMid = Color(0xFFE3EFF8);

  /// Icon circle bg / card tint / chip bg on white surfaces.
  static const Color primaryLight = Color(0xFFEDF4F9);

  /// Header surface and AED card tint — soft blue-white.
  static const Color headerSurface = Color(0xFFEDF4F9);


  /// AED
  static const Color clusterCenter = Color(0xFF006636);
  static const Color clusterRing   = Color(0xFF93C01F);

  // ═══════════════════════════════════════════════════════
  // SEMANTIC — Success / Warning / Error
  // Used on WHITE / light surfaces only.
  // For dark-surface feedback use the FEEDBACK section below.
  // ═══════════════════════════════════════════════════════

  /// Correct compression on white, AED open border, BLE connected, form success.
  static const Color success = Color(0xFF2E7D32);

  /// Light green tint for success banners / confirmation backgrounds.
  static const Color successBg = Color(0xFFE6F5E8);

  /// Needs improvement, training mode accent, fatigue badge, BLE scanning.
  static const Color warning = Color(0xFFF57C00);

  /// Warm orange tint for warning banners.
  static const Color warningBg = Color(0xFFFFF3E0);
  /// No-feedback training mode accent — aliases warning.
  /// Used in pills/badges to indicate the session ran without live coaching.
  static const Color noFeedback   = warning;
  static const Color noFeedbackBg = warningBg;

  /// Form errors, validation, non-life-threatening error states.
  static const Color error = Color(0xFFD32F2F);

  /// Light red tint — form error bg and emergency dialog bg.
  static const Color errorBg = Color(0xFFFDF0F0);

  // ═══════════════════════════════════════════════════════
  // EMERGENCY
  // ═══════════════════════════════════════════════════════

  /// Emergency call banner, BLE disconnect error, delete confirmations.
  static const Color emergency = Color(0xFFB71C1C);

  /// Gradient end for emergency header — deeper dark red.
  static const Color emergencyDark = Color(0xFF8B0000);

  // ── MODE COLORS ──────────────────────────────────────────────────────────
  /// Emergency mode accent — forest green, same visual weight as primary blue.
  static const Color emergencyMode     = Color(0xFF1B7A3F);

  /// Emergency mode light tint — card backgrounds, badges.
  static const Color emergencyModeBg   = Color(0xFFE6F4EC);

  /// Emergency mode dark — header gradient end stop.
  static const Color emergencyModeDark = Color(0xFF145C30);

  // ═══════════════════════════════════════════════════════
  // FEEDBACK — dark-surface only (on cprCardBg / blue900)
  //
  // Different from success/warning/error intentionally.
  // The light-surface greens/oranges/reds are too dark/dull
  // to read against the deep navy card (#163872).
  // These are brighter, tuned specifically for that surface.
  // ═══════════════════════════════════════════════════════

  /// Correct compression — text, icons, fills on dark card. Vivid emerald.
  static const Color feedbackGood = Color(0xFF4CD966);

  /// Needs improvement — text, icons on dark card. Warm amber.
  static const Color feedbackWarn = Color(0xFFFFB347);

  /// Wrong / excessive — text, icons on dark card. Soft coral red.
  static const Color feedbackBad = Color(0xFFFF6B6B);

  /// Informational / neutral state on dark card — light blue.
  static const Color feedbackInfo = Color(0xFF60B4FF);

  /// Frequency arc — good zone (100–120 CPM). Teal-green, glows on dark.
  static const Color arcGood = Color(0xFF4CD966);

  /// Frequency arc — out-of-range zones. Muted warm red.
  static const Color arcBad = Color(0xFFFF6B6B);

  /// Depth bar fill — too-shallow zone.
  static const Color depthFillWarn = Color(0xFFFFB347);

  /// Depth bar fill — correct zone.
  static const Color depthFillGood = Color(0xFF4CD966);

  /// Depth bar fill — excessive zone.
  static const Color depthFillBad = Color(0xFFFF6B6B);

  /// Depth bar track background — barely-visible white layer on dark card.
  static const Color depthBarTrack = Color(0x35FFFFFF);

  /// Depth bar pill inactive fill — deep navy.
  static const Color depthBarPillBg = Color(0xFF0F2D5C);

  // ═══════════════════════════════════════════════════════
  // FREQUENCY NEEDLE (on dark card)
  // ═══════════════════════════════════════════════════════

  /// Needle body fill — cool periwinkle blue.
  static const Color needleFill = Color(0xFF93C5FD);

  /// Needle tip / triangle — near-white blue.
  static const Color needleTip = Color(0xFFDBEAFE);

  /// Needle pivot circle shadow.
  static const Color needleShadow = Color(0x44000000);

  // ── Gamification ────────────────────────────────────────────────────────────
  /// Gold gradient start/end for personal best banner.
  static const Color pbGoldDark  = Color(0xFFB8860B);
  /// Gold gradient midpoint — pure gold.
  static const Color pbGoldLight = Color(0xFFFFD700);
  /// Dark brown text on gold — high contrast.
  static const Color pbGoldText  = Color(0xFF3D2000);

// ── Session Trend Banner ─────────────────────────────────────────────────────
  /// Trend improving — line, dots, accent text.
  static const Color trendImproving     = Color(0xFF4CD966);   // reuses feedbackGood
  /// Trend improving — dark badge background (deep green).
  static const Color trendImprovingDark = Color(0xFF1A6B38);
  /// Trend improving — pill/callout background.
  static const Color trendImprovingBg   = Color(0x334CD966);   // 20% feedbackGood

  /// Trend declining — line, dots, accent text.
  static const Color trendDeclining     = Color(0xFFFF6B6B);   // reuses feedbackBad
  /// Trend declining — dark badge background (deep red).
  static const Color trendDecliningDark = Color(0xFF8B2020);
  /// Trend declining — pill/callout background.
  static const Color trendDecliningBg   = Color(0x33FF6B6B);   // 20% feedbackBad

  /// Trend neutral/inconsistent — line, dots, accent text.
  static const Color trendNeutral       = Color(0xFFFFB347);   // reuses feedbackWarn
  /// Trend neutral — dark badge background (deep amber).
  static const Color trendNeutralDark   = Color(0xFF7A4800);
  /// Trend neutral — pill/callout background.
  static const Color trendNeutralBg     = Color(0x33FFB347);   // 20% feedbackWarn

  // ── Session Compare Slot Colors ──────────────────────────────────────────────
  /// Compare slot 1 — brand blue (same as primary).
  static const Color compareSlot2 = Color(0xFFE65100);   // deep orange
  static const Color compareSlot3 = Color(0xFF00897B);   // teal-green
  static const Color compareSlot4 = Color(0xFFF9A825);   // amber

  // ═══════════════════════════════════════════════════════
  // TEXT HIERARCHY
  // ═══════════════════════════════════════════════════════

  /// Near-black — headings, primary body text.
  static const Color textPrimary = Color(0xFF111827);

  /// Mid grey — secondary body, captions, metadata.
  static const Color textSecondary = Color(0xFF4B5563);

  /// Disabled state — labels, placeholders, inactive icons.
  static const Color textDisabled = Color(0xFF9CA3AF);

  /// Form placeholder text only.
  static const Color textHint = Color(0xFFC4C9D1);

  /// White text / icons on any dark background.
  static const Color textOnDark = Color(0xFFFFFFFF);

  // ═══════════════════════════════════════════════════════
  // SCENARIO
  // ═══════════════════════════════════════════════════════

  /// Pediatric mode accent — teal.
  static const Color pediatric = Color(0xFF057692);

  /// Teal — Competent level accent, readable on dark surfaces.
  static const Color feedbackTeal = Color(0xFF40C4C4);

  /// Pediatric mode background tint.
  static const Color pediatricLight = Color(0xFFE0F7FA);

  // ═══════════════════════════════════════════════════════
  // BACKGROUNDS & SURFACES
  // ═══════════════════════════════════════════════════════

  static const Color transparent = Color(0x00000000);

  /// Pure white — screens, cards, dialogs, header, sheets.
  static const Color white = Color(0xFFFFFFFF);

  /// Cool grey-blue screen bg — lists, settings, achievements.
  static const Color screenBgGrey = Color(0xFFF2F6FC);

  /// Dividers and borders — visible against both white and screenBgGrey.
  static const Color divider = Color(0xFFE8EEF6);

  // Overlays
  static const Color tooltipDark  = Color(0xFF0A0E1A); // dark chart tooltip bg
  static const Color overlayDark  = Color(0x80000000);
  static const Color overlayLight = Color(0x1A000000);

  // ═══════════════════════════════════════════════════════
  // AED MAP
  // ═══════════════════════════════════════════════════════

  /// AED open-status border and map cluster fill — same green as success.
  static const Color aedOpen = Color(0xFF2E7D32);

  /// AED closed / unavailable opacity multiplier.
  static const double aedClosedOpacity = 0.5;

  /// Walking / driving route lines and transport icons — darker forest green.
  static const Color aedNavGreen = Color(0xFF006636);

  /// AED cluster marker outer ring — lime green.
  static const Color aedClusterRing = Color(0xFF93C01F);

  /// Scrollbar thumb in AED side panels.
  static const Color scrollThumb = Color(0xFFC2D9F2);

  // ═══════════════════════════════════════════════════════
  // SHADOWS
  // Use via AppDecorations only — avoid direct widget use.
  // ═══════════════════════════════════════════════════════

  static const Color shadowDefault = Color(0x0D000000);
  static const Color shadowMedium  = Color(0x1A000000);
  static const Color shadowStrong  = Color(0x1F000000);
}