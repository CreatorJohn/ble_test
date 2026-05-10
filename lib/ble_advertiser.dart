import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:ble_peripheral/ble_peripheral.dart';
import 'package:ble_test/data/found_device.dart';
import 'package:ble_test/data/isar_service.dart';
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
  static const locationCharUuid = 'e5f6a1b2-c3d4-4321-8765-abcdef654321';
  
  static bool _isAdvertising = false;
  static bool _initialized = false;
  
  // Stored state for GATT reads
  static double _currentLat = 0.0;
  static double _currentLon = 0.0;

  factory BLEAdvertiser() => _instance;

  BLEAdvertiser._internal();

  Future<bool> _waitForBluetooth() async {
    _log.info("Checking the bluetooth...");
    BluetoothAdapterState state = await FlutterBluePlus.adapterState
        .firstWhere((s) => s != BluetoothAdapterState.unknown)
        .timeout(const Duration(seconds: 2), onTimeout: () => BluetoothAdapterState.unknown);

    if (state == BluetoothAdapterState.on) return true;
    if (state == BluetoothAdapterState.off) {
      try { await FlutterBluePlus.turnOn(); } catch (e) { _log.warning("Could not turn on BT: $e"); }
    }

    try {
      await FlutterBluePlus.adapterState.where((s) => s == BluetoothAdapterState.on).first.timeout(const Duration(seconds: 5));
      return true;
    } catch (_) { return false; }
  }

  Future<bool> initialize({bool ignorePermissions = false}) async {
    if (_initialized) return true;
    _initialized = true;

    if ((Platform.isAndroid || Platform.isIOS) && !ignorePermissions) {
      await [Permission.bluetoothScan, Permission.bluetoothAdvertise, Permission.bluetoothConnect, Permission.location, Permission.locationWhenInUse].request();
    }

    try {
      if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isWindows) {
        await BlePeripheral.initialize();
      }
    } catch (e) { _log.severe('BlePeripheral.initialize() failed: $e'); }

    if ((Platform.isAndroid || Platform.isIOS) && !ignorePermissions) {
      final bluetoothOn = await _waitForBluetooth();
      if (!bluetoothOn) { _initialized = false; return false; }
    }

    BlePeripheral.setAdvertisingStatusUpdateCallback((isAdvertising, error) {
      _advertisingStatusController.add(isAdvertising);
      _isAdvertising = isAdvertising;
    });

    BlePeripheral.setWriteRequestCallback((deviceId, characteristicUuid, offset, value) {
      if (characteristicUuid.toLowerCase() == messageCharUuid.toLowerCase() && value != null) {
        final isar = IsarService();
        if (isar.isOpen) {
          isar.db.foundDevices.where().remoteIdEqualTo(deviceId).findFirst().then((device) {
            if (device != null) {
              MessageHandler.handleIncomingMessage(senderStableId: device.stableId, data: value);
            }
          });
        }
      }
      return WriteRequestResult();
    });

    BlePeripheral.setReadRequestCallback((deviceId, characteristicUuid, offset, value) async* {
      final charId = characteristicUuid.toLowerCase();
      if (charId == profilePicCharUuid) {
        final pic = await ProfileManager.getProfilePicture();
        yield ReadRequestResult(value: pic ?? Uint8List(0));
      } else if (charId == fullHashCharUuid) {
        final hash = await ProfileManager.getProfileHash();
        yield ReadRequestResult(value: hash);
      } else if (charId == locationCharUuid) {
        yield ReadRequestResult(value: MeshPacketEncoder.encodeLocation(_currentLat, _currentLon));
      } else {
        yield ReadRequestResult(value: Uint8List(0));
      }
    });

    return true;
  }

  Stream<bool> get advertisingStatusStream => _advertisingStatusController.stream;
  bool get isAdvetising => _isAdvertising;

  Future<void> startAdvertising({
    required String localName,
    double latitude = 0.0,
    double longitude = 0.0,
    bool isOnline = false,
  }) async {
    _currentLat = latitude;
    _currentLon = longitude;

    try {
      if (!_initialized) { await initialize(); }
      if (!await _waitForBluetooth()) return;

      try {
        await BlePeripheral.stopAdvertising();
        await BlePeripheral.clearServices();
      } catch (e) { _log.fine('Clean reset ignored: $e'); }

      await Future.delayed(const Duration(seconds: 1));

      final profilePic = await ProfileManager.getProfilePicture();
      final fullHash = await ProfileManager.getProfileHash();
      final stableId = await ProfileManager.getStableDeviceId();

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
            BleCharacteristic(
              uuid: locationCharUuid,
              value: MeshPacketEncoder.encodeLocation(_currentLat, _currentLon),
              permissions: [AttributePermissions.readable.index],
              properties: [CharacteristicProperties.read.index],
            ),
          ],
        ),
      );

      await Future.delayed(const Duration(milliseconds: 500));

      // Clean Identity Payload (6 bytes)
      final manufacturerData = MeshPacketEncoder.encodeIdentityPayload(
        stableId: stableId,
        profileHash: fullHash,
        isIOS: Platform.isIOS,
        isOnline: isOnline,
      );

      _log.info('Starting CLEAN BLE advertising with local name: $localName');
      await BlePeripheral.startAdvertising(
        services: [serviceUuid],
        localName: localName, // Clean String!
        manufacturerData: ManufacturerData(
          manufacturerId: 0xFEFF, // Valid generic ID
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
    } catch (e) { _log.severe(e); }
  }
}
