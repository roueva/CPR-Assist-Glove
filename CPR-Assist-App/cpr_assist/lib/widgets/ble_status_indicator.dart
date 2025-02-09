import 'package:flutter/material.dart';
import '../services/ble_connection.dart';

class BLEStatusIndicator extends StatefulWidget {
  final BLEConnection bleConnection;
  final ValueNotifier<String> connectionStatusNotifier; // ✅ Listen to BLE status updates

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
    if (mounted) {
      setState(() {}); // ✅ Trigger rebuild when BLE status changes
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 12,
      right: 12,
      child: Column(
        children: [
          GestureDetector(
            onTap: widget.connectionStatusNotifier.value == "Arduino Not Found"
                ? () {
              debugPrint("🔄 Retrying BLE scan...");
              widget.bleConnection.scanAndConnect();
            }
                : null,
            child: Icon(
              _getIconForStatus(widget.connectionStatusNotifier.value),
              color: _getColorForStatus(widget.connectionStatusNotifier.value),
              size: 28,
            ),
          ),
          if (widget.connectionStatusNotifier.value == "Arduino Not Found") ...[
            const SizedBox(height: 6),
            const Text(
              "Retry",
              style: TextStyle(
                fontSize: 12,
                color: Colors.orange,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
    );
  }

  IconData _getIconForStatus(String status) {
    switch (status) {
      case "Connected":
        return Icons.check_circle;
      case "Arduino Not Found":
        return Icons.refresh;
      case "Bluetooth OFF":
        return Icons.bluetooth_disabled;
      case "Scanning for Arduino...": // ✅ New state
        return Icons.search; // 🔍 Use a search icon to indicate scanning
      default:
        return Icons.cancel;
    }
  }


  Color _getColorForStatus(String status) {
    switch (status) {
      case "Connected":
        return Colors.green;
      case "Arduino Not Found":
        return Colors.orange;
      case "Bluetooth OFF":
        return Colors.grey;
      case "Scanning...": // ✅ New state
        return Colors.blue; // 🔵 Scanning color
      default:
        return Colors.red;
    }
  }
}
