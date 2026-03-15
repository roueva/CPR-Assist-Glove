import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:cpr_assist/core/core.dart';
import '../../services/ble/ble_connection.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BLEStatusIndicator
//
// Shows the current BLE connection state as an SVG icon with an optional
// scanning spinner. Tapping triggers a manual reconnect when applicable.
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
  @override
  void initState() {
    super.initState();
    widget.connectionStatusNotifier.addListener(_rebuild);
  }

  @override
  void dispose() {
    widget.connectionStatusNotifier.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  // ── Icon selection ──────────────────────────────────────────────────────

  String _icon(String status) {
    if (status == 'Connected') {
      return 'assets/icons/bluetooth_on.svg';
    }
    if (status == 'Scanning for Arduino...' ||
        status.contains('Connecting')) {
      return 'assets/icons/bluetooth_search.svg';
    }
    if (status.contains('Tap to') ||
        status.contains('Connection Lost')) {
      return 'assets/icons/bluetooth_retry.svg';
    }
    return 'assets/icons/bluetooth_off.svg';
  }

  bool _canRetry(String status) =>
      status.contains('Tap to') ||
          status == 'Disconnected' ||
          status == 'Connection Lost - Tap to Retry';

  String _tooltip(String status) {
    if (status == 'Connected')            return 'Glove Connected';
    if (status.contains('Scanning'))      return 'Searching for glove…';
    if (status.contains('Lost'))          return 'Connection lost — tap to retry';
    return status;
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final status = widget.connectionStatusNotifier.value;
    final isScanning = status == 'Scanning for Arduino...';

    return GestureDetector(
      onTap: _canRetry(status) ? widget.bleConnection.manualRetry : null,
      child: Tooltip(
        message: _tooltip(status),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xs + AppSpacing.xxs), // 6
              child: SvgPicture.asset(
                _icon(status),
                width: AppSpacing.iconMd - AppSpacing.xxs,  // 22
                height: AppSpacing.iconMd - AppSpacing.xxs,
              ),
            ),
            if (isScanning)
              const Positioned(
                bottom: AppSpacing.xxs + AppSpacing.xxs, // 4 — aligns spinner to icon corner
                right: AppSpacing.xxs,
                child: SizedBox(
                  width: AppSpacing.sm + AppSpacing.xxs,   // 10
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