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
      status.contains('Reconnecting')         ||
      status.contains('Retrying')) {
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
  bool _wasConnected = false;

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
    if (!mounted) return;
    final status = widget.connectionStatusNotifier.value;
    final bleState = _classifyStatus(status);

    // Detect drop: was connected, now isn't
    if (_wasConnected && bleState != _BLEState.connected) {
      _wasConnected = false;
      // Don't show glove-lost dialog if BT itself turned off — that has its own dialog
      if (bleState != _BLEState.bluetoothOff) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showGloveLostDialog();
        });
      }
    }

    if (bleState == _BLEState.connected) _wasConnected = true;

    setState(() {});
  }

  void _onAdapterState(BluetoothAdapterState state) {
    if (!mounted) return;
    setState(() {});
    if (state == BluetoothAdapterState.off) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _enableBluetooth();
      });
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
        return;
      case _BLEState.bluetoothOff:
        await _enableBluetooth();
        return;
      case _BLEState.tapToRetry:
        await widget.bleConnection.manualRetry();
        return;
      case _BLEState.disconnected:
        await widget.bleConnection.manualRetry();
        return;
    }
  }

  // ── Bluetooth enable (native prompt first, explanation on denial) ─────────
  Future<void> _enableBluetooth() async {
    try {
      await FlutterBluePlus.turnOn();
    } on FlutterBluePlusException {
      if (mounted) {
        AppDialogs.showAlert(
          context,
          icon:      Icons.bluetooth_disabled_rounded,
          iconColor: AppColors.emergencyRed,
          iconBg:    AppColors.emergencyBg,
          title:     'Bluetooth Required',
          message:   'The CPR Assist glove requires Bluetooth. Please enable it to connect.',
        );
      }
    } catch (_) {}
  }

// ── Glove lost dialog ─────────────────────────────────────────────────────
  void _showGloveLostDialog() {
    AppDialogs.showAlert(
      context,
      icon:      Icons.bluetooth_searching_rounded,
      iconColor: AppColors.warning,
      iconBg:    AppColors.warningBg,
      title:     'Glove Connection Lost',
      message:   'The CPR Assist glove disconnected unexpectedly. Attempting to reconnect automatically.',
    );
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
          ],
        ),
      ),
    );
  }
}