import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:encrypt/encrypt.dart';
import 'dart:async';
import 'dart:typed_data';

class BLEService {
  final flutterReactiveBle = FlutterReactiveBle();
  final serviceUuid = Uuid.parse("19b10000-e8f2-537e-4f6c-d104768a1214");
  final characteristicUuid = Uuid.parse("19b10001-e8f2-537e-4f6c-d104768a1214");

  late DiscoveredDevice connectedDevice;
  final aesKey = Key.fromUtf8("1234567890123456"); // 16-byte AES key
  late final Encrypter encrypter = Encrypter(AES(aesKey, mode: AESMode.ecb));

  late StreamSubscription<DiscoveredDevice> scanSubscription;
  late StreamSubscription<List<int>> notificationSubscription;

  final _discoveredDevicesController = StreamController<List<DiscoveredDevice>>.broadcast();
  Stream<List<DiscoveredDevice>> get discoveredDevicesStream => _discoveredDevicesController.stream;

  void startScan() {
    List<DiscoveredDevice> devices = [];
    print("Starting BLE scan...");

    scanSubscription = flutterReactiveBle.scanForDevices(withServices: [serviceUuid]).listen((device) {
      print("Found device: ${device.name} (${device.id})");

      if (!devices.any((d) => d.id == device.id)) {
        devices.add(device);
        _discoveredDevicesController.add(devices); // Emit updated device list
      }
    }, onError: (error) {
      print("Scan error: $error");
    });
  }

  void connectToDevice(DiscoveredDevice device, Function onConnected, {Function? onDisconnect}) {
    flutterReactiveBle.connectToDevice(id: device.id).listen((connectionState) {
      if (connectionState.connectionState == DeviceConnectionState.connected) {
        connectedDevice = device;
        onConnected();
      } else if (connectionState.connectionState == DeviceConnectionState.disconnected) {
        if (onDisconnect != null) {
          onDisconnect();
        }
      }
    }, onError: (error) {
      print("Connection error: $error");
    });
  }

  void listenToNotifications(Function(Map<String, dynamic> data) onDataReceived) {
    final characteristic = QualifiedCharacteristic(
      serviceId: serviceUuid,
      characteristicId: characteristicUuid,
      deviceId: connectedDevice.id,
    );

    notificationSubscription = flutterReactiveBle.subscribeToCharacteristic(characteristic).listen(
          (data) {
        final decryptedData = decryptData(data);
        final parsedData = _parseSensorData(Uint8List.fromList(decryptedData));
        onDataReceived(parsedData);
      },
      onError: (error) {
        print("Notification error: $error");
      },
    );
  }

  Map<String, dynamic> _parseSensorData(Uint8List data) {
    final buffer = ByteData.sublistView(data);

    return {
      "depth": buffer.getFloat32(0, Endian.little).toInt(),
      "frequency": buffer.getInt16(4, Endian.little),
      "angle": buffer.getInt16(6, Endian.little),
      "correct_angle_duration": buffer.getFloat32(8, Endian.little)
    };
  }

  List<int> decryptData(List<int> encryptedData) {
    final encrypted = Encrypted(Uint8List.fromList(encryptedData));
    final decryptedBytes = encrypter.decryptBytes(encrypted);
    return decryptedBytes;
  }

  void dispose() {
    scanSubscription.cancel();
    notificationSubscription.cancel();
    _discoveredDevicesController.close();
  }
}
