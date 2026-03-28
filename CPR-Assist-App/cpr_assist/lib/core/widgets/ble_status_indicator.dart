import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:cpr_assist/core/core.dart';
import '../../services/ble/ble_connection.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BLEStatusIndicator
//
// Maps every status string from BLEConnection to the correct SVG icon,
// spinning progress indicator, and tap behaviour.
//
// States handled:
//   Connected                        → bluetooth_on.svg,    no tap
//   Scanning for Glove...            → bluetooth_search.svg, spinner, no tap
//   Connecting…                      → bluetooth_search.svg, spinner, no tap
//   Bluetooth ON — Connecting…       → bluetooth_search.svg, spinner, no tap
//   Disconnected — Reconnecting…     → bluetooth_search.svg, spinner, no tap
//   Bluetooth OFF                    → bluetooth_off.svg,   tap → enable BT
//   Bluetooth ON — Tap to Connect    → bluetooth_retry.svg, tap → retry
//   Disconnected                     → bluetooth_off.svg,   tap → retry
//   Glove Not Found — Tap to Retry   → bluetooth_retry.svg, tap → retry dialog
//   Scan Failed — Tap to Retry       → bluetooth_retry.svg, tap → retry dialog
//   Connection Failed — Tap to Retry → bluetooth_retry.svg, tap → retry dialog
//   Connection Lost — Tap to Retry   → bluetooth_retry.svg, tap → retry dialog
//   Setup Failed — Tap to Retry      → bluetooth_retry.svg, tap → retry dialog
// ─────────────────────────────────────────────────────────────────────────────

// ── State classification ─────────────────────────────────────────────────────

enum _BLEState {
  connected,
  scanning,      // scanning or connecting (auto)
  tapToRetry,    // error states where manual retry makes sense
  bluetoothOff,  // BT disabled — special action: enable
  disconnected,  // manual disconnect / initial
}

_BLEState _classifyStatus(String status) {
  if (status == 'Connected') return _BLEState.connected;

  if (status == 'Scanning for Glove...'       ||
      status == 'Connecting…'                 ||
      status == 'Bluetooth ON — Connecting…'  ||
      status.contains('Reconnecting')) {
    return _BLEState.scanning;
  }

  if (status == 'Bluetooth OFF')               return _BLEState.bluetoothOff;

  if (status.contains('Tap to Retry') ||
      status == 'Bluetooth ON — Tap to Connect') {
    return _BLEState.tapToRetry;
  }

  return _BLEState.disconnected;
}

// ─────────────────────────────────────────────────────────────────────────────

class BLEStatusIndicator extends StatefulWidget {
  final BLEConnection bleConnection;
  final ValueNotifier<String> connectionStatusNotifier;

  const BLEStatusIndicator({
    super.key,
    required this.bleConnection,
    required this.connectionStatusNotifier,
  });

  @override
  State<BLEStatusIndicator> createState() => _BLEStatusIndicatorState();
}

class _BLEStatusIndicatorState extends State<BLEStatusIndicator> {
  StreamSubscription<BluetoothAdapterState>? _adapterStateSub;

  @override
  void initState() {
    super.initState();
    widget.connectionStatusNotifier.addListener(_rebuild);
    // Listen for BT adapter going off so we can prompt the user
    _adapterStateSub = widget.bleConnection.adapterStateStream
        .listen(_onAdapterState);
  }

  @override
  void dispose() {
    widget.connectionStatusNotifier.removeListener(_rebuild);
    _adapterStateSub?.cancel();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _onAdapterState(BluetoothAdapterState state) {
    if (state == BluetoothAdapterState.off && mounted) {
      setState(() {});
      _showBluetoothDialog();
    }
  }

  // ── Icon ─────────────────────────────────────────────────────────────────

  String _icon(_BLEState state) {
    switch (state) {
      case _BLEState.connected:
        return 'assets/icons/bluetooth_on.svg';
      case _BLEState.scanning:
        return 'assets/icons/bluetooth_search.svg';
      case _BLEState.tapToRetry:
        return 'assets/icons/bluetooth_retry.svg';
      case _BLEState.bluetoothOff:
      case _BLEState.disconnected:
        return 'assets/icons/bluetooth_off.svg';
    }
  }

  // ── Tooltip ──────────────────────────────────────────────────────────────

  String _tooltip(_BLEState state, String status) {
    switch (state) {
      case _BLEState.connected:
        return 'Glove connected';
      case _BLEState.scanning:
        return status.contains('Reconnecting')
            ? 'Reconnecting to glove…'
            : 'Searching for glove…';
      case _BLEState.bluetoothOff:
        return 'Bluetooth is off — tap to enable';
      case _BLEState.tapToRetry:
        return 'Glove not found — tap to retry';
      case _BLEState.disconnected:
        return 'Glove disconnected — tap to connect';
    }
  }

  // ── Tap handler ───────────────────────────────────────────────────────────

  Future<void> _handleTap(_BLEState state, String status) async {
    switch (state) {
      case _BLEState.connected:
      case _BLEState.scanning:
        return; // no action while connected or auto-scanning

      case _BLEState.bluetoothOff:
        _showBluetoothDialog();
        return;

      case _BLEState.tapToRetry:
        _showRetryDialog(status);
        return;

      case _BLEState.disconnected:
        await widget.bleConnection.manualRetry();
        return;
    }
  }

  void _showBluetoothDialog() {
    AppDialogs.showAlert(
      context,
      icon:      Icons.bluetooth_disabled_rounded,
      iconColor: AppColors.emergencyRed,
      iconBg:    AppColors.emergencyBg,
      title:     'Bluetooth Required',
      message:   'Bluetooth must be enabled to connect to the CPR Assist glove.',
    ).then((_) async {
      // After dialog dismissed, attempt to enable
      if (mounted) {
        await widget.bleConnection.enableBluetooth(prompt: true);
      }
    });
  }

  void _showRetryDialog(String status) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(
          Icons.bluetooth_searching_rounded,
          color: AppColors.warning,
          size:  32,
        ),
        title:   const Text('Glove Not Found'),
        content: Text(
          _retryMessage(status),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:     const Text('Dismiss'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.bleConnection.manualRetry();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  String _retryMessage(String status) {
    if (status.contains('Connection Lost') || status.contains('Connection Failed')) {
      return 'The connection to the glove was lost. Make sure the glove is powered on and nearby.';
    }
    if (status.contains('Setup Failed')) {
      return 'Connected to the glove but service setup failed. Try restarting the glove.';
    }
    return 'Could not find the CPR Assist glove. Make sure it is powered on and nearby.';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final status    = widget.connectionStatusNotifier.value;
    final bleState  = _classifyStatus(status);
    final isSpinning = bleState == _BLEState.scanning;
    final isTappable = bleState != _BLEState.connected && bleState != _BLEState.scanning;

    return GestureDetector(
      onTap: isTappable ? () => _handleTap(bleState, status) : null,
      child: Tooltip(
        message: _tooltip(bleState, status),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Icon
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xs + AppSpacing.xxs),
              child: SvgPicture.asset(
                _icon(bleState),
                width:  AppSpacing.iconMd - AppSpacing.xxs,
                height: AppSpacing.iconMd - AppSpacing.xxs,
              ),
            ),

            // Scanning spinner — corner badge
            if (isSpinning)
              const Positioned(
                bottom: AppSpacing.xxs + AppSpacing.xxs,
                right:  AppSpacing.xxs,
                child: SizedBox(
                  width:  AppSpacing.sm + AppSpacing.xxs,
                  height: AppSpacing.sm + AppSpacing.xxs,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                ),
              ),

            // Tap-to-retry dot — small red badge when action available
            if (isTappable && bleState != _BLEState.disconnected)
              Positioned(
                top:   AppSpacing.xxs,
                right: AppSpacing.xxs,
                child: Container(
                  width:  AppSpacing.xs,
                  height: AppSpacing.xs,
                  decoration: const BoxDecoration(
                    color:  AppColors.emergencyRed,
                    shape:  BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}