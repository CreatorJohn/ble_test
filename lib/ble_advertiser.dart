import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:ble_peripheral/ble_peripheral.dart';
import 'package:ble_test/mesh_packet_encoder.dart';
import 'package:ble_test/message_handler.dart';
import 'package:ble_test/profile_manager.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart'
    hide CharacteristicProperties;
import 'package:permission_handler/permission_handler.dart';
import 'package:logging/logging.dart' show Logger;

class BLEAdvertiser {
  static final Logger _log = Logger('BLEAdvertiser');
  static final BLEAdvertiser _instance = BLEAdvertiser._internal();
  static final StreamController<bool> _advertisingStatusController =
      StreamController.broadcast();
  static const serviceUuid = 'ab12cd34-56ef-78ab-90cd-ef1234567890';
  static const messageCharUuid = '12345678-90ab-cdef-1234-567890abcdef';
  static const profilePicCharUuid = '87654321-abcd-ef09-1234-567890fedcba';
  static const fullHashCharUuid = 'a1b2c3d4-e5f6-4321-8765-abcdef123456';
  
  static bool _isAdvertising = false;
  static bool _initialized = false;

  factory BLEAdvertiser() => _instance;

  BLEAdvertiser._internal();

  Future<bool> _waitForBluetooth() async {
    _log.info("Checking the bluetooth...");

    BluetoothAdapterState state = await FlutterBluePlus.adapterState
        .firstWhere((s) => s != BluetoothAdapterState.unknown)
        .timeout(
          const Duration(seconds: 2),
          onTimeout: () => BluetoothAdapterState.unknown,
        );

    if (state == BluetoothAdapterState.on) {
      _log.fine("Bluetooth is already ON");
      return true;
    }

    if (state == BluetoothAdapterState.off) {
      _log.info("Bluetooth is OFF, trying to turn it ON...");
      try {
        await FlutterBluePlus.turnOn();
      } catch (e) {
        _log.warning("Could not turn on Bluetooth automatically: $e");
      }
    }

    try {
      await FlutterBluePlus.adapterState
          .where((s) => s == BluetoothAdapterState.on)
          .first
          .timeout(const Duration(seconds: 5));
      _log.fine("Bluetooth is now ON");
      return true;
    } catch (_) {
      _log.severe(
        "Bluetooth failed to turn on or remains in state: ${FlutterBluePlus.adapterStateNow}",
      );
      return false;
    }
  }

  Future<bool> initialize({bool ignorePermissions = false}) async {
    if (_initialized) return true;
    _initialized = true;

    _log.info('Initializing BLEAdvertiser: Requesting permissions first');
    if ((Platform.isAndroid || Platform.isIOS) && !ignorePermissions) {
      final permissions = await [
        Permission.bluetoothScan,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
        Permission.location,
        Permission.locationWhenInUse,
      ].request();

      bool failed = false;
      for (final permission in permissions.entries) {
        if (permission.value.isDenied || permission.value.isPermanentlyDenied) {
          _log.warning(
            'Permission ${permission.key} denied/permanently denied',
          );
          if (permission.key != Permission.location &&
              permission.key != Permission.locationWhenInUse) {
            failed = true;
          }
        }
      }

      if (failed) {
        _log.severe('Required core Bluetooth permissions not granted');
        _initialized = false;
        return false;
      }
    }

    try {
      if (Platform.isAndroid ||
          Platform.isIOS ||
          Platform.isMacOS ||
          Platform.isWindows) {
        _log.info('Calling BlePeripheral.initialize()...');
        await BlePeripheral.initialize();
      }
    } catch (e) {
      _log.severe('BlePeripheral.initialize() failed: $e');
    }

    if ((Platform.isAndroid || Platform.isIOS) && !ignorePermissions) {
      final bluetoothOn = await _waitForBluetooth();
      if (!bluetoothOn) {
        _initialized = false;
        return false;
      }
    }

    BlePeripheral.setAdvertisingStatusUpdateCallback((isAdvertising, error) {
      _log.info('Advertising status updated: isAdvertising=$isAdvertising');
      _advertisingStatusController.add(isAdvertising);
      _isAdvertising = isAdvertising;

      if (error != null) {
        _log.severe('Error occurred while updating advertising status: $error');
        _advertisingStatusController.add(false);
        _isAdvertising = false;
      }
    });

    BlePeripheral.setWriteRequestCallback(
        (deviceId, characteristicUuid, offset, value) {
      _log.info('Write request from $deviceId for $characteristicUuid');
      if (characteristicUuid.toLowerCase() == messageCharUuid.toLowerCase()) {
        if (value != null) {
          MessageHandler.handleIncomingMessage(
            senderId: deviceId,
            data: value,
          );
        }
      }
      return WriteRequestResult();
    });

    BlePeripheral.setReadRequestCallback(
        (deviceId, characteristicUuid, offset, value) {
      _log.info('Read request from $deviceId for $characteristicUuid');
      return null; // Return null to use the current characteristic value
    });

    return true;
  }

  Stream<bool> get advertisingStatusStream =>
      _advertisingStatusController.stream;

  bool get isAdvetising => _isAdvertising;

  Future<void> startAdvertising({
    required String localName,
    double latitude = 0.0,
    double longitude = 0.0,
    bool isOnline = false,
  }) async {
    try {
      if (_initialized == false) {
        bool success = await initialize();
        if (!success) return;
      }

      final bluetoothOn = await _waitForBluetooth();
      if (!bluetoothOn) return;

      _log.info('Resetting BLE stack before starting...');
      try {
        await BlePeripheral.stopAdvertising();
        await BlePeripheral.clearServices();
      } catch (e) {
        _log.fine('Clean reset ignored: $e');
      }

      await Future.delayed(const Duration(seconds: 1));

      final profilePic = await ProfileManager.getProfilePicture();
      final fullHash = await ProfileManager.getProfileHash();

      await BlePeripheral.addService(
        BleService(
          uuid: serviceUuid,
          primary: true,
          characteristics: [
            BleCharacteristic(
              uuid: messageCharUuid,
              value: Uint8List.fromList([0x00]),
              permissions: [AttributePermissions.writeable.index],
              properties: [CharacteristicProperties.write.index],
            ),
            BleCharacteristic(
              uuid: profilePicCharUuid,
              value: profilePic ?? Uint8List.fromList([]),
              permissions: [AttributePermissions.readable.index],
              properties: [CharacteristicProperties.read.index],
            ),
            BleCharacteristic(
              uuid: fullHashCharUuid,
              value: fullHash,
              permissions: [AttributePermissions.readable.index],
              properties: [CharacteristicProperties.read.index],
            ),
          ],
        ),
      );

      await Future.delayed(const Duration(milliseconds: 500));

      final manufacturerData = MeshPacketEncoder.encodeManufacturerData(
        latitude: latitude,
        longitude: longitude,
        isIOS: Platform.isIOS,
        isOnline: isOnline,
        profileHash: fullHash,
      );

      // Prepare Scan Response Data (Full Hash + Local Name)
      final nameBytes = Uint8List.fromList(localName.codeUnits);
      final combinedScanResponse = Uint8List(fullHash.length + nameBytes.length);
      combinedScanResponse.setRange(0, fullHash.length, fullHash);
      combinedScanResponse.setRange(fullHash.length, combinedScanResponse.length, nameBytes);

      _log.info('Starting BLE advertising...');
      await BlePeripheral.startAdvertising(
        services: [serviceUuid],
        localName: String.fromCharCodes(combinedScanResponse),
        manufacturerData: ManufacturerData(
          manufacturerId: 0xFFFF,
          data: manufacturerData,
        ),
      );
    } catch (e) {
      _log.severe('Failed to start advertising: $e');
      await BlePeripheral.stopAdvertising();
    }
  }

  Future<void> stopAdvertising() async {
    try {
      if (!_initialized) return;
      await BlePeripheral.stopAdvertising();
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      _log.severe(e);
    }
  }
}
