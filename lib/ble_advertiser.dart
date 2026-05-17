import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:ble_peripheral/ble_peripheral.dart';
import 'package:ble_test/data/isar_service.dart';
import 'package:ble_test/data/mesh_packet.dart';
import 'package:ble_test/mesh_packet_encoder.dart';
import 'package:ble_test/message_handler.dart';
import 'package:ble_test/profile_manager.dart';
import 'package:ble_test/utils/constants.dart';
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

  static const int manufacturerId = MeshConstants.manufacturerId;
  static const int maxNameLength = 13;

  static bool _initialized = false,
      _servicesAdded = false,
      _isAdvertising = false;
  static Uint8List? _currentProfilePic, _currentFullHash, _currentPubKey;
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
          if (val.isNotEmpty &&
              val[0] == MeshPacket.typeAck &&
              val.length == 10) {
            MessageHandler.handleIncomingAck(AckPacket.fromBytes(val));
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
      return ReadRequestResult(value: Uint8List.fromList([0x00]), status: 0);
    });

    return true;
  }

  Future<void> startAdvertising({
    required String localName,
    double? latitude,
    double? longitude,
    bool isOnline = false,
  }) async {
    if (!_initialized) await initialize();
    _currentProfilePic = await ProfileManager.getProfilePicture();
    _currentFullHash = await ProfileManager.getProfileHash();
    _currentPubKey = Uint8List.fromList(
      (await (await ProfileManager.getKeyPair()).extractPublicKey()).bytes,
    );

    if (!_servicesAdded) {
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
          ],
        ),
      );
      _servicesAdded = true;
    }

    final stableId = await ProfileManager.getStableDeviceId();
    final manufacturerData = MeshPacketEncoder.encodeMainPacket(
      stableId: stableId,
      profileHash: _currentFullHash ?? Uint8List(6),
      isIOS: Platform.isIOS,
      isOnline: isOnline,
    );

    final scanResponseData =
        MeshPacketEncoder.encodeScanResponseManufacturerData(
          latitude: latitude ?? 0.0,
          longitude: longitude ?? 0.0,
          profileHash: _currentFullHash ?? Uint8List(6),
        );

    _log.info('Starting advertising: Name: $localName, StableId: $stableId, MFD: ${manufacturerData.length}b, ScanRespMFD: ${scanResponseData.length}b');

    await BlePeripheral.startAdvertising(
      services: [serviceUuid],
      localName: localName.length > maxNameLength
          ? localName.substring(0, maxNameLength)
          : localName,
      manufacturerData: ManufacturerData(
        manufacturerId: manufacturerId,
        data: manufacturerData,
      ),
      addManufacturerDataInScanResponse: false, // Move StableId to primary packet
      scanResponseManufacturerData: ManufacturerData(
        manufacturerId: manufacturerId,
        data: scanResponseData,
      ),
    );
  }

  Future<void> stopAdvertising() async {
    if (!_initialized) return;
    await BlePeripheral.stopAdvertising();
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

  Stream<bool> get advertisingStatusStream =>
      _advertisingStatusController.stream;
  bool get isAdvertising => _isAdvertising;
}
