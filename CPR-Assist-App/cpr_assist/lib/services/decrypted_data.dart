import 'dart:async';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;

class DecryptedData {
  final StreamController<Map<String, dynamic>> _dataStreamController =
  StreamController<Map<String, dynamic>>.broadcast();

  // AES key configured as raw bytes to match the Arduino
  final encrypt.Key _aesKey = encrypt.Key(Uint8List.fromList([
    0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
    0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F
  ]));
  late final encrypt.Encrypter _aesEncrypter;

  DecryptedData() {
    _aesEncrypter = encrypt.Encrypter(
      encrypt.AES(
        _aesKey,
        mode: encrypt.AESMode.ecb,
        padding: null,
      ),
    );
  }

  Stream<Map<String, dynamic>> get dataStream => _dataStreamController.stream;

  void processReceivedData(List<int> data) {
    if (data.length != 32) {
      print("Incorrect data length: ${data.length}. Expected 32 bytes.");
      return;
    }

    try {
      // Split encrypted data into 16-byte blocks
      final Uint8List encryptedBlock1 = Uint8List.fromList(data.sublist(0, 16));
      final Uint8List encryptedBlock2 = Uint8List.fromList(data.sublist(16, 32));

      // Decrypt each block
      final decryptedBlock1 = _aesEncrypter.decryptBytes(encrypt.Encrypted(encryptedBlock1));
      final decryptedBlock2 = _aesEncrypter.decryptBytes(encrypt.Encrypted(encryptedBlock2));

      // Combine decrypted blocks (first 28 bytes are meaningful data)
      final decryptedData = [...decryptedBlock1, ...decryptedBlock2.sublist(0, 12)];


      // Parse and stream the data
      final parsedData = _parseDecryptedData(Uint8List.fromList(decryptedData));
      _dataStreamController.add(parsedData);
    } catch (e) {
      print("Failed to decrypt or process data: $e");
    }
  }

  Map<String, dynamic> _parseDecryptedData(Uint8List decryptedData) {
    final buffer = ByteData.sublistView(decryptedData);

    try {
      return {
        'totalCompressions': buffer.getUint32(0, Endian.little),
        'correctWeightCompressions': buffer.getUint32(4, Endian.little),
        'correctFrequencyCompressions': buffer.getUint32(8, Endian.little),
        'weightGrade': buffer.getUint32(12, Endian.little) / 100.0,
        'frequencyGrade': buffer.getUint32(16, Endian.little) / 100.0,
        'angleGrade': buffer.getUint32(20, Endian.little) / 100.0,
        'totalGrade': buffer.getUint32(24, Endian.little) / 100.0,
      };
    } catch (e) {
      print("Error parsing decrypted data: $e");
      return {};
    }
  }

  void dispose() {
    _dataStreamController.close();
  }
}
