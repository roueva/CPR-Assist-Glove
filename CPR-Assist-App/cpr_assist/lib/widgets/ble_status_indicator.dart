import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/ble_connection.dart';

class BLEStatusIndicator extends StatefulWidget {
  final BLEConnection bleConnection;
  final ValueNotifier<String> connectionStatusNotifier;

  const BLEStatusIndicator({
    super.key,
    required this.bleConnection,
    required this.connectionStatusNotifier,
  });

  @override
  _BLEStatusIndicatorState createState() => _BLEStatusIndicatorState();
}

class _BLEStatusIndicatorState extends State<BLEStatusIndicator> {
  @override
  void initState() {
    super.initState();
    widget.connectionStatusNotifier.addListener(_updateState);
  }

  @override
  void dispose() {
    widget.connectionStatusNotifier.removeListener(_updateState);
    super.dispose();
  }

  void _updateState() {
    if (mounted) setState(() {});
  }

  String _getBluetoothIcon(String status) {
    switch (status) {
      case "Connected":
        return 'assets/icons/bluetooth_on.svg';
      case "Scanning for Arduino...":
        return 'assets/icons/bluetooth_search.svg';
      case "Arduino Not Found":
        return 'assets/icons/bluetooth_retry.svg';
      case "Bluetooth OFF":
        return 'assets/icons/bluetooth_search.svg';
      default:
        return 'assets/icons/bluetooth_off.svg';
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.connectionStatusNotifier.value;

    return Container(
      padding: const EdgeInsets.all(6),
      child: SvgPicture.asset(
        _getBluetoothIcon(status),
        width: 22,
        height: 22,
      ),
    );
  }
}
