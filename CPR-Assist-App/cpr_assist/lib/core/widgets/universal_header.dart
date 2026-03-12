import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';

import 'package:cpr_assist/core/core.dart';

import '../../features/account/screens/account_menu.dart';
import '../../providers/app_providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// UniversalHeader
//
// Rules:
//   - Account panel opens ONLY by tapping the avatar button.
//   - No hamburger icon, no swipe-to-open.
//   - forMainScreens: white bg, blue-tinted pills.
//   - forOtherScreens: light-blue bg, white pills.
// ─────────────────────────────────────────────────────────────────────────────

class UniversalHeader extends ConsumerWidget implements PreferredSizeWidget {
  final bool          _isMainScreen;
  final bool          showBackButton;
  final VoidCallback? onBackPressed;
  final String?       customTitle;

  /// Called when the account avatar is tapped — hook this to
  /// [AccountPanelController.open].
  final VoidCallback? onAccountTap;

  const UniversalHeader._({
    required bool isMainScreen,
    this.showBackButton = false,
    this.onBackPressed,
    this.customTitle,
    this.onAccountTap,
  }) : _isMainScreen = isMainScreen;

  /// Header for the three main tab screens (AED Map, Live CPR, Guide).
  factory UniversalHeader.forMainScreens({
    VoidCallback? onAccountTap,
  }) =>
      UniversalHeader._(
        isMainScreen: true,
        onAccountTap: onAccountTap,
      );

  /// Header for secondary screens (settings, session detail, etc.).
  factory UniversalHeader.forOtherScreens({
    bool          showBackButton = true,
    VoidCallback? onBackPressed,
    String?       customTitle,
  }) =>
      UniversalHeader._(
        isMainScreen:   false,
        showBackButton: showBackButton,
        onBackPressed:  onBackPressed,
        customTitle:    customTitle,
      );

  // Main screens: white bg → blue-tinted pills.
  // Other screens: light-blue bg → white pills.
  Color get _headerBg => _isMainScreen ? AppColors.headerBg : AppColors.primaryLight;
  Color get _pillBg   => _isMainScreen ? AppColors.primaryMid : AppColors.surfaceWhite;

  @override
  Size get preferredSize => const Size.fromHeight(AppSpacing.headerHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppBar(
      toolbarHeight:          AppSpacing.headerHeight,
      backgroundColor:        _headerBg,
      foregroundColor:        AppColors.textPrimary,
      elevation:              0,
      scrolledUnderElevation: 0,
      // Explicitly disable the hamburger / back auto-leading so only our
      // buttons appear in the actions slot.
      automaticallyImplyLeading: false,
      leading: showBackButton
          ? IconButton(
        icon: const Icon(
          Icons.arrow_back_ios_new_rounded,
          color: AppColors.primary,
        ),
        onPressed: onBackPressed ?? () => context.pop(),
      )
          : null,
      titleSpacing: showBackButton ? AppSpacing.xs : AppSpacing.md,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            'assets/icons/logo.svg',
            width:  AppSpacing.iconLg - AppSpacing.xxs,  // ~30
            height: AppSpacing.iconLg - AppSpacing.xxs,
          ),
          const SizedBox(width: AppSpacing.xs + AppSpacing.xxs), // 6
          Text(
            customTitle ?? 'CPR Assist',
            style:    AppTypography.appTitle(),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      actions: [
        _BleAndBatteryPill(pillBg: _pillBg),
        const SizedBox(width: AppSpacing.sm),
        // Account avatar — the ONLY way to open the panel
        GestureDetector(
          onTap: onAccountTap,
          child: Container(
            width:  AppSpacing.touchTargetMin - AppSpacing.sm, // 36
            height: AppSpacing.touchTargetMin - AppSpacing.sm,
            decoration: AppDecorations.iconCircle(bg: _pillBg),
            child: const Center(child: AccountAvatarButton()),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BLE + Battery pill
// ─────────────────────────────────────────────────────────────────────────────

class _BleAndBatteryPill extends ConsumerWidget {
  final Color pillBg;
  const _BleAndBatteryPill({required this.pillBg});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bleConnection = ref.watch(bleConnectionProvider);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical:   AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color:        pillBg,
        borderRadius: BorderRadius.circular(AppSpacing.buttonRadiusLg),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BLEStatusIndicator(
            bleConnection:            bleConnection,
            connectionStatusNotifier: bleConnection.connectionStatusNotifier,
          ),
          const SizedBox(width: AppSpacing.xs),
          ValueListenableBuilder<int>(
            valueListenable: bleConnection.batteryPercentageNotifier,
            builder: (context, battery, _) {
              return ValueListenableBuilder<bool>(
                valueListenable: bleConnection.isChargingNotifier,
                builder: (context, isCharging, _) {
                  return Tooltip(
                    message: isCharging
                        ? 'Charging: $battery%'
                        : 'Battery: $battery%',
                    triggerMode: TooltipTriggerMode.tap,
                    decoration: AppDecorations.card(
                      color: AppColors.surfaceWhite,
                    ),
                    textStyle: AppTypography.label(color: AppColors.textPrimary),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.chipPaddingH,
                      vertical:   AppSpacing.chipPaddingV,
                    ),
                    showDuration: const Duration(seconds: 2),
                    child: GloveBatteryIndicator(
                      batteryPercentage: battery,
                      isCharging:        isCharging,
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}