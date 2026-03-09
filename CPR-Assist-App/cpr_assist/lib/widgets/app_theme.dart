import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SHARED THEME CONSTANTS
// Import this wherever you need consistent colors / styles
// ─────────────────────────────────────────────────────────────────────────────

const kPrimary      = Color(0xFF194E9D);
const kPrimaryLight = Color(0xFFEDF4F9);
const kPrimaryMid   = Color(0xFFE3EFF8);
const kEmergency    = Color(0xFFB53B3B);
const kEmergencyBg  = Color(0xFFFDF0F0);
const kTraining     = Color(0xFFC47A00);
const kTrainingBg   = Color(0xFFFFF8EC);
const kSuccess      = Color(0xFF2E7D52);
const kSuccessBg    = Color(0xFFEDF7F2);
const kDivider      = Color(0xFFEEF2F7);
const kTextDark     = Color(0xFF111827);
const kTextMid      = Color(0xFF4B5563);
const kTextLight    = Color(0xFF9CA3AF);
const kBgGrey       = Color(0xFFF4F7FB);

// ── Text styles ───────────────────────────────────────────────────────────────

TextStyle kHeading({double size = 18, Color color = kTextDark}) => TextStyle(
  fontSize: size,
  fontWeight: FontWeight.w800,
  color: color,
  letterSpacing: -0.3,
);

TextStyle kBody({double size = 14, Color color = kTextMid}) => TextStyle(
  fontSize: size,
  fontWeight: FontWeight.w400,
  color: color,
  height: 1.5,
);

TextStyle kLabel({double size = 12, Color color = kTextLight}) => TextStyle(
  fontSize: size,
  fontWeight: FontWeight.w600,
  color: color,
  letterSpacing: 0.3,
);

// ── Reusable decoration ───────────────────────────────────────────────────────

BoxDecoration kCardDecoration({Color? color, double radius = 14}) =>
    BoxDecoration(
      color: color ?? Colors.white,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ],
    );

// ── Helpers ───────────────────────────────────────────────────────────────────

String getInitials(String? username) {
  if (username == null || username.trim().isEmpty) return '?';
  final parts = username.trim().split(' ');
  if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  final s = username.trim();
  return s.substring(0, s.length >= 2 ? 2 : 1).toUpperCase();
}