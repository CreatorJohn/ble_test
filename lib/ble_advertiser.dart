import 'dart:async';
import 'dart:convert';
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
  static const nameCharUuid = 'c3c4c5c6-d7d8-4321-8765-abcdefabcdef';

  static const int maxNameLength = 13;

  static bool _initialized = false,
      _servicesAdded = false,
      _isAdvertising = false;
  static Uint8List? _currentProfilePic, _currentFullHash, _currentPubKey;
  static String? _currentName;
  static final Set<String> _connectedDevices = {};
  static final Map<String, int> _deviceMtu = {};
  static final StreamController<Map<String, bool>> _connectionController =
      StreamController.broadcast();

  static bool get initialized => _initialized;
  static bool get hasInboundConnections => _connectedDevices.isNotEmpty;
  static bool isDeviceConnected(String deviceId) =>
      _connectedDevices.contains(deviceId);
  static int getMtuForDevice(String deviceId) => _deviceMtu[deviceId] ?? 23;
  static Stream<Map<String, bool>> get connectionStream =>
      _connectionController.stream;

  factory BLEAdvertiser() => _instance;
  BLEAdvertiser._internal();

  static Future<void> sendNotification({
    required String characteristicUuid,
    required Uint8List value,
    String? deviceId,
  }) async {
    try {
      if (!_initialized) return;
      await BlePeripheral.updateCharacteristic(
        characteristicId: characteristicUuid,
        value: value,
        deviceId: deviceId,
      );
    } catch (e) {
      _log.warning('Notify fail: $e');
    }
  }

  Future<bool> initialize({bool ignorePermissions = false}) async {
    if (_initialized) return true;
    _initialized = true;
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
      await Future.delayed(const Duration(seconds: 1));
    }
    try {
      await BlePeripheral.initialize();
    } catch (e) {
      _log.warning('Init fail: $e');
    }

    BlePeripheral.setAdvertisingStatusUpdateCallback((isAd, err) {
      _isAdvertising = isAd;
      _advertisingStatusController.add(isAd);
    });
    BlePeripheral.setConnectionStateChangeCallback((id, conn) {
      _log.info('Connection Change | $id | Connected: $conn');
      if (conn) {
        _connectedDevices.add(id);
      } else {
        _connectedDevices.remove(id);
        _deviceMtu.remove(id);
      }
      _connectionController.add({id: conn});
    });
    BlePeripheral.setMtuChangeCallback((id, mtu) => _deviceMtu[id] = mtu);

    BlePeripheral.setWriteRequestCallback((id, char, offset, val) {
      final charLower = char.toLowerCase();
      try {
        if (charLower == messageCharUuid.toLowerCase() && val != null) {
          if (val.isNotEmpty && val[0] == 0x05 && val.length == 10) {
            MessageHandler.handleIncomingAck(val);
            return WriteRequestResult(status: 0);
          }
          final isar = IsarService();
          if (isar.isOpen) {
            isar.findDeviceByRemoteId(id).then((dev) async {
              if (dev != null) {
                MessageHandler.handleIncomingMessage(
                  senderStableId: dev.stableId,
                  data: val,
                );
              } else {
                final tempId = id.hashCode.abs();
                final placeholder = FoundDevice()
                  ..remoteId = id
                  ..stableId = tempId
                  ..name = "Connecting Device..."
                  ..lastSeen = DateTime.now();
                await isar.putFoundDevice(placeholder);
                MessageHandler.handleIncomingMessage(
                  senderStableId: tempId,
                  data: val,
                );
              }
            });
          }
        }
      } catch (e) {
        _log.severe('Write error: $e');
        return WriteRequestResult(status: 1);
      }
      return WriteRequestResult(status: 0);
    });

    BlePeripheral.setReadRequestCallback((id, char, offset, val) {
      final charLower = char.toLowerCase();
      try {
        if (charLower == profilePicCharUuid.toLowerCase() && offset == 0) {
          final chunkSize = (getMtuForDevice(id) - 3).clamp(20, 500);
          _streamProfilePicture(id, chunkSize);
          final header = _getProfileHeaderSync(chunkSize);
          if (header != null) {
            return ReadRequestResult(value: header, status: 0);
          }
        }
        if (charLower == fullHashCharUuid.toLowerCase()) {
          return ReadRequestResult(
            value: _currentFullHash ?? Uint8List.fromList([0, 0, 0, 0, 0, 0]),
            status: 0,
          );
        }
        if (charLower == publicKeyCharUuid.toLowerCase()) {
          return ReadRequestResult(
            value: _currentPubKey ?? Uint8List(32),
            status: 0,
          );
        }
        if (charLower == nameCharUuid.toLowerCase()) {
          return ReadRequestResult(
            value: Uint8List.fromList(utf8.encode(_currentName ?? "Unknown")),
            status: 0,
          );
        }
      } catch (e) {
        _log.severe('Read error: $e');
      }
      return null;
    });
    return true;
  }

  Future<bool> _waitForBluetooth() async {
    BluetoothAdapterState s = FlutterBluePlus.adapterStateNow;
    if (s == BluetoothAdapterState.on) return true;
    if (s == BluetoothAdapterState.unknown) {
      await Future.delayed(const Duration(seconds: 3));
    }
    try {
      await FlutterBluePlus.adapterState
          .where((s) => s == BluetoothAdapterState.on)
          .first
          .timeout(const Duration(seconds: 15));
      return true;
    } catch (_) {
      return true;
    }
  }

  static Uint8List? _getProfileHeaderSync(int chunkSize) {
    if (_currentProfilePic == null || _currentProfilePic!.isEmpty) return null;
    final size = _currentProfilePic!.length, count = (size / chunkSize).ceil();
    final h = Uint8List(5);
    h[0] = 0xAA;
    final bd = ByteData.view(h.buffer);
    bd.setUint16(1, size, Endian.big);
    bd.setUint16(3, count, Endian.big);
    return h;
  }

  static Future<void> _streamProfilePicture(String id, int chunkSize) async {
    try {
      if (_currentProfilePic == null || _currentProfilePic!.isEmpty) return;
      final bytes = _currentProfilePic!;
      await Future.delayed(const Duration(milliseconds: 300));
      int offset = 0;
      while (offset < bytes.length) {
        final end = (offset + chunkSize < bytes.length)
            ? offset + chunkSize
            : bytes.length;
        await BlePeripheral.updateCharacteristic(
          characteristicId: profilePicCharUuid,
          value: bytes.sublist(offset, end),
          deviceId: id,
        );
        offset = end;
        await Future.delayed(const Duration(milliseconds: 100));
      }
    } catch (e) {
      _log.severe('Stream fail: $e');
    }
  }

  Future<void> startAdvertising({
    required String localName,
    double latitude = 0.0,
    double longitude = 0.0,
    bool isOnline = false,
  }) async {
    try {
      if (!_initialized) await initialize();
      if (!await BlePeripheral.isSupported()) return;
      await _waitForBluetooth();

      _currentProfilePic = await ProfileManager.getProfilePicture();
      _currentFullHash = await ProfileManager.getProfileHash();
      _currentName = localName;
      final stableId = await ProfileManager.getStableDeviceId();
      final kp = await ProfileManager.getKeyPair();
      _currentPubKey = Uint8List.fromList((await kp.extractPublicKey()).bytes);

      if (!_servicesAdded) {
        _log.info('Setup BLE services...');
        await BlePeripheral.clearServices().catchError((_) {});
        await BlePeripheral.addService(
          BleService(
            uuid: serviceUuid,
            primary: true,
            characteristics: [
              BleCharacteristic(
                uuid: messageCharUuid,
                properties: [
                  CharacteristicProperties.write.index,
                  CharacteristicProperties.notify.index,
                  CharacteristicProperties.indicate.index,
                ],
                permissions: [AttributePermissions.writeable.index],
                value: Uint8List.fromList([0x00]),
              ),
              BleCharacteristic(
                uuid: profilePicCharUuid,
                properties: [
                  CharacteristicProperties.read.index,
                  CharacteristicProperties.write.index,
                  CharacteristicProperties.notify.index,
                  CharacteristicProperties.indicate.index,
                ],
                permissions: [
                  AttributePermissions.readable.index,
                  AttributePermissions.writeable.index,
                ],
                value: _currentProfilePic ?? Uint8List.fromList([]),
              ),
              BleCharacteristic(
                uuid: fullHashCharUuid,
                properties: [CharacteristicProperties.read.index],
                permissions: [AttributePermissions.readable.index],
                value:
                    _currentFullHash ?? Uint8List.fromList([0, 0, 0, 0, 0, 0]),
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
                value: _currentPubKey!,
              ),
              BleCharacteristic(
                uuid: nameCharUuid,
                properties: [CharacteristicProperties.read.index],
                permissions: [AttributePermissions.readable.index],
                value: Uint8List.fromList(utf8.encode(localName)),
              ),
            ],
          ),
        );
        _servicesAdded = true;
        _log.info("Services added!");
        await Future.delayed(const Duration(milliseconds: 500));
      } else {
        _log.info("Updating services...");
        await BlePeripheral.updateCharacteristic(
          characteristicId: locationCharUuid,
          value: MeshPacketEncoder.encodeLocation(latitude, longitude),
        );
        await BlePeripheral.updateCharacteristic(
          characteristicId: fullHashCharUuid,
          value: _currentFullHash ?? Uint8List.fromList([0, 0, 0, 0, 0, 0]),
        );
        await BlePeripheral.updateCharacteristic(
          characteristicId: nameCharUuid,
          value: Uint8List.fromList(utf8.encode(localName)),
        );
        _log.info("Services updated!");
      }

      _log.info("Starting advertising...");
      final main = MeshPacketEncoder.encodeMainPacket(
        stableId: stableId,
        profileHash: _currentFullHash ?? Uint8List.fromList([0, 0, 0, 0, 0, 0]),
        isIOS: Platform.isIOS,
        isOnline: isOnline,
      );
      final scanResp = MeshPacketEncoder.encodeScanResponseManufacturerData(
        latitude: latitude,
        longitude: longitude,
        profileHash: _currentFullHash ?? Uint8List.fromList([0, 0, 0, 0, 0, 0]),
      );

      await BlePeripheral.startAdvertising(
        services: [serviceUuid],
        localName: localName,
        manufacturerData: ManufacturerData(manufacturerId: 0xFFFF, data: main),
        addManufacturerDataInScanResponse: false,
        scanResponseManufacturerData: ManufacturerData(
          manufacturerId: 0xFFFF,
          data: scanResp,
        ),
      );
      _log.info("Advertising!");
    } catch (e) {
      _log.severe('Ad start fail: $e');
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

  Stream<bool> get advertisingStatusStream =>
      _advertisingStatusController.stream;
  bool get isAdvertising => _isAdvertising;
}
