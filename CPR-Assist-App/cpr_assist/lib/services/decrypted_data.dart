import 'dart:async';
import 'package:flutter/foundation.dart';
import 'ble/ble_data_processor.dart';
import 'cpr/cpr_session_manager.dart';

/// Coordinates BLE data processing and CPR session management
/// Streams unified data to the UI
class DecryptedData {
  final BLEDataProcessor _dataProcessor = BLEDataProcessor();
  final CPRSessionManager _sessionManager = CPRSessionManager();

  final StreamController<Map<String, dynamic>> _dataStreamController =
  StreamController<Map<String, dynamic>>.broadcast();

  final ValueNotifier<int> batteryPercentageNotifier = ValueNotifier(100);
  final ValueNotifier<bool> isChargingNotifier = ValueNotifier(false);

  Map<String, dynamic>? _lastEndPingData;

  Stream<Map<String, dynamic>> get dataStream => _dataStreamController.stream;
  Map<String, dynamic>? getLastEndPingData() => _lastEndPingData;

  void processReceivedData(List<int> data) {
    final parsed = _dataProcessor.parsePacket(data);
    if (parsed == null) return;

    // Update battery status
    if (parsed.batteryPercentage != null && parsed.isCharging != null) {
      // ✅ Only update if value actually changed
      if (batteryPercentageNotifier.value != parsed.batteryPercentage) {
        batteryPercentageNotifier.value = parsed.batteryPercentage!;
        isChargingNotifier.value = parsed.isCharging!;
        print("🔋 Battery: ${parsed.batteryPercentage}% ${parsed.isCharging! ? '(charging)' : ''}");
      }
    }

    // Handle session state changes
    if (parsed.isStartPing) {
      _sessionManager.startSession();
    } else if (parsed.isEndPing) {
      _sessionManager.stopSession();
    }

    // Update session metrics
    if (parsed.isContinuousData && _sessionManager.isSessionActive) {
      _sessionManager.updateMetrics(
        depth: parsed.depth,
        frequency: parsed.frequency,
        compressionCount: parsed.compressionCount,
      );
    }

    // Build unified data packet for UI
    final uiData = {
      'depth': _sessionManager.isSessionActive ? parsed.depth : 0.0,
      'frequency': _sessionManager.currentFrequency,
      'angle': parsed.angle,
      'compressionCount': _sessionManager.compressionCount,
      'sessionDuration': _sessionManager.sessionDuration,
      'isSessionActive': _sessionManager.isSessionActive,
      'startPing': parsed.isStartPing,
      'endPing': parsed.isEndPing,
      'heartRatePatient': parsed.heartRatePatient,
      'temperaturePatient': parsed.temperaturePatient,
      'heartRateUser': parsed.heartRateUser,
      'temperatureUser': parsed.temperatureUser,
      'correctDepth': parsed.correctDepth,
      'correctFrequency': parsed.correctFrequency,
      'correctRecoil': parsed.correctRecoil,
      'depthRateCombo': parsed.depthRateCombo,
      'totalCompressions': parsed.totalCompressions,
      'batteryPercentage': batteryPercentageNotifier.value,
      'isCharging': isChargingNotifier.value,
    };

    _dataStreamController.add(uiData);

    if (parsed.isEndPing) {
      _lastEndPingData = uiData;
    }
  }

  void dispose() {
    _sessionManager.dispose();
    _dataStreamController.close();
  }
}