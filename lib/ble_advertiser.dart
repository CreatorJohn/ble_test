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
  static const locationCharUuid = 'f1e2d3c4-b5a6-4321-8765-abcdef123456';
  static const publicKeyCharUuid = 'd4c3b2a1-f6e5-4321-8765-abcdefabcdef';

  static bool _isAdvertising = false;
  static bool _initialized = false;
  static bool _isHardwareUnsupported = false;

  factory BLEAdvertiser() => _instance;

  BLEAdvertiser._internal();

  Future<bool> _waitForBluetooth() async {
    _log.info("Checking the bluetooth...");

    BluetoothAdapterState state = FlutterBluePlus.adapterStateNow;
    _log.info("Current Bluetooth State: $state");

    if (state == BluetoothAdapterState.on) {
      _log.fine("Bluetooth is already ON");
      return true;
    }

    if (state == BluetoothAdapterState.off ||
        state == BluetoothAdapterState.turningOff) {
      _log.info("Bluetooth reported as $state, attempting to wait for ON...");
    }

    try {
      await FlutterBluePlus.adapterState
          .where((s) => s == BluetoothAdapterState.on)
          .first
          .timeout(const Duration(seconds: 5));
      _log.fine("Bluetooth is now ON");
      return true;
    } catch (_) {
      _log.warning(
        "Bluetooth remains in state: ${FlutterBluePlus.adapterStateNow}. Continuing anyway for Chromebook reliability.",
      );
      return true;
    }
  }

  Future<bool> initialize({bool ignorePermissions = false}) async {
    if (_initialized) return true;
    _initialized = true;

    _log.info('Initializing BLEAdvertiser: Requesting permissions first');
    if ((Platform.isAndroid || Platform.isIOS) && !ignorePermissions) {
      await [
        Permission.bluetoothScan,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
        Permission.location,
        Permission.locationWhenInUse,
      ].request();
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
      _log.warning(
          'BlePeripheral.initialize() failed (Advertising may be unsupported): $e');
    }

    if ((Platform.isAndroid || Platform.isIOS) && !ignorePermissions) {
      await _waitForBluetooth();
    }

    _log.fine('Setting up BLE callbacks');

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
          final isar = IsarService();
          if (isar.isOpen) {
            isar.findDeviceByRemoteId(deviceId).then((device) {
              if (device != null) {
                MessageHandler.handleIncomingMessage(
                  senderStableId: device.stableId,
                  data: value,
                );
              } else {
                _log.warning('Received message from unknown MAC: $deviceId');
              }
            });
          }
        }
      }
      return WriteRequestResult();
    });

    BlePeripheral.setReadRequestCallback(
        (deviceId, characteristicUuid, offset, value) {
      _log.info('Read request from $deviceId for $characteristicUuid');
      return null;
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
    if (_isHardwareUnsupported) return;

    try {
      if (_initialized == false) {
        bool success = await initialize();
        if (!success) return;
      }

      if (Platform.isAndroid && !await BlePeripheral.isSupported()) {
        _log.warning('Hardware does not support Peripheral Mode (Advertising)');
        _isHardwareUnsupported = true;
        return;
      }

      await _waitForBluetooth();

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
      final stableId = await ProfileManager.getStableDeviceId();
      final keyPair = await ProfileManager.getKeyPair();
      final pubKey = await keyPair.extractPublicKey();

      await BlePeripheral.addService(
        BleService(
          uuid: serviceUuid,
          primary: true,
          characteristics: [
            BleCharacteristic(
              uuid: messageCharUuid,
              properties: [CharacteristicProperties.write.index],
              permissions: [AttributePermissions.writeable.index],
              value: Uint8List.fromList([0x00]),
            ),
            BleCharacteristic(
              uuid: profilePicCharUuid,
              properties: [CharacteristicProperties.read.index],
              permissions: [AttributePermissions.readable.index],
              value: profilePic ?? Uint8List.fromList([]),
            ),
            BleCharacteristic(
              uuid: fullHashCharUuid,
              properties: [CharacteristicProperties.read.index],
              permissions: [AttributePermissions.readable.index],
              value: fullHash,
            ),
            BleCharacteristic(
              uuid: locationCharUuid,
              properties: [CharacteristicProperties.read.index],
              permissions: [AttributePermissions.readable.index],
              value: MeshPacketEncoder.encodeLocation(latitude, longitude),
            ),
            BleCharacteristic(
              uuid: publicKeyCharUuid,
              properties: [CharacteristicProperties.read.index],
              permissions: [AttributePermissions.readable.index],
              value: Uint8List.fromList(pubKey.bytes),
            ),
          ],
        ),
      );

      await Future.delayed(const Duration(milliseconds: 500));

      final mainPayload = MeshPacketEncoder.encodeMainPacket(
        stableId: stableId,
        profileHash: fullHash,
        isIOS: Platform.isIOS,
        isOnline: isOnline,
      );

      final scanResponseMetadata = MeshPacketEncoder.encodeScanResponseData(
        latitude: latitude,
        longitude: longitude,
        profileHash: fullHash,
      );

      final nameBytes = Uint8List.fromList(localName.codeUnits);
      final combinedName =
          Uint8List(scanResponseMetadata.length + nameBytes.length);
      combinedName.setRange(
          0, scanResponseMetadata.length, scanResponseMetadata);
      combinedName.setRange(
          scanResponseMetadata.length, combinedName.length, nameBytes);

      _log.info('Starting BLE advertising...');
      await BlePeripheral.startAdvertising(
        services: [serviceUuid],
        localName: String.fromCharCodes(combinedName),
        manufacturerData: ManufacturerData(
          manufacturerId: 0xFFFF,
          data: mainPayload,
        ),
      );
    } catch (e) {
      if (e.toString().contains("UnsupportedOperationException") || 
          e.toString().contains("Advertising not supported")) {
        _log.warning('Detected unsupported advertising hardware. Silencing future attempts.');
        _isHardwareUnsupported = true;
      } else {
        _log.severe('Failed to start advertising: $e');
      }
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
