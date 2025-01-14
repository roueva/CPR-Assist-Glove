import 'dart:async';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;

class DecryptedData {
  final StreamController<Map<String, dynamic>> _dataStreamController =
  StreamController<Map<String, dynamic>>.broadcast();

  // AES key must match the Arduino's key (16 bytes)
  final encrypt.Key _aesKey = encrypt.Key.fromUtf8('000102030405060708090A0B0C0D0E0F');
  late final encrypt.Encrypter _aesEncrypter;

  DecryptedData() {
    _aesEncrypter = encrypt.Encrypter(encrypt.AES(_aesKey, mode: encrypt.AESMode.ecb));
  }

  Stream<Map<String, dynamic>> get dataStream => _dataStreamController.stream;

  void processReceivedData(List<int> data) {
    if (data.length == 32) {
      try {
        // Convert List<int> to Uint8List for encryption library
        final Uint8List encryptedBlock1 = Uint8List.fromList(data.sublist(0, 16));
        final Uint8List encryptedBlock2 = Uint8List.fromList(data.sublist(16, 32));

        // Decrypt both blocks
        final decryptedBlock1 = _aesEncrypter.decrypt(encrypt.Encrypted(encryptedBlock1));
        final decryptedBlock2 = _aesEncrypter.decrypt(encrypt.Encrypted(encryptedBlock2));

        // Combine the decrypted blocks into a single list of bytes
        final decryptedData = [...decryptedBlock1.codeUnits, ...decryptedBlock2.codeUnits];

        // Notify listeners with parsed data
        _dataStreamController.add(_parseDecryptedData(decryptedData));

        print("Data processed successfully.");
      } catch (e) {
        print("Failed to decrypt or process data: $e");
      }
    } else {
      print("Received incomplete or incorrect data length.");
    }
  }

  Map<String, dynamic> _parseDecryptedData(List<int> decryptedData) {
    int totalCompressions = _bytesToInt(decryptedData.sublist(0, 4));
    int correctWeightCompressions = _bytesToInt(decryptedData.sublist(4, 8));
    int correctFrequencyCompressions = _bytesToInt(decryptedData.sublist(8, 12));
    int weightGrade = _bytesToInt(decryptedData.sublist(12, 16));
    int frequencyGrade = _bytesToInt(decryptedData.sublist(16, 20));
    int angleGrade = _bytesToInt(decryptedData.sublist(20, 24));
    int totalGrade = _bytesToInt(decryptedData.sublist(24, 28));

    return {
      'totalCompressions': totalCompressions,
      'correctWeightCompressions': correctWeightCompressions,
      'correctFrequencyCompressions': correctFrequencyCompressions,
      'weightGrade': weightGrade / 100.0,
      'frequencyGrade': frequencyGrade / 100.0,
      'angleGrade': angleGrade / 100.0,
      'totalGrade': totalGrade / 100.0,
    };
  }

  int _bytesToInt(List<int> bytes) {
    return bytes[0] |
    (bytes[1] << 8) |
    (bytes[2] << 16) |
    (bytes[3] << 24);
  }

  void dispose() {
    _dataStreamController.close();
  }
}
