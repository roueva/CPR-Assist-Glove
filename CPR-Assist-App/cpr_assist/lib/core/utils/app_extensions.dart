import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// **App Extensions — Shortcut helpers available on common Flutter types**
///
/// Usage:
///   context.colors.primary
///   context.typography.heading()
///   context.screenWidth
///   'hello world'.capitalize()
///   'John Doe'.initials  → 'JD'


// ═══════════════════════════════════════════════════════
// BuildContext — Theme shortcuts
// ═══════════════════════════════════════════════════════

extension BuildContextTheme on BuildContext {
  ThemeData    get theme       => Theme.of(this);
  TextTheme    get textTheme   => Theme.of(this).textTheme;
  ColorScheme  get colorScheme => Theme.of(this).colorScheme;

  /// Quick access to AppColors — e.g. context.colors.primary
  AppColorsProxy get colors   => const AppColorsProxy();

  /// Quick access to AppTypography — e.g. context.typography.heading()
  AppTypographyProxy get typography => const AppTypographyProxy();
}

// ─── Internal proxy so context.colors.xxx works without static ───────────────
class AppColorsProxy {
  const AppColorsProxy();

  Color get primary        => AppColors.primary;
  Color get primaryLight   => AppColors.primaryLight;
  Color get success        => AppColors.success;
  Color get warning        => AppColors.warning;
  Color get error          => AppColors.error;
  Color get emergencyRed   => AppColors.emergencyRed;
  Color get textPrimary    => AppColors.textPrimary;
  Color get textSecondary  => AppColors.textSecondary;
  Color get textDisabled   => AppColors.textDisabled;
  Color get divider        => AppColors.divider;
  Color get screenBg       => AppColors.screenBg;
  Color get cardBg         => AppColors.cardBg;
}

// ─── Proxy so context.typography.xxx works without static calls ──────────────
class AppTypographyProxy {
  const AppTypographyProxy();

  TextStyle heading({double size = 18, Color color = AppColors.textPrimary}) =>
      AppTypography.heading(size: size, color: color);

  TextStyle subheading({double size = 15, Color color = AppColors.textPrimary}) =>
      AppTypography.subheading(size: size, color: color);

  TextStyle body({double size = 14, Color color = AppColors.textSecondary}) =>
      AppTypography.body(size: size, color: color);

  TextStyle bodyMedium({double size = 14, Color color = AppColors.textPrimary}) =>
      AppTypography.bodyMedium(size: size, color: color);

  TextStyle bodyBold({double size = 14, Color color = AppColors.textPrimary}) =>
      AppTypography.bodyBold(size: size, color: color);

  TextStyle label({double size = 12, Color color = AppColors.textDisabled}) =>
      AppTypography.label(size: size, color: color);

  TextStyle caption({Color color = AppColors.textDisabled}) =>
      AppTypography.caption(color: color);

  TextStyle badge({double size = 11, Color color = AppColors.textPrimary}) =>
      AppTypography.badge(size: size, color: color);

  TextStyle buttonPrimary() => AppTypography.buttonPrimary();
  TextStyle buttonSecondary({Color color = AppColors.primary}) =>
      AppTypography.buttonSecondary(color: color);

  TextStyle appTitle()       => AppTypography.appTitle();
  TextStyle navSelected()    => AppTypography.navSelected();
  TextStyle navUnselected()  => AppTypography.navUnselected();
}

// ═══════════════════════════════════════════════════════
// BuildContext — Layout helpers
// ═══════════════════════════════════════════════════════

extension BuildContextLayout on BuildContext {
  MediaQueryData get mediaQuery    => MediaQuery.of(this);
  Size           get screenSize    => MediaQuery.sizeOf(this);
  double         get screenWidth   => MediaQuery.sizeOf(this).width;
  double         get screenHeight  => MediaQuery.sizeOf(this).height;
  EdgeInsets     get padding       => MediaQuery.paddingOf(this);
  EdgeInsets     get viewInsets    => MediaQuery.viewInsetsOf(this);

  bool get isLandscape =>
      MediaQuery.orientationOf(this) == Orientation.landscape;
  bool get isPortrait =>
      MediaQuery.orientationOf(this) == Orientation.portrait;

  /// True if screen width < 600dp (phone)
  bool get isPhone  => screenWidth < 600;
  /// True if screen width >= 600dp (tablet)
  bool get isTablet => screenWidth >= 600;

  /// Safe bottom padding (above home indicator / nav bar)
  double get safeBottom => padding.bottom;

  /// Available height minus padding
  double get usableHeight => screenHeight - padding.top - padding.bottom;
}

// ═══════════════════════════════════════════════════════
// BuildContext — Navigation shortcuts
// ═══════════════════════════════════════════════════════

extension BuildContextNavigation on BuildContext {
  void pop<T>([T? result]) => Navigator.of(this).pop(result);

  Future<T?> push<T>(Widget page) => Navigator.of(this).push<T>(
    MaterialPageRoute(builder: (_) => page),
  );

  Future<T?> pushReplacement<T>(Widget page) =>
      Navigator.of(this).pushReplacement<T, void>(
        MaterialPageRoute(builder: (_) => page),
      );

  Future<T?> pushAndRemoveAll<T>(Widget page) =>
      Navigator.of(this).pushAndRemoveUntil<T>(
        MaterialPageRoute(builder: (_) => page),
            (_) => false,
      );
}

// ═══════════════════════════════════════════════════════
// String extensions
// ═══════════════════════════════════════════════════════

extension StringX on String {
  /// 'hello world' → 'Hello world'
  String get capitalize {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }

  /// 'hello world' → 'Hello World'
  String get titleCase => split(' ')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  /// Extracts up to 2 uppercase initials from a display name.
  /// 'John Doe' → 'JD' | 'Alice' → 'AL' | '' → '?'
  String get initials {
    final trimmed = trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return trimmed.substring(0, trimmed.length >= 2 ? 2 : 1).toUpperCase();
  }

  /// True if string is a valid email format
  bool get isValidEmail => RegExp(
    r'^[\w.-]+@([\w-]+\.)+[\w-]{2,4}$',
  ).hasMatch(this);

  /// True if string is a valid Greek phone number (10 digits starting with 6/2)
  bool get isValidGreekPhone =>
      RegExp(r'^(6\d{9}|2\d{9})$').hasMatch(replaceAll(' ', ''));

  /// Null-safe trim + empty check
  bool get isBlank => trim().isEmpty;
  bool get isNotBlank => trim().isNotEmpty;
}

extension NullableStringX on String? {
  bool get isNullOrBlank => this == null || this!.trim().isEmpty;
  String get orEmpty => this ?? '';
  String get initials => this?.initials ?? '?';
}

// ═══════════════════════════════════════════════════════
// num / double extensions
// ═══════════════════════════════════════════════════════

extension NumX on num {
  /// 1250 → '1.25 km' | 800 → '800 m'
  String get asDistance =>
      this >= 1000 ? '${(this / 1000).toStringAsFixed(2)} km' : '${toInt()} m';

  /// 90 → '1 min' | 3600 → '1 h' | 3720 → '1 h 2 min'
  String get asEta {
    final mins = (this / 60).ceil();
    if (mins < 60) return '$mins min';
    final h = mins ~/ 60;
    final m = mins % 60;
    return m == 0 ? '$h h' : '$h h $m min';
  }

  /// Clamps to [0.0, 1.0]
  double get clampedProgress => toDouble().clamp(0.0, 1.0);
}

// ═══════════════════════════════════════════════════════
// Duration extensions
// ═══════════════════════════════════════════════════════

extension DurationX on Duration {
  /// Duration(seconds: 90) → '1:30'
  String get mmss {
    final m = inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

// ═══════════════════════════════════════════════════════
// DateTime extensions
// ═══════════════════════════════════════════════════════

extension DateTimeX on DateTime {
  /// '14 Jun 2024'
  String get ddMmmYyyy {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '$day ${months[month - 1]} $year';
  }

  /// '14/06/2024'
  String get ddMmYyyy =>
      '${day.toString().padLeft(2, '0')}/${month.toString().padLeft(2, '0')}/$year';

  /// '14:35'
  String get hhmm =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  bool get isToday {
    final now = DateTime.now();
    return year == now.year && month == now.month && day == now.day;
  }
}