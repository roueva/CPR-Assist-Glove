import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';
import '../services/decrypted_data.dart';
import '../utils/safe_fonts.dart';
import '../widgets/account_menu.dart';
import '../widgets/battery_widget.dart';
import '../widgets/ble_status_indicator.dart';
import '../main.dart';

class UniversalHeader extends ConsumerWidget implements PreferredSizeWidget {
  final DecryptedData? decryptedDataHandler;
  final Color backgroundColor;
  final bool showBackButton;
  final VoidCallback? onBackPressed;
  final String? customTitle;

  const UniversalHeader({
    super.key,
    this.decryptedDataHandler,
    required this.backgroundColor,
    this.showBackButton = false,
    this.onBackPressed,
    this.customTitle,
  });

  // ✅ Factory constructors for different screen types
  factory UniversalHeader.forMainScreens({
    required DecryptedData decryptedDataHandler,
    required int currentIndex,
  }) {
    final isDarkBackground = currentIndex == 1 || currentIndex == 2; // Live or Training
    return UniversalHeader(
      decryptedDataHandler: decryptedDataHandler,
      backgroundColor: isDarkBackground ? const Color(0xFFEDF4F9) : Colors.white,
    );
  }

  factory UniversalHeader.forOtherScreens({
    DecryptedData? decryptedDataHandler,
    bool showBackButton = true,
    VoidCallback? onBackPressed,
    String? customTitle,
  }) {
    return UniversalHeader(
      decryptedDataHandler: decryptedDataHandler,
      backgroundColor: const Color(0xFFEDF4F9), // Default to light blue for other screens
      showBackButton: showBackButton,
      onBackPressed: onBackPressed,
      customTitle: customTitle,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(45);

  Color get _widgetBackgroundColor {
    // If main screen background is light blue, widgets should be white
    // If main screen background is white, widgets should be light blue
    return backgroundColor == const Color(0xFFEDF4F9)
        ? Colors.white
        : const Color(0xFFE3EFF8);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppBar(
      toolbarHeight: 45,
      backgroundColor: backgroundColor,
      foregroundColor: Colors.black,
      elevation: 0,
      leading: showBackButton
          ? IconButton(
        icon: const Icon(Icons.arrow_back, color: Color(0xFF194E9D)),
        onPressed: onBackPressed ?? () => Navigator.pop(context),
      )
          : null,
      title: Row(
        mainAxisSize: showBackButton ? MainAxisSize.min : MainAxisSize.max,
        children: [
          SvgPicture.asset(
            "assets/icons/logo.svg",
            width: 28.6,
            height: 28,
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              customTitle ?? "CPR Assist",
              overflow: TextOverflow.ellipsis,
              style: SafeFonts.inter(
                fontWeight: FontWeight.bold,
                fontSize: 22,
                color: const Color(0xFF194E9D),
              ),
            ),
          ),
        ],
      ),
      centerTitle: !showBackButton, // Center only when no back button
      actions: [
        // Show BLE and Battery only if decryptedDataHandler is provided
        if (decryptedDataHandler != null) ...[
          // Bluetooth + Battery Combined Container
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
              decoration: BoxDecoration(
                color: _widgetBackgroundColor,
                borderRadius: BorderRadius.circular(32),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Consumer(
                    builder: (context, ref, child) {
                      final bleConnection = ref.watch(bleConnectionProvider);
                      return BLEStatusIndicator(
                        bleConnection: bleConnection,
                        connectionStatusNotifier: bleConnection.connectionStatusNotifier,
                      );
                    },
                  ),
                  const SizedBox(width: 4),
                  ValueListenableBuilder<int>(
                    valueListenable: decryptedDataHandler!.batteryPercentageNotifier,
                    builder: (context, battery, _) {
                      return ValueListenableBuilder<bool>(
                        valueListenable: decryptedDataHandler!.isChargingNotifier,
                        builder: (context, isCharging, _) {
                          return Tooltip(
                            message: isCharging
                                ? 'Charging: $battery%'
                                : 'Battery: $battery%',
                            triggerMode: TooltipTriggerMode.tap,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            textStyle: const TextStyle(
                              color: Colors.black,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            showDuration: const Duration(seconds: 2),
                            child: GloveBatteryIndicator(
                              batteryPercentage: battery,
                              isCharging: isCharging,
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          // Account Icon
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _widgetBackgroundColor,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: AccountMenu(
                  decryptedDataHandler: decryptedDataHandler!,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}