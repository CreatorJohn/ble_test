import 'dart:async';
import 'dart:typed_data';

import 'package:ble_peripheral/ble_peripheral.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:logging/logging.dart';

enum BLEAdvertiserError { permissionsDenied, unknown }

class BLEAdvertiser {
  static final Logger _log = Logger('BLEAdvertiser');
  static final BLEAdvertiser _instance = BLEAdvertiser._internal();
  static final StreamController<bool> _advertisingStatusController =
      StreamController.broadcast();
  static final _serviceUuid = 'ab12cd34-56ef-78ab-90cd-ef1234567890';

  factory BLEAdvertiser() => _instance;

  BLEAdvertiser._internal();

  Future<BLEAdvertiserError?> initialize() async {
    // Check whether permissions are granted using permissions_handler or similar package
    // If not granted, request permissions and return BLEAdvertiserError.permissionsDenied if not granted

    try {
      if (await BlePeripheral.isSupported() != true) {
        _log.severe('BLE Peripheral mode is not supported on this device');
        return BLEAdvertiserError.unknown;
      }
    } catch (e) {
      _log.severe('Error occurred while checking BLE support: $e');
      return BLEAdvertiserError.unknown;
    }

    final permissions = await [
      Permission.bluetooth,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
    ].request();

    bool failed = false;

    for (final permission in permissions.entries) {
      if (permission.value.isDenied) {
        _log.warning('Permission ${permission.key} denied');
        failed = true;
      } else if (permission.value.isPermanentlyDenied) {
        _log.warning('Permission ${permission.key} permanently denied');
        failed = true;
      } else {
        _log.info('Permission ${permission.key} granted');
      }
    }

    if (failed) {
      return BLEAdvertiserError.permissionsDenied;
    }

    BlePeripheral.setAdvertisingStatusUpdateCallback((isAdvertising, error) {
      _log.info('Advertising status updated: isAdvertising=$isAdvertising');
      _advertisingStatusController.add(isAdvertising);

      if (error != null) {
        _log.severe('Error occurred while updating advertising status: $error');
      }
    });
    return null; // No error
  }

  Stream<bool> get advertisingStatusStream =>
      _advertisingStatusController.stream;

  Future<void> startAdvertising({required String localName}) async {
    try {
      if (await BlePeripheral.isAdvertising() == true) {
        _log.warning('Already advertising, stopping first');
        await stopAdvertising();
      }

      _log.info('Starting BLE advertising with local name: $localName');

      await BlePeripheral.addService(
        BleService(
          uuid: _serviceUuid,
          primary: true,
          characteristics: [
            BleCharacteristic(
              uuid: '12345678-90ab-cdef-1234-567890abcdef',
              value: Uint8List.fromList([0x01, 0x02, 0x03]),
              permissions: [AttributePermissions.readable.index],
              properties: [CharacteristicProperties.read.index],
            ),
          ],
        ),
      );

      await BlePeripheral.startAdvertising(
        services: [_serviceUuid],
        localName: localName,
      );
    } catch (e) {
      _log.severe(e);
    }
  }

  Future<void> stopAdvertising() async {
    try {
      await BlePeripheral.stopAdvertising();

      // Ensure stop completes
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      _log.severe(e);
    }
  }
}
