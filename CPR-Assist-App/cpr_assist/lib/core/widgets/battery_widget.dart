import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:cpr_assist/core/core.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GloveBatteryIndicator
//
// Displays an SVG battery icon that reflects the current charge level
// and charging state of the CPR glove.
// Thresholds are sourced from AppConstants — never hardcode percentages.
// ─────────────────────────────────────────────────────────────────────────────

class GloveBatteryIndicator extends StatelessWidget {
  final int batteryPercentage;
  final bool isCharging;

  const GloveBatteryIndicator({
    super.key,
    required this.batteryPercentage,
    this.isCharging = false,
  });

  String _icon() {
    if (isCharging) return 'assets/icons/battery_charging.svg';
    if (batteryPercentage >= AppConstants.batteryFull)    return 'assets/icons/battery_100.svg';
    if (batteryPercentage >= AppConstants.batteryHigh)    return 'assets/icons/battery_70.svg';
    if (batteryPercentage >= AppConstants.batteryMedium)  return 'assets/icons/battery_50.svg';
    if (batteryPercentage >= AppConstants.batteryLow)     return 'assets/icons/battery_30.svg';
    return 'assets/icons/battery_1.svg';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xs + AppSpacing.xxs), // 6
      child: SvgPicture.asset(
        _icon(),
        width: AppSpacing.iconMd - AppSpacing.xxs,  // 22
        height: AppSpacing.iconMd - AppSpacing.xxs,
      ),
    );
  }
}