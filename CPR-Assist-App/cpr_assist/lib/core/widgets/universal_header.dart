import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';

import 'package:cpr_assist/core/core.dart';

import '../../features/account/screens/account_menu.dart';
import '../../providers/app_providers.dart';
import '../../services/ble/ble_connection.dart';

// ─────────────────────────────────────────────────────────────────────────────
// UniversalHeader
//
// Rules:
//   - Account panel opens ONLY by tapping the avatar button.
//   - No hamburger icon, no swipe-to-open.
//   - forMainScreens: white bg, blue-tinted pills.
//   - forOtherScreens: light-blue bg, white pills.
// ─────────────────────────────────────────────────────────────────────────────

// ── Local BLE state (mirrors ble_status_indicator.dart) ──────────────────────
enum _BLEState { connected, scanning, tapToRetry, bluetoothOff, disconnected }

_BLEState _classifyStatus(String status) {
  if (status == 'Connected') return _BLEState.connected;
  if (status == 'Scanning for Glove...'      ||
      status == 'Connecting…'                ||
      status == 'Bluetooth ON — Connecting…' ||
      status.contains('Reconnecting')        ||
      status.contains('Retrying')) {
    return _BLEState.scanning;
  }
  if (status == 'Bluetooth OFF') return _BLEState.bluetoothOff;
  if (status.contains('Tap to Retry') ||
      status == 'Bluetooth ON — Tap to Connect') {
    return _BLEState.tapToRetry;
  }
  return _BLEState.disconnected;
}

// ─────────────────────────────────────────────────────────────────────────────

class UniversalHeader extends ConsumerWidget implements PreferredSizeWidget {
  final bool          _isMainScreen;
  final bool          showBackButton;
  final VoidCallback? onBackPressed;
  final String?       customTitle;
  final bool          isLiveCprTab;
  final VoidCallback? onAccountTap;

  const UniversalHeader._({
    required bool isMainScreen,
    this.showBackButton = false,
    this.onBackPressed,
    this.customTitle,
    this.onAccountTap,
    this.isLiveCprTab = false,
  }) : _isMainScreen = isMainScreen;

  factory UniversalHeader.forMainScreens({
    VoidCallback? onAccountTap,
    bool isLiveCprTab = false,
  }) =>
      UniversalHeader._(
        isMainScreen: true,
        onAccountTap: onAccountTap,
        isLiveCprTab: isLiveCprTab,
      );

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

  Color get _headerBg {
    if (!_isMainScreen) return AppColors.headerSurface;
    return isLiveCprTab ? AppColors.headerSurface : AppColors.white;
  }

  Color get _pillBg {
    if (!_isMainScreen) return AppColors.white;
    return isLiveCprTab ? AppColors.white : AppColors.headerSurface;
  }

  @override
  Size get preferredSize => const Size.fromHeight(AppSpacing.headerHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppBar(
      toolbarHeight:             AppSpacing.headerHeight,
      backgroundColor:           _headerBg,
      foregroundColor:           AppColors.textPrimary,
      elevation:                 0,
      scrolledUnderElevation:    0,
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
            width:  AppSpacing.iconLg - AppSpacing.xxs,
            height: AppSpacing.iconLg - AppSpacing.xxs,
          ),
          const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
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
        GestureDetector(
          onTap: onAccountTap,
          child: Container(
            width:  AppSpacing.touchTargetMin - AppSpacing.sm,
            height: AppSpacing.touchTargetMin - AppSpacing.sm,
            decoration: AppDecorations.iconCircle(bg: _pillBg),
            child: Center(child: AccountAvatarButton(bgColor: _pillBg)),
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

    return ValueListenableBuilder<String>(
      valueListenable: bleConnection.connectionStatusNotifier,
      builder: (context, status, _) {
        final isConnected = status == 'Connected';

        return GestureDetector(
          onTap: () => _showGloveDialog(context, bleConnection),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
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
                SizedBox(
                  width:  AppSpacing.iconLg,
                  height: AppSpacing.iconLg,
                  child: Center(
                    child: isConnected
                        ? ValueListenableBuilder<int>(
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
                              decoration: AppDecorations.card(color: AppColors.white),
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
                    )
                        : SvgPicture.asset(
                      'assets/icons/glove_icon.svg',
                      width:  AppSpacing.iconMd,
                      height: AppSpacing.iconMd,
                      colorFilter: ColorFilter.mode(
                        AppColors.textSecondary,
                        BlendMode.srcIn,
                      ),
                    )
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dialog launcher
// ─────────────────────────────────────────────────────────────────────────────

void _showGloveDialog(BuildContext context, BLEConnection bleConnection) {
  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (_) => _GloveStatusDialog(bleConnection: bleConnection),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Glove status dialog
// ─────────────────────────────────────────────────────────────────────────────

class _GloveStatusDialog extends StatefulWidget {
  final BLEConnection bleConnection;
  const _GloveStatusDialog({required this.bleConnection});

  @override
  State<_GloveStatusDialog> createState() => _GloveStatusDialogState();
}

class _GloveStatusDialogState extends State<_GloveStatusDialog>
    with SingleTickerProviderStateMixin {

  late AnimationController _pulseController;
  late Animation<double>   _pulseScale;
  late Animation<double>   _pulseOpacity;

  List<ScanResult> _scanResults = [];
  StreamSubscription<List<ScanResult>>? _scanSub;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: false);

    // Scale: 1.0 → 1.6 (ring grows outward)
    _pulseScale = Tween<double>(begin: 1.0, end: 1.6).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );
    // Opacity: 0.4 → 0.0 (ring fades as it grows)
    _pulseOpacity = Tween<double>(begin: 0.4, end: 0.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );

    // Listen to scan results — filter to known glove only
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      if (!mounted) return;
      setState(() {
        _scanResults = results.where((r) =>
        r.device.platformName == AppConstants.bleDeviceName ||
            r.advertisementData.serviceUuids.any(
                  (u) => u.toString().toLowerCase() == AppConstants.bleServiceUuid,
            ),
        ).toList();
      });
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scanSub?.cancel();
    super.dispose();
  }

  /// Handle "Scan Again" — check Bluetooth first, prompt if off.
  Future<void> _handleScanAgain(BuildContext context) async {
    final isBluetoothOn = await FlutterBluePlus.adapterState.first ==
        BluetoothAdapterState.on;

    if (!isBluetoothOn) {
      // Bluetooth is OFF — show system prompt to enable
      try {
        await FlutterBluePlus.turnOn();
        // After user enables BT, start scan
        if (mounted) {
          widget.bleConnection.manualRetry();
        }
      } on FlutterBluePlusException {
        // User denied or error — show alert
        if (mounted) {
          AppDialogs.showAlert(
            context,
            icon:      Icons.bluetooth_disabled_rounded,
            iconColor: AppColors.emergency,
            iconBg:    AppColors.errorBg,
            title:     'Bluetooth Required',
            message:   'Enable Bluetooth to scan for the CPR Assist glove.',
          );
        }
      } catch (_) {}
    } else {
      // Bluetooth is ON — just retry scan
      widget.bleConnection.manualRetry();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: widget.bleConnection.connectionStatusNotifier,
      builder: (context, status, _) {
        final bleState    = _classifyStatus(status);
        final isScanning  = bleState == _BLEState.scanning;
        final isConnected = bleState == _BLEState.connected;

        // Pulse only while scanning
        if (isScanning && !_pulseController.isAnimating) {
          _pulseController.repeat();
        } else if (!isScanning && _pulseController.isAnimating) {
          _pulseController.stop();
        }

        return Dialog(
          backgroundColor: AppColors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.dialogRadius),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.dialogInsetH,
            vertical:   AppSpacing.dialogInsetV,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [

                // ── Close button ───────────────────────────────────────────
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width:  AppSpacing.iconLg,
                      height: AppSpacing.iconLg,
                      decoration: BoxDecoration(
                        color: AppColors.headerSurface,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        size:  AppSpacing.iconSm,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.sm),

                // ── Pulsing BT icon ────────────────────────────────────────
                SizedBox(
                  width:  AppSpacing.avatarLg,
                  height: AppSpacing.avatarLg,
                  child: AnimatedBuilder(
                    animation: _pulseController,
                    builder: (_, __) {
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          // Pulse ring (only while scanning)
                          if (isScanning)
                            Transform.scale(
                              scale: _pulseScale.value,
                              child: Container(
                                width:  60,
                                height: 60,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.primary.withValues(
                                    alpha: _pulseOpacity.value,
                                  ),
                                ),
                              ),
                            ),
                          // Icon circle
                          Container(
                            width:  AppSpacing.iconLg * 2,
                            height: AppSpacing.iconLg * 2,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isConnected
                                  ? AppColors.successBg
                                  : isScanning
                                  ? AppColors.primaryLight
                                  : AppColors.headerSurface,
                            ),
                            child: Icon(
                              isConnected
                                  ? Icons.bluetooth_connected_rounded
                                  : isScanning
                                  ? Icons.bluetooth_searching_rounded
                                  : Icons.bluetooth_rounded,
                              size:  AppSpacing.iconLg,
                              color: isConnected
                                  ? AppColors.success
                                  : isScanning
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),

                const SizedBox(height: AppSpacing.md),

                // ── Title ──────────────────────────────────────────────────
                Text(
                  _title(bleState),
                  style: AppTypography.subheading(),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _message(bleState),
                  style: AppTypography.body(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: AppSpacing.lg),

                // ── Available devices ──────────────────────────────────────
                if (_scanResults.isNotEmpty) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'AVAILABLE DEVICES',
                      style: AppTypography.badge(color: AppColors.textDisabled),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ..._scanResults.map((r) => _DeviceRow(
                    result: r,
                    onPair: () {
                      Navigator.of(context).pop();
                      widget.bleConnection.manualRetry();
                    },
                  )),
                  const SizedBox(height: AppSpacing.sm),
                ],

                // ── Scan Again button ──────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: isScanning
                        ? null
                        : () => _handleScanAgain(context),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: isScanning
                            ? AppColors.divider
                            : AppColors.primary,
                      ),
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.sm + AppSpacing.xs,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
                      ),
                    ),
                    child: Text(
                      isScanning ? 'Scanning…' : 'Scan Again',
                      style: AppTypography.label(
                        color: isScanning
                            ? AppColors.textDisabled
                            : AppColors.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _title(_BLEState state) => switch (state) {
    _BLEState.scanning     => 'Searching for ${AppConstants.bleDeviceName}…',
    _BLEState.connected    => 'Connected to ${AppConstants.bleDeviceName}',
    _BLEState.tapToRetry   => 'Glove Not Found',
    _BLEState.bluetoothOff => 'Bluetooth is Off',
    _BLEState.disconnected => 'Glove Not Connected',
  };

  String _message(_BLEState state) => switch (state) {
    _BLEState.scanning     => 'Make sure the glove is powered on and nearby.',
    _BLEState.connected    => 'Your CPR Assist Glove is connected and ready.',
    _BLEState.tapToRetry   => 'Could not find the glove. Check that it is powered on and within range.',
    _BLEState.bluetoothOff => 'Enable Bluetooth on your device to connect to the glove.',
    _BLEState.disconnected => 'Tap "Scan Again" to search for your glove.',
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Single scanned device row
// ─────────────────────────────────────────────────────────────────────────────

class _DeviceRow extends StatelessWidget {
  final ScanResult   result;
  final VoidCallback onPair;
  const _DeviceRow({required this.result, required this.onPair});

  @override
  Widget build(BuildContext context) {
    final name = result.device.platformName.isEmpty
        ? 'Unknown Device'
        : result.device.platformName;
    final rssi     = result.rssi;
    final signal   = rssi > -60 ? 'Strong' : rssi > -80 ? 'Good' : 'Weak';
    final sigColor = rssi > -60
        ? AppColors.success
        : rssi > -80
        ? AppColors.warning
        : AppColors.emergency;
    final sigIcon  = rssi > -60
        ? Icons.signal_wifi_4_bar_rounded
        : rssi > -80
        ? Icons.network_wifi_3_bar_rounded
        : Icons.signal_wifi_bad_rounded;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
        Container(
        width:  AppSpacing.iconBoxSize,
        height: AppSpacing.iconBoxSize,
        decoration: BoxDecoration(
          color: AppColors.primaryLight,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: SvgPicture.asset(
          'assets/icons/glove_icon.svg',
          width:  AppSpacing.iconMd,
          height: AppSpacing.iconMd,
          colorFilter: ColorFilter.mode(
            AppColors.primary,
            BlendMode.srcIn,
          ),
        ),
      ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: AppTypography.label()),
                Row(
                  children: [
                    Icon(sigIcon, size: AppSpacing.iconXs, color: sigColor),
                    const SizedBox(width: AppSpacing.xxs),
                    Text(
                      '$signal  ($rssi dBm)',
                      style: AppTypography.caption(color: sigColor),
                    ),
                  ],
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onPair,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical:   AppSpacing.xs,
              ),
            ),
            child: Text('Pair', style: AppTypography.label(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }
}