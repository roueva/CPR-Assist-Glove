import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// **UIHelper — Common UI operations: snackbars, loading, focus**
///
/// Rules:
///   - No hardcoded colors or sizes — use AppColors / AppSpacing.
///   - Stateless static methods only.
///   - For dialogs, use AppDialogs instead.
class UIHelper {
  UIHelper._();

  // ═══════════════════════════════════════════════════════
  // SNACKBARS
  // ═══════════════════════════════════════════════════════

  /// Standard informational snackbar.
  static void showSnackbar(
      BuildContext context, {
        required String message,
        required IconData icon,
        Color? backgroundColor,
        Duration duration = const Duration(seconds: 3),
        SnackBarAction? action,
      }) {
    _show(
      context,
      message: message,
      icon: icon,
      backgroundColor: backgroundColor ?? AppColors.primary,
      duration: duration,
      action: action,
    );
  }

  /// Success snackbar (green).
  static void showSuccess(
      BuildContext context,
      String message, {
        Duration duration = const Duration(seconds: 3),
      }) {
    _show(
      context,
      message: message,
      icon: Icons.check_circle_outline_rounded,
      backgroundColor: AppColors.success,
      duration: duration,
    );
  }

  /// Error snackbar (red).
  static void showError(
      BuildContext context,
      String message, {
        Duration duration = const Duration(seconds: 4),
        SnackBarAction? action,
      }) {
    _show(
      context,
      message: message,
      icon: Icons.error_outline_rounded,
      backgroundColor: AppColors.error,
      duration: duration,
      action: action,
    );
  }

  /// Warning snackbar (orange).
  static void showWarning(
      BuildContext context,
      String message, {
        Duration duration = const Duration(seconds: 3),
      }) {
    _show(
      context,
      message: message,
      icon: Icons.warning_amber_rounded,
      backgroundColor: AppColors.warning,
      duration: duration,
    );
  }

  /// Snackbar with a tappable action button.
  static void showSnackbarWithAction(
      BuildContext context, {
        required String message,
        required IconData icon,
        required String actionLabel,
        required VoidCallback onAction,
        Color? backgroundColor,
        Duration duration = const Duration(seconds: 6),
      }) {
    _show(
      context,
      message:         message,
      icon:            icon,
      backgroundColor: backgroundColor ?? AppColors.primary,
      duration:        duration,
      action: SnackBarAction(
        label:     actionLabel,
        textColor: AppColors.textOnDark,
        onPressed: onAction,
      ),
    );
  }

  /// Loading snackbar — stays until dismissed.
  /// Call UIHelper.clearSnackbars() when done.
  static void showLoading(BuildContext context, String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: AppSpacing.iconMd,
              height: AppSpacing.iconMd,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.textOnDark),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                message,
                style: AppTypography.snackbar(),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.primary,
        duration: const Duration(seconds: 60), // dismissed manually
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.buttonRadiusSm),
        ),
        margin: const EdgeInsets.all(AppSpacing.md),
      ),
    );
  }

  /// Clears all active snackbars.
  static void clearSnackbars(BuildContext context) {
    ScaffoldMessenger.of(context).clearSnackBars();
  }

  // ═══════════════════════════════════════════════════════
  // FOCUS HELPERS
  // ═══════════════════════════════════════════════════════

  /// Dismisses the keyboard / unfocuses current field.
  static void unfocus(BuildContext context) {
    FocusScope.of(context).unfocus();
  }

  /// Moves focus to the next field (equivalent to pressing Tab/Next on keyboard).
  static void focusNext(BuildContext context) {
    FocusScope.of(context).nextFocus();
  }

  // ═══════════════════════════════════════════════════════
  // PRIVATE
  // ═══════════════════════════════════════════════════════

  static void _show(
      BuildContext context, {
        required String message,
        required IconData icon,
        required Color backgroundColor,
        required Duration duration,
        SnackBarAction? action,
      }) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: AppColors.textOnDark, size: AppSpacing.iconMd),
            const SizedBox(width: AppSpacing.sm + AppSpacing.xs), // 12
            Expanded(
              child: Text(message, style: AppTypography.snackbar()),
            ),
          ],
        ),
        backgroundColor: backgroundColor,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        action: action,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.buttonRadiusSm),
        ),
        margin: const EdgeInsets.all(AppSpacing.md),
      ),
    );
  }
}