import 'dart:async';
import 'dart:typed_data';

import 'package:ble_peripheral/ble_peripheral.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:logging/logging.dart' show Logger;

class BLEAdvertiser {
  static final Logger _log = Logger('BLEAdvertiser');
  static final BLEAdvertiser _instance = BLEAdvertiser._internal();
  static final StreamController<bool> _advertisingStatusController =
      StreamController.broadcast();
  static final serviceUuid = 'ab12cd34-56ef-78ab-90cd-ef1234567890';
  static bool _initialized = false;

  factory BLEAdvertiser() => _instance;

  BLEAdvertiser._internal();

  Future<bool> initialize() async {
    if (_initialized) return true;
    _initialized = true;
    // Check whether permissions are granted using permissions_handler or similar package
    // If not granted, request permissions and return BLEAdvertiserError.permissionsDenied if not granted

    try {
      final isSupported = await BlePeripheral.isSupported() == true;

      if (!isSupported) {
        _log.severe('BLE Peripheral mode is not supported on this device');
        _initialized = false;
        return false;
      }

      _log.fine("BLE Peripheral mode is supported on this device");
    } catch (e) {
      _log.severe('Error occurred while checking BLE support: $e');
      _initialized = false;
      return false;
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
      _initialized = false;
      return false;
    }

    _log.fine('All required permissions granted');

    BlePeripheral.setAdvertisingStatusUpdateCallback((isAdvertising, error) {
      _log.info('Advertising status updated: isAdvertising=$isAdvertising');
      _advertisingStatusController.add(isAdvertising);

      if (error != null) {
        _log.severe('Error occurred while updating advertising status: $error');
        _advertisingStatusController.add(false);
      }
    });

    return true; // No error
  }

  Stream<bool> get advertisingStatusStream =>
      _advertisingStatusController.stream;

  Future<void> startAdvertising({required String localName}) async {
    try {
      print("Is BLEAdvertiser initialized? $_initialized");
      if (_initialized == false) {
        _log.warning('BLEAdvertiser not initialized, initializing now');

        return;
      }

      if (await BlePeripheral.isAdvertising() == true) {
        _log.warning('Already advertising, stopping first');
        await stopAdvertising();
      }

      _log.info('Starting BLE advertising with local name: $localName');

      await BlePeripheral.addService(
        BleService(
          uuid: serviceUuid,
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
        services: [serviceUuid],
        localName: localName,
      );
    } catch (e) {
      _log.severe(e);
    }
  }

  Future<void> stopAdvertising() async {
    try {
      if (!_initialized) {
        _log.warning('BLEAdvertiser not initialized, nothing to stop');
        return;
      }

      if (await BlePeripheral.isAdvertising() != true) {
        _log.warning('Not currently advertising, nothing to stop');
        return;
      }

      await BlePeripheral.stopAdvertising();

      // Ensure stop completes
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      _log.severe(e);
    }
  }
}
