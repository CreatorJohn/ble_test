import 'dart:async';
import 'dart:typed_data';

import 'package:ble_peripheral/ble_peripheral.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart'
    hide CharacteristicProperties;
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

  Future<bool> _waitForBluetooth() async {
    _log.info("Checking the bluetooth...");

    switch (FlutterBluePlus.adapterStateNow) {
      case BluetoothAdapterState.turningOff:
      case BluetoothAdapterState.off:
      case BluetoothAdapterState.unauthorized:
      case BluetoothAdapterState.unavailable:
      case BluetoothAdapterState.unknown:
        _log.severe("Bluetooth failed to turn on");
        return false;
      default:
    }

    bool isBluetoothOn() =>
        FlutterBluePlus.adapterStateNow == BluetoothAdapterState.on;

    // Check if Bluetooth is ON and wait for it
    if (isBluetoothOn()) {
      _log.fine("Bluetooth is turned on");
    } else {
      // Waiting for Bluetooth to turn on
      await Future.doWhile(() async {
        _log.warning("Bluetooth is turning on...");
        await Future.delayed(const Duration(seconds: 1));

        return isBluetoothOn();
      });
    }

    return true;
  }

  Future<bool> initialize() async {
    if (_initialized) return true;
    _initialized = true;

    _log.info('Initializing BLEAdvertiser: Requesting permissions first');
    final permissions = await [
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
    ].request();

    bool failed = false;
    for (final permission in permissions.entries) {
      if (permission.value.isDenied || permission.value.isPermanentlyDenied) {
        _log.warning('Permission ${permission.key} denied/permanently denied');
        failed = true;
      }
    }

    if (failed) {
      _log.severe('Required permissions not granted');
      _initialized = false;
      return false;
    }

    final bluetoothOn = await _waitForBluetooth();

    if (!bluetoothOn) {
      _initialized = false;
      return false;
    }

    _log.fine('All required permissions granted and bluetooth running');

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
      if (_initialized == false) {
        _log.warning('BLEAdvertiser not initialized, initializing now');
        bool success = await initialize();
        if (!success) return;
      }

      final bluetoothOn = await _waitForBluetooth();

      if (!bluetoothOn) return;

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
