import 'package:flutter/material.dart';
import 'app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// APP DIALOGS
// All confirmation / alert dialogs used across the app.
// Each returns a Future<bool?> — true = confirmed, false/null = cancelled.
// ─────────────────────────────────────────────────────────────────────────────

class AppDialogs {
  AppDialogs._();

  // ── Logout confirmation ───────────────────────────────────────────────────

  static Future<bool?> confirmLogout(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (_) => const _ConfirmDialog(
        icon: Icons.logout_rounded,
        iconColor: kEmergency,
        iconBg: kEmergencyBg,
        title: 'Log Out',
        message: 'Youll be returned to the login screen. Any active session data will be saved.',
      confirmLabel: 'Log Out',
        confirmColor: kEmergency,
        cancelLabel: 'Cancel',
      ),
    );
  }

  // ── Switch to Training Mode ───────────────────────────────────────────────

  static Future<bool?> confirmSwitchToTraining(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (_) => const _ConfirmDialog(
        icon: Icons.school_outlined,
        iconColor: kTraining,
        iconBg: kTrainingBg,
        title: 'Switch to Training Mode',
        message:
        'You\'ll practice CPR with real-time feedback. Sessions are recorded and graded.\n\nThis is not for real emergencies.',
        confirmLabel: 'Switch to Training',
        confirmColor: kTraining,
        cancelLabel: 'Cancel',
        badge: _ModeBadge(label: 'TRAINING', color: kTraining, bg: kTrainingBg),
      ),
    );
  }

  // ── Switch to Emergency Mode ──────────────────────────────────────────────

  static Future<bool?> confirmSwitchToEmergency(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (_) => const _ConfirmDialog(
        icon: Icons.emergency_outlined,
        iconColor: kPrimary,
        iconBg: kPrimaryLight,
        title: 'Switch to Emergency Mode',
        message:
        'For real cardiac arrest situations only. Sessions are not recorded or graded.',
        confirmLabel: 'Switch to Emergency',
        confirmColor: kPrimary,
        cancelLabel: 'Cancel',
        badge: _ModeBadge(label: 'LIVE', color: kPrimary, bg: kPrimaryLight),
      ),
    );
  }

  // ── Login required ────────────────────────────────────────────────────────

  static Future<bool?> promptLogin(
      BuildContext context, {
        String reason =
        'Training Mode requires an account to save sessions and track your progress.',
      }) {
    return showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (_) => _ConfirmDialog(
        icon: Icons.lock_outline_rounded,
        iconColor: kPrimary,
        iconBg: kPrimaryLight,
        title: 'Login Required',
        message: reason,
        confirmLabel: 'Log In',
        confirmColor: kPrimary,
        cancelLabel: 'Not Now',
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PRIVATE — _ConfirmDialog
// ─────────────────────────────────────────────────────────────────────────────

class _ConfirmDialog extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String message;
  final String confirmLabel;
  final Color confirmColor;
  final String cancelLabel;
  final Widget? badge;

  const _ConfirmDialog({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.confirmColor,
    required this.cancelLabel,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 48),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 30,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Top section ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
              child: Column(
                children: [
                  // Icon circle
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: iconBg,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: iconColor, size: 28),
                  ),
                  const SizedBox(height: 16),

                  // Mode badge (optional)
                  if (badge != null) ...[
                    badge!,
                    const SizedBox(height: 12),
                  ],

                  // Title
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: kHeading(size: 17),
                  ),
                  const SizedBox(height: 8),

                  // Message
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: kBody(size: 13, color: kTextMid),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),

            // ── Divider ──────────────────────────────────────────────────────
            const Divider(height: 1, color: kDivider),

            // ── Buttons ──────────────────────────────────────────────────────
            IntrinsicHeight(
              child: Row(
                children: [
                  // Cancel
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: const RoundedRectangleBorder(
                          borderRadius:
                          BorderRadius.only(bottomLeft: Radius.circular(20)),
                        ),
                      ),
                      child: Text(
                        cancelLabel,
                        style: kBody(size: 15, color: kTextMid).copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),

                  // Vertical divider
                  const VerticalDivider(width: 1, color: kDivider),

                  // Confirm
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.only(
                              bottomRight: Radius.circular(20)),
                        ),
                      ),
                      child: Text(
                        confirmLabel,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: confirmColor,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PRIVATE — _ModeBadge
// ─────────────────────────────────────────────────────────────────────────────

class _ModeBadge extends StatelessWidget {
  final String label;
  final Color color;
  final Color bg;

  const _ModeBadge({
    required this.label,
    required this.color,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}