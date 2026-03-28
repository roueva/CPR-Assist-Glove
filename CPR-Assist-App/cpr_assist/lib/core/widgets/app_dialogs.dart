import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cpr_assist/core/core.dart';

// ─────────────────────────────────────────────────────────────────────────────
// APP DIALOGS
// All confirmation / alert dialogs used across the app.
// Each returns Future<bool?> — true = confirmed, false / null = cancelled.
//
// Rules:
//   - No hardcoded colors or sizes — use AppColors / AppSpacing.
//   - Add new dialogs as static methods here; never use showDialog inline.
// ─────────────────────────────────────────────────────────────────────────────

class AppDialogs {
  AppDialogs._();

  // ── Logout ────────────────────────────────────────────────────────────────

  static Future<bool?> confirmLogout(BuildContext context) {
    return _show(
      context,
      dialog: const _ConfirmDialog(
        icon: Icons.logout_rounded,
        iconColor: AppColors.emergencyRed,
        iconBg: AppColors.emergencyBg,
        title: 'Log Out',
        message:
        'You\'ll be returned to the login screen. Any active session data will be saved.',
        confirmLabel: 'Log Out',
        confirmColor: AppColors.emergencyRed,
        cancelLabel: 'Cancel',
      ),
    );
  }

  static Future<bool?> confirmDeleteAccount(BuildContext context) {
    return _show(
      context,
      dialog: const _ConfirmDialog(
        icon:         Icons.delete_forever_rounded,
        iconColor:    AppColors.emergencyRed,
        iconBg:       AppColors.emergencyBg,
        title:        'Delete Account?',
        message:      'This permanently deletes your account, all sessions, and scores. '
            'This cannot be undone.',
        confirmLabel: 'Delete Account',
        confirmColor: AppColors.emergencyRed,
        cancelLabel:  'Cancel',
      ),
    );
  }

  // ── Switch to Training Mode ───────────────────────────────────────────────

  static Future<bool?> confirmSwitchToTraining(BuildContext context) {
    return _show(
      context,
      dialog: const _ConfirmDialog(
        icon: Icons.school_outlined,
        iconColor: AppColors.warning,
        iconBg: AppColors.warningBg,
        title: 'Switch to Training Mode',
        message:
        'You\'ll practice CPR with real-time feedback. Sessions are recorded and graded.\n\nThis is not for real emergencies.',
        confirmLabel: 'Switch to Training',
        confirmColor: AppColors.warning,
        cancelLabel: 'Cancel',
        badge: _ModeBadge(
          label: 'TRAINING',
          color: AppColors.warning,
          bg: AppColors.warningBg,
        ),
      ),
    );
  }

  // ── Pre-session training checklist ───────────────────────────────────────

  static Future<bool?> showTrainingChecklist(BuildContext context) {
    return _show(
      context,
      dialog: const _ConfirmDialog(
        icon:         Icons.checklist_rounded,
        iconColor:    AppColors.warning,
        iconBg:       AppColors.warningBg,
        title:        'Ready to Start?',
        message:
        '• Manikin placed on a firm, flat surface\n'
            '• Glove fitted snugly — sensors over fingertips\n'
            '• Hands positioned centre of chest\n'
            '• Elbows locked, arms straight\n\n'
            'Press Start on the glove when ready.',
        confirmLabel: 'I\'m Ready',
        confirmColor: AppColors.warning,
        cancelLabel:  'Not Yet',
      ),
    );
  }

  // ── Switch to Emergency Mode ──────────────────────────────────────────────

  static Future<bool?> confirmSwitchToEmergency(BuildContext context) {
    return _show(
      context,
      dialog: const _ConfirmDialog(
        icon: Icons.emergency_outlined,
        iconColor: AppColors.primary,
        iconBg: AppColors.primaryLight,
        title: 'Switch to Emergency Mode',
        message:
        'For real cardiac arrest situations only. Sessions are not recorded or graded.',
        confirmLabel: 'Switch to Emergency',
        confirmColor: AppColors.primary,
        cancelLabel: 'Cancel',
        badge: _ModeBadge(
          label: 'LIVE',
          color: AppColors.primary,
          bg: AppColors.primaryLight,
        ),
      ),
    );
  }

  // ── Login required ────────────────────────────────────────────────────────

  static Future<bool?> promptLogin(
      BuildContext context, {
        String reason =
        'Training Mode requires an account to save sessions and track your progress.',
      }) {
    return _show(
      context,
      dialog: _ConfirmDialog(
        icon: Icons.lock_outline_rounded,
        iconColor: AppColors.primary,
        iconBg: AppColors.primaryLight,
        title: 'Login Required',
        message: reason,
        confirmLabel: 'Log In',
        confirmColor: AppColors.primary,
        cancelLabel: 'Not Now',
      ),
    );
  }

  // ── Generic destructive confirm (delete, reset, etc.) ─────────────────────
  //
  // Replaces every inline showDialog used for destructive actions.
  // Returns true = confirmed, false/null = cancelled.

  static Future<bool?> showDestructiveConfirm(
      BuildContext context, {
        required IconData icon,
        required Color    iconColor,
        required Color    iconBg,
        required String   title,
        required String   message,
        required String   confirmLabel,
        required Color    confirmColor,
        required String   cancelLabel,
      }) {
    return _show(
      context,
      dialog: _ConfirmDialog(
        icon:         icon,
        iconColor:    iconColor,
        iconBg:       iconBg,
        title:        title,
        message:      message,
        confirmLabel: confirmLabel,
        confirmColor: confirmColor,
        cancelLabel:  cancelLabel,
      ),
    );
  }

  // ── Discard unsaved changes ───────────────────────────────────────────────
  //
  // Used by ProfileEditorScreen's PopScope / back button guard.
  // Returns true = discard (allow pop), false/null = keep editing.

  static Future<bool?> confirmDiscard(BuildContext context) {
    return _show(
      context,
      dialog: const _ConfirmDialog(
        icon:         Icons.edit_off_rounded,
        iconColor:    AppColors.warning,
        iconBg:       AppColors.warningBg,
        title:        'Discard changes?',
        message:      'Your unsaved changes will be lost.',
        confirmLabel: 'Discard',
        confirmColor: AppColors.emergencyRed,
        cancelLabel:  'Keep editing',
      ),
    );
  }

  // ── Edit session note ─────────────────────────────────────────────────────

  static Future<String?> showNoteEditor(
      BuildContext context, {
        String? initialNote,
      }) {
    return showDialog<String>(
      context: context,
      barrierColor: AppColors.overlayDark,
      builder: (_) => _NoteEditorDialog(initialNote: initialNote),
    );
  }

// ── Location permission settings ──────────────────────────────────────────

  static Future<bool?> showLocationPermissionSettings(BuildContext context) {
    return _show(
      context,
      dialog: const _ConfirmDialog(
        icon:         Icons.location_off_rounded,
        iconColor:    AppColors.warning,
        iconBg:       AppColors.warningBg,
        title:        'Location Permission Required',
        message:
        'Location access has been permanently denied. To use location features, '
            'please enable location permissions in your device settings.',
        confirmLabel: 'Open Settings',
        confirmColor: AppColors.primary,
        cancelLabel:  'Cancel',
      ),
    );
  }

  // ── Generic info / alert ──────────────────────────────────────────────────

  /// Single-button informational dialog (no cancel).
  static Future<void> showAlert(
      BuildContext context, {
        required String title,
        required String message,
        IconData icon = Icons.info_outline_rounded,
        Color iconColor = AppColors.primary,
        Color iconBg = AppColors.primaryLight,
        String dismissLabel = 'OK',
      }) {
    return showDialog<void>(
      context: context,
      barrierColor: AppColors.overlayDark,
      builder: (_) => _AlertDialog(
        icon: icon,
        iconColor: iconColor,
        iconBg: iconBg,
        title: title,
        message: message,
        dismissLabel: dismissLabel,
      ),
    );
  }

  // ── AED Share ─────────────────────────────────────────────────────────────

  static Future<void> showAEDShare(
      BuildContext context, {
        required String aedName,
        required double latitude,
        required double longitude,
      }) {
    return showDialog<void>(
      context: context,
      barrierColor: AppColors.overlayDark,
      builder: (_) => _AEDShareDialog(
        aedName: aedName,
        latitude: latitude,
        longitude: longitude,
      ),
    );
  }

  // ── KSL Info ──────────────────────────────────────────────────────────────

  static Future<void> showKSLInfo(
      BuildContext context, {
        required VoidCallback onVisitWebsite,
      }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: AppColors.overlayDark,
      builder: (_) => _KSLInfoDialog(onVisitWebsite: onVisitWebsite),
    );
  }

  // ── Private ───────────────────────────────────────────────────────────────

  static Future<bool?> _show(
      BuildContext context, {
        required Widget dialog,
      }) {
    return showDialog<bool>(
      context: context,
      barrierColor: AppColors.overlayDark,
      builder: (_) => dialog,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ConfirmDialog — two-button (cancel + confirm)
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
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.dialogInsetH,
        vertical: AppSpacing.dialogInsetV,
      ),
      child: Container(
        decoration: AppDecorations.dialog(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Top section ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.dialogPaddingH,
                AppSpacing.dialogPaddingTop,
                AppSpacing.dialogPaddingH,
                0,
              ),
              child: Column(
                children: [
                  // Icon circle
                  _IconCircle(icon: icon, color: iconColor, bg: iconBg),
                  const SizedBox(height: AppSpacing.md),

                  // Mode badge (optional)
                  if (badge != null) ...[
                    badge!,
                    const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
                  ],

                  // Title
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: AppTypography.heading(size: 17),
                  ),
                  const SizedBox(height: AppSpacing.sm),

                  // Message
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: AppTypography.body(
                      size: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
              ),
            ),

            // ── Divider ────────────────────────────────────────────────────
            const Divider(height: 1, color: AppColors.divider),

            // ── Buttons ────────────────────────────────────────────────────
            IntrinsicHeight(
              child: Row(
                children: [
                  // Cancel
                  Expanded(
                    child: TextButton(
                      onPressed: () => context.pop(false),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.md,
                        ),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.only(
                            bottomLeft: Radius.circular(AppSpacing.dialogRadius),
                          ),
                        ),
                      ),
                      child: Text(
                        cancelLabel,
                        style: AppTypography.body(
                          size: 15,
                          color: AppColors.textSecondary,
                        ).copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),

                  // Vertical divider
                  const VerticalDivider(width: 1, color: AppColors.divider),

                  // Confirm
                  Expanded(
                    child: TextButton(
                      onPressed: () => context.pop(true),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.md,
                        ),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.only(
                            bottomRight:
                            Radius.circular(AppSpacing.dialogRadius),
                          ),
                        ),
                      ),
                      child: Text(
                        confirmLabel,
                        style: AppTypography.bodyBold(
                          size: 15,
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
// _AlertDialog — single dismiss button
// ─────────────────────────────────────────────────────────────────────────────

class _AlertDialog extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String message;
  final String dismissLabel;

  const _AlertDialog({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.message,
    required this.dismissLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.dialogInsetH,
        vertical: AppSpacing.dialogInsetV,
      ),
      child: Container(
        decoration: AppDecorations.dialog(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.dialogPaddingH,
                AppSpacing.dialogPaddingTop,
                AppSpacing.dialogPaddingH,
                AppSpacing.lg,
              ),
              child: Column(
                children: [
                  _IconCircle(icon: icon, color: iconColor, bg: iconBg),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: AppTypography.heading(size: 17),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: AppTypography.body(
                      size: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.divider),
            TextButton(
              onPressed: () => context.pop(),
              style: TextButton.styleFrom(
                minimumSize: const Size(double.infinity, AppSpacing.touchTargetLarge),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(AppSpacing.dialogRadius),
                    bottomRight: Radius.circular(AppSpacing.dialogRadius),
                  ),
                ),
              ),
              child: Text(
                dismissLabel,
                style: AppTypography.bodyBold(
                  size: 15,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _IconCircle — shared icon container
// ─────────────────────────────────────────────────────────────────────────────

class _IconCircle extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color bg;

  const _IconCircle({
    required this.icon,
    required this.color,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppSpacing.iconXl + AppSpacing.sm,   // 56
      height: AppSpacing.iconXl + AppSpacing.sm,  // 56
      decoration: AppDecorations.iconCircle(bg: bg),
      child: Icon(icon, color: color, size: AppSpacing.iconLg - AppSpacing.xs),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ModeBadge — pill label (TRAINING / LIVE)
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
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.chipPaddingH,
        vertical: AppSpacing.chipPaddingV,
      ),
      decoration: AppDecorations.chip(color: color, bg: bg),
      child: Text(label, style: AppTypography.badge(color: color)),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// _AEDShareDialog
// ─────────────────────────────────────────────────────────────────────────────

class _AEDShareDialog extends StatelessWidget {
  final String aedName;
  final double latitude;
  final double longitude;

  const _AEDShareDialog({
    required this.aedName,
    required this.latitude,
    required this.longitude,
  });

  String get _mapsUrl =>
      'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude';

  String get _shareText =>
      '🚨 AED Location: $aedName\n'
          '📍 $latitude, $longitude\n'
          '🗺️ $_mapsUrl';

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.dialogInsetH,
        vertical: AppSpacing.dialogInsetV,
      ),
      child: Container(
        decoration: AppDecorations.dialog(),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm + AppSpacing.xs),
                  decoration: AppDecorations.iconRounded(bg: AppColors.primaryLight),
                  child: const Icon(
                    Icons.share,
                    color: AppColors.primary,
                    size: AppSpacing.iconMd,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Share AED Location', style: AppTypography.heading(size: 17)),
                      Text(
                        aedName,
                        style: AppTypography.caption(color: AppColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.lg),

            // ── QR Code ─────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: AppDecorations.card(),
              child: Column(
                children: [
                  QrImageView(
                    data: _mapsUrl,
                    version: QrVersions.auto,
                    size: AppConstants.qrCodeSize,
                    backgroundColor: AppColors.surfaceWhite,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Scan to open in Google Maps',
                    style: AppTypography.caption(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.md + AppSpacing.xs),

            // ── Action buttons ───────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: _ShareActionButton(
                    icon: Icons.copy,
                    label: 'Copy Link',
                    color: AppColors.primary,
                    bg: AppColors.primaryLight,
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: _mapsUrl));
                      if (context.mounted) {
                        context.pop();
                        UIHelper.showSuccess(context, 'Link copied to clipboard');
                      }
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
                Expanded(
                  child: _ShareActionButton(
                    icon: Icons.share,
                    label: 'Share',
                    color: AppColors.success,
                    bg: AppColors.successBg,
                    onTap: () async {
                      context.pop();
                      await Share.share(_shareText, subject: 'AED Location: $aedName');
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.sm),

            // ── Close ────────────────────────────────────────────────────────
            TextButton(
              onPressed: () => context.pop(),
              style: TextButton.styleFrom(
                minimumSize: const Size(double.infinity, AppSpacing.touchTargetMin),
              ),
              child: Text(
                'Close',
                style: AppTypography.body(color: AppColors.textSecondary)
                    .copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ShareActionButton
// ─────────────────────────────────────────────────────────────────────────────

class _ShareActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color bg;
  final VoidCallback onTap;

  const _ShareActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.bg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.buttonPaddingV),
        decoration: AppDecorations.chip(color: color, bg: bg),
        child: Column(
          children: [
            Icon(icon, color: color, size: AppSpacing.iconMd),
            const SizedBox(height: AppSpacing.cardSpacing),
            Text(label, style: AppTypography.label(color: color)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _KSLInfoDialog
// ─────────────────────────────────────────────────────────────────────────────

class _KSLInfoDialog extends StatelessWidget {
  final VoidCallback onVisitWebsite;

  const _KSLInfoDialog({required this.onVisitWebsite});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Container(
        decoration: AppDecorations.dialog(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header — brand blue ──────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                vertical: AppSpacing.md + AppSpacing.xs,
              ),
              decoration: AppDecorations.dialogHeader(),
              child: Column(
                children: [
                  Image.asset(
                    'assets/icons/kids_save_lives_logo.png',
                    height: AppSpacing.iconXl + AppSpacing.sm,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
                  Text(
                    'Kids Save Lives',
                    style: AppTypography.subheading(color: AppColors.textOnDark),
                  ),
                ],
              ),
            ),

            // ── Body ────────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: Text(
                'AED data in this app is provided by the Kids Save Lives foundation '
                    'via the iSaveLives.gr registry.',
                textAlign: TextAlign.center,
                style: AppTypography.body(color: AppColors.textSecondary),
              ),
            ),

            // ── Buttons ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => context.pop(),
                      child: Text(
                        'Close',
                        style: AppTypography.body(color: AppColors.textSecondary)
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        context.pop();
                        onVisitWebsite();
                      },
                      child: const Text('Visit Website'),
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
// _NoteEditorDialog
// ─────────────────────────────────────────────────────────────────────────────

class _NoteEditorDialog extends StatefulWidget {
  final String? initialNote;
  const _NoteEditorDialog({this.initialNote});

  @override
  State<_NoteEditorDialog> createState() => _NoteEditorDialogState();
}

class _NoteEditorDialogState extends State<_NoteEditorDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialNote ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.dialogInsetH,
        vertical:   AppSpacing.dialogInsetV,
      ),
      child: Container(
        decoration: AppDecorations.dialog(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.dialogPaddingH,
                AppSpacing.dialogPaddingTop,
                AppSpacing.dialogPaddingH,
                AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Session Note', style: AppTypography.heading(size: 17)),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller:  _controller,
                    maxLines:    4,
                    maxLength:   300,
                    style:       AppTypography.body(size: 14),
                    decoration: InputDecoration(
                      hintText:    'Add a note about this session…',
                      hintStyle:   AppTypography.body(
                          size: 14, color: AppColors.textDisabled),
                      filled:      true,
                      fillColor:   AppColors.screenBgGrey,
                      border: OutlineInputBorder(
                        borderRadius:
                        BorderRadius.circular(AppSpacing.cardRadiusSm),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius:
                        BorderRadius.circular(AppSpacing.cardRadiusSm),
                        borderSide: const BorderSide(
                            color: AppColors.primary, width: 1.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.divider),
            IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => context.pop(),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.md),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.only(
                            bottomLeft:
                            Radius.circular(AppSpacing.dialogRadius),
                          ),
                        ),
                      ),
                      child: Text('Cancel',
                          style: AppTypography.body(
                              size: 15, color: AppColors.textSecondary)
                              .copyWith(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const VerticalDivider(width: 1, color: AppColors.divider),
                  Expanded(
                    child: TextButton(
                      onPressed: () => context.pop(_controller.text),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.md),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.only(
                            bottomRight:
                            Radius.circular(AppSpacing.dialogRadius),
                          ),
                        ),
                      ),
                      child: Text('Save',
                          style: AppTypography.bodyBold(
                              size: 15, color: AppColors.primary)),
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