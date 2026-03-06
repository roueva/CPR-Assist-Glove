  import 'package:flutter/material.dart';
  import 'package:flutter_svg/flutter_svg.dart';

import '../utils/app_constants.dart';

  class GloveBatteryIndicator extends StatelessWidget {
    final int batteryPercentage;
    final bool isCharging; // ⚡️ Optional future support

    const GloveBatteryIndicator({
      super.key,
      required this.batteryPercentage,
      this.isCharging = false,
    });

    String _getBatteryIcon() {
      if (isCharging) return 'assets/icons/battery_charging.svg';

      // ✅ Use constants instead of hardcoded values
      if (batteryPercentage >= AppConstants.batteryFull) {
        return 'assets/icons/battery_100.svg';
      }
      if (batteryPercentage >= AppConstants.batteryHigh) {
        return 'assets/icons/battery_70.svg';
      }
      if (batteryPercentage >= AppConstants.batteryMedium) {
        return 'assets/icons/battery_50.svg';
      }
      if (batteryPercentage >= AppConstants.batteryLow) {
        return 'assets/icons/battery_30.svg';
      }
      return 'assets/icons/battery_1.svg';
    }

    @override
    Widget build(BuildContext context) {
      return Container(
        padding: const EdgeInsets.all(6),
        child: SvgPicture.asset(
          _getBatteryIcon(),
          width: 22,
          height: 22,
        ),
      );
    }
  }
