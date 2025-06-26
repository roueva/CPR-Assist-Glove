import 'dart:async';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter/cupertino.dart';

class DecryptedData {
  final StreamController<Map<String, dynamic>> _dataStreamController =
  StreamController<Map<String, dynamic>>.broadcast();
  final _stopwatch = Stopwatch();
  Timer? _sessionTimer;
  Timer? _frequencyResetTimer;

  bool _isSessionActive = false;
  int _currentCompressionCount = 0;
  double _currentFrequency = 0.0;
  double _lastNonZeroFrequency = 0.0;
  Duration _sessionDuration = Duration.zero;
  int _zeroFrequencyCount = 0;

  final ValueNotifier<int> batteryPercentageNotifier = ValueNotifier(100);
  final ValueNotifier<bool> isChargingNotifier = ValueNotifier(false);

  static const int FREQUENCY_RESET_THRESHOLD = 75; // ~1.5 seconds at 20ms intervals

  final encrypt.Key _aesKey = encrypt.Key(Uint8List.fromList([
    0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
    0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F
  ]));

  late final encrypt.Encrypter _aesEncrypter;

  DecryptedData() {
    _aesEncrypter = encrypt.Encrypter(
      encrypt.AES(_aesKey, mode: encrypt.AESMode.ecb, padding: null),
    );
  }

  Stream<Map<String, dynamic>> get dataStream => _dataStreamController.stream;
  Map<String, dynamic>? _lastEndPingData;

  void processReceivedData(List<int> data) {
    if (data.length != 48) {
      print("❌ Incorrect data length: ${data.length}. Expected 48 bytes.");
      return;
    }

    try {
      // Decrypt the data
      // 🔽 Bypass decryption — treat raw BLE data as plaintext
      final Uint8List combinedData = Uint8List.fromList(data);

// 🔒 (Commented-out decryption logic)
/*
final Uint8List encryptedBlock1 = Uint8List.fromList(data.sublist(0, 16));
final Uint8List encryptedBlock2 = Uint8List.fromList(data.sublist(16, 32));
final Uint8List encryptedBlock3 = Uint8List.fromList(data.sublist(32, 48));

final decryptedBlock1 = _aesEncrypter.decryptBytes(encrypt.Encrypted(encryptedBlock1));
final decryptedBlock2 = _aesEncrypter.decryptBytes(encrypt.Encrypted(encryptedBlock2));

final Uint8List combinedData = Uint8List.fromList([...decryptedBlock1, ...decryptedBlock2]);
*/

      final buffer = ByteData.sublistView(combinedData);

      // Extract data from buffer
      final depth = buffer.getFloat32(0, Endian.little);
      final frequency = buffer.getFloat32(4, Endian.little);
      final angle = buffer.getFloat32(8, Endian.little);
      final compressionCount = buffer.getInt32(12, Endian.little);

      final sessionActive = buffer.getUint8(16) != 0;
      final packetType = buffer.getUint8(18);

      final int batteryPercentage = buffer.getUint8(46);
      final bool isCharging = buffer.getUint8(47) == 1;

      if (batteryPercentage > 0 && batteryPercentage <= 100) {
        if (batteryPercentageNotifier.value != batteryPercentage) {
          batteryPercentageNotifier.value = batteryPercentage;
          print("🔋 Battery updated: $batteryPercentage% ${isCharging ? '(charging)' : '(not charging)'}");
        }
        // Always update charging status
        isChargingNotifier.value = isCharging;
      } else {
        print("⚠️ Invalid battery data received: $batteryPercentage% - keeping previous value");
      }

      final isStartPing = packetType == 2 && sessionActive && !_isSessionActive;
      final isEndPing = packetType == 2 && !sessionActive && _isSessionActive;
      final isContinuousData = packetType == 1;

      batteryPercentageNotifier.value = batteryPercentage;
      isChargingNotifier.value = isCharging;

      print("🔋 Received battery: $batteryPercentage% ${isCharging ? '(charging)' : '(not charging)'}");

      double heartRatePatient = 0.0;
      double temperaturePatient = 0.0;
      double heartRateUser = 0.0;
      double temperatureUser = 0.0;

      int correctDepth = 0;
      int correctFrequency = 0;
      int correctRecoil = 0;
      int depthRateCombo = 0;
      int totalCompressions = 0;

// 📡 Parse based on packet type
      if (isContinuousData) {
        heartRatePatient = buffer.getFloat32(20, Endian.little);
        temperaturePatient = buffer.getFloat32(24, Endian.little);
        heartRateUser = buffer.getFloat32(28, Endian.little);
        temperatureUser = buffer.getFloat32(32, Endian.little);
      }

      else if (isEndPing) {
        correctDepth = buffer.getUint16(20, Endian.little);
        correctFrequency = buffer.getUint16(22, Endian.little);
        correctRecoil = buffer.getUint16(24, Endian.little);
        depthRateCombo = buffer.getUint16(26, Endian.little);
        totalCompressions = buffer.getUint16(28, Endian.little);

        print("📊 Quality Metrics (END):");
        print("✅ Correct Depth: $correctDepth");
        print("✅ Correct Frequency: $correctFrequency");
        print("✅ Correct Recoil: $correctRecoil");
        print("✅ Depth+Rate Combo: $depthRateCombo");
        print("🔢 Total Compressions: $totalCompressions");
      }

      // Handle session state changes
      if (isStartPing) {
        _startSession();
      } else if (isEndPing) {
        _stopSession();
      }

      // Process continuous data
      if (isContinuousData && _isSessionActive) {
        _processContinuousData(depth, frequency, angle, compressionCount);
      }

      // Send data to UI
      final parsedData = {
        'depth': _isSessionActive ? depth : 0.0,
        'frequency': _currentFrequency,
        'angle': angle,
        'compressionCount': _currentCompressionCount,
        'sessionDuration': _sessionDuration,
        'isSessionActive': _isSessionActive,
        'startPing': isStartPing,
        'endPing': isEndPing,
        'heartRatePatient': heartRatePatient,
        'temperaturePatient': temperaturePatient,
        'heartRateUser': heartRateUser,
        'temperatureUser': temperatureUser,
        // 🟢 Only non-zero if endPing
        'correctDepth': correctDepth,
        'correctFrequency': correctFrequency,
        'correctRecoil': correctRecoil,
        'depthRateCombo': depthRateCombo,
        'totalCompressions': totalCompressions,
        'batteryPercentage': batteryPercentageNotifier.value, // Use notifier value
        'isCharging': isChargingNotifier.value,
      };

      _dataStreamController.add(parsedData);

      if (isEndPing) {
        _lastEndPingData = parsedData;
      }

    } catch (e) {
      print("❌ Failed to decrypt or process data: $e");
    }
  }

  Map<String, dynamic>? getLastEndPingData() => _lastEndPingData;

  void _processContinuousData(double depth, double frequency, double angle, int compressionCount) {
    // Update compression count
    if (compressionCount > _currentCompressionCount) {
      _currentCompressionCount = compressionCount;
      print('🔢 Compression count updated: $_currentCompressionCount');
    }

    // Simplified frequency handling - trust Arduino's calculations
    if (frequency > 0) {
      _currentFrequency = frequency;
      _lastNonZeroFrequency = frequency;
      _zeroFrequencyCount = 0;

      // Cancel any pending frequency reset
      _frequencyResetTimer?.cancel();
      _frequencyResetTimer = null;

      print('📊 Frequency updated: ${_currentFrequency.toStringAsFixed(1)} CPM');

    } else {
      // Only reset frequency after no compressions for 3 seconds
      _zeroFrequencyCount++;
      if (_zeroFrequencyCount >= 30) { // 30 * 100ms = 3 seconds
        if (_currentFrequency > 0) {
          print('⏰ Frequency reset to 0 after 3 seconds of no activity');
          _currentFrequency = 0.0;
        }
        _zeroFrequencyCount = 0;
      }
    }
  }

  void _startSession() {
    print('🟢 Session started - resetting all metrics');

    // Reset stopwatch and start timing
    _stopwatch.reset();
    _stopwatch.start();
    _isSessionActive = true;

    // Reset all metrics
    _currentCompressionCount = 0;
    _currentFrequency = 0.0;
    _lastNonZeroFrequency = 0.0;
    _zeroFrequencyCount = 0;
    _sessionDuration = Duration.zero;

    // Cancel any existing timers
    _sessionTimer?.cancel();
    _frequencyResetTimer?.cancel();

    // Start session duration timer (updates every 100ms for smooth UI)
    _sessionTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_isSessionActive) {
        _sessionDuration = _stopwatch.elapsed;
        _dataStreamController.add({
          'sessionDuration': _sessionDuration,
          'isSessionActive': true,
          'compressionCount': _currentCompressionCount,
          'frequency': _currentFrequency,
        });
      }
    });
  }

  void _stopSession() {
    print('🔴 Session stopped - preserving final metrics');

    // Stop timing but preserve final values
    _stopwatch.stop();
    _isSessionActive = false;
    _sessionDuration = _stopwatch.elapsed;

    // Cancel timers
    _sessionTimer?.cancel();
    _frequencyResetTimer?.cancel();
    _sessionTimer = null;
    _frequencyResetTimer = null;

    // Send final state to UI (depth and frequency will be reset to 0 by the UI logic)
    _dataStreamController.add({
      'sessionDuration': _sessionDuration,
      'isSessionActive': false,
      'compressionCount': _currentCompressionCount, // Keep final count
      'frequency': 0.0, // Reset frequency display
      'depth': 0.0, // Reset depth display
      'endPing': true,
    });

    print('📊 Final session metrics: $_currentCompressionCount compressions in ${_formatDuration(_sessionDuration)}');
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  void dispose() {
    _stopSession();
    _dataStreamController.close();
  }
}