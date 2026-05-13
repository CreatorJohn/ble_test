import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:ble_peripheral/ble_peripheral.dart';
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

  /// Maximum length for the display name in the scan response.
  /// Calculated as: 31 (Total) - 16 (Mfg Data + Header) - 2 (Name Header) = 13
  /// Note: The BLE peripheral plugin has been modified to put the name ONLY in scan response.
  static const int maxNameLength = 13;

  static bool _isAdvertising = false;
  static bool _initialized = false;

  static bool get initialized => _initialized;

  factory BLEAdvertiser() => _instance;

  BLEAdvertiser._internal();

  Future<bool> _waitForBluetooth() async {
    _log.info("Checking the bluetooth...");

    BluetoothAdapterState state = FlutterBluePlus.adapterStateNow;
    _log.info("Initial Bluetooth State: $state");

    if (state == BluetoothAdapterState.on) {
      _log.fine("Bluetooth is already ON");
      return true;
    }

    if (state == BluetoothAdapterState.unknown) {
      _log.info("Bluetooth state unknown, waiting for warm-up...");
      await Future.delayed(const Duration(seconds: 3));
      state = FlutterBluePlus.adapterStateNow;
      if (state == BluetoothAdapterState.on) return true;
    }

    _log.info("Waiting for Bluetooth to reach ON state...");
    try {
      final newState = await FlutterBluePlus.adapterState
          .where((s) => s == BluetoothAdapterState.on)
          .first
          .timeout(const Duration(seconds: 15));
      _log.info("Bluetooth state reached: $newState");
      return true;
    } catch (_) {
      final finalState = FlutterBluePlus.adapterStateNow;
      _log.warning(
        "Bluetooth remains in state: $finalState after timeout. Continuing anyway for stack resilience.",
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

    if (Platform.isAndroid || Platform.isIOS) {
      await _waitForBluetooth();
      // Give the system a moment to settle after Bluetooth turns ON
      await Future.delayed(const Duration(seconds: 1));
    }

    try {
      if (Platform.isAndroid ||
          Platform.isIOS ||
          Platform.isMacOS ||
          Platform.isWindows) {
        _log.info('Calling BlePeripheral.initialize()...');
        try {
          await BlePeripheral.initialize();
        } catch (e) {
          if (e.toString().contains('gattServer is null')) {
            _log.warning('GATT server null, retrying initialize in 3s...');
            await Future.delayed(const Duration(seconds: 3));
            await BlePeripheral.initialize();
          } else {
            rethrow;
          }
        }
      }
    } catch (e) {
      _log.warning(
        'BlePeripheral.initialize() failed (Advertising may be unsupported): $e',
      );
    }

    _log.fine('Setting up BLE callbacks');

    BlePeripheral.setAdvertisingStatusUpdateCallback((isAdvertising, error) {
      _log.info(
        'Advertising status update from plugin: isAdvertising=$isAdvertising, error=$error',
      );
      _isAdvertising = isAdvertising;
      _advertisingStatusController.add(isAdvertising);

      if (error != null) {
        _log.severe('Plugin reported advertisement error: $error');
      }
    });

    BlePeripheral.setWriteRequestCallback((
      deviceId,
      characteristicUuid,
      offset,
      value,
    ) {
      final charUuidLower = characteristicUuid.toLowerCase();
      final valueLen = value?.length ?? 0;
      final hexValue = value != null
          ? value.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')
          : 'null';

      _log.info(
        'Write Request | Device: $deviceId | Char: $charUuidLower | Offset: $offset | Len: $valueLen | Data: [$hexValue]',
      );

      try {
        if (charUuidLower == messageCharUuid.toLowerCase()) {
          if (value != null) {
            final isar = IsarService();
            if (isar.isOpen) {
              isar
                  .findDeviceByRemoteId(deviceId)
                  .then((device) {
                    if (device != null) {
                      _log.info(
                        'Processing Message from ${device.stableId} (Remote: $deviceId)',
                      );
                      MessageHandler.handleIncomingMessage(
                        senderStableId: device.stableId,
                        data: value,
                      );
                    } else {
                      _log.warning(
                        'Message Write Error: Device $deviceId not found in DB. Cannot map to stableId.',
                      );
                    }
                  })
                  .catchError((e) {
                    _log.severe(
                      'Error in findDeviceByRemoteId for Message: $e',
                    );
                  });
            } else {
              _log.warning('Message Write Error: Isar DB is closed');
            }
          } else {
            _log.warning('Message Write Warning: Received null value');
          }
        } else if (charUuidLower == profilePicCharUuid.toLowerCase()) {
          _log.info('Profile Sync Triggered | Device: $deviceId');
          final isar = IsarService();
          if (isar.isOpen) {
            isar
                .findDeviceByRemoteId(deviceId)
                .then((device) {
                  if (device != null) {
                    ProfileManager.getProfilePicture()
                        .then((pic) {
                          if (pic != null) {
                            _log.info(
                              'Pushing Profile Picture to ${device.stableId} (Remote: $deviceId)',
                            );
                            MessageHandler.pushProfilePicture(
                              targetStableId: device.stableId,
                              targetRemoteId: deviceId,
                              imageBytes: pic,
                            );
                          } else {
                            _log.warning(
                              'Profile Sync Error: Local profile pic not found',
                            );
                          }
                        })
                        .catchError((e) {
                          _log.severe('Error fetching local profile pic: $e');
                        });
                  } else {
                    _log.warning(
                      'Profile Sync Error: Device $deviceId not found in DB',
                    );
                  }
                })
                .catchError((e) {
                  _log.severe('Error in findDeviceByRemoteId for Profile: $e');
                });
          } else {
            _log.warning('Profile Sync Error: Isar DB is closed');
          }
        } else {
          _log.fine('Write request to unknown characteristic: $charUuidLower');
        }
      } catch (e) {
        _log.severe('Global error in setWriteRequestCallback: $e');
        return WriteRequestResult(status: 1); // 1 = General Failure
      }
      return WriteRequestResult(status: 0); // 0 = Success
    });

    BlePeripheral.setReadRequestCallback((
      deviceId,
      characteristicUuid,
      offset,
      value,
    ) {
      try {
        _log.info(
          'Read Request | Device: $deviceId | Char: ${characteristicUuid.toLowerCase()} | Offset: $offset',
        );
      } catch (e) {
        _log.severe('Error in setReadRequestCallback logging: $e');
      }
      return null; // Return null to use the characteristic's current value
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

      if (Platform.isAndroid && !await BlePeripheral.isSupported()) {
        _log.warning('Hardware does not support Peripheral Mode (Advertising)');
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
              properties: [
                CharacteristicProperties.read.index,
                CharacteristicProperties.write.index,
              ],
              permissions: [
                AttributePermissions.readable.index,
                AttributePermissions.writeable.index,
              ],
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

      final scanResponsePayload =
          MeshPacketEncoder.encodeScanResponseManufacturerData(
            latitude: latitude,
            longitude: longitude,
            profileHash: fullHash,
          );

      _log.info('Starting BLE advertising...');
      await BlePeripheral.startAdvertising(
        services: [serviceUuid],
        localName: localName,
        manufacturerData: ManufacturerData(
          manufacturerId: 0xFFFF,
          data: mainPayload,
        ),
        addManufacturerDataInScanResponse: false,
        scanResponseManufacturerData: ManufacturerData(
          manufacturerId: 0xFFFF,
          data: scanResponsePayload,
        ),
      );
    } catch (e) {
      if (e.toString().contains("UnsupportedOperationException") ||
          e.toString().contains("Advertising not supported")) {
        _log.warning('Detected unsupported advertising hardware.');
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
