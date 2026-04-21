import 'dart:async';

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

    // Wait for first valid state
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

    // Wait for ON state
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

  Future<bool> initialize() async {
    if (_initialized) return true;
    _initialized = true;

    _log.info('Initializing BLEAdvertiser: Requesting permissions first');
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
        _log.warning('Permission ${permission.key} denied/permanently denied');
        // On Android 16, location might be denied but BLE might still work if neverForLocation is set,
        // but we'll log it as a warning. We only fail on the core BT permissions.
        if (permission.key != Permission.location && permission.key != Permission.locationWhenInUse) {
          failed = true;
        }
      }
    }

    if (failed) {
      _log.severe('Required core Bluetooth permissions not granted');
      _initialized = false;
      return false;
    }

    final bluetoothOn = await _waitForBluetooth();

    if (!bluetoothOn) {
      _initialized = false;
      return false;
    }

    // Extra stabilization for Android 16
    await Future.delayed(const Duration(seconds: 1));

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

      // Android 16/HyperOS safety: Reset the stack first
      _log.info('Resetting BLE stack before starting...');
      try {
        await BlePeripheral.stopAdvertising();
        await BlePeripheral.clearServices();
      } catch (e) {
        _log.fine('Clean reset ignored: $e');
      }

      /*
      // Crucial delay for Android 16 GATT stability
      await Future.delayed(const Duration(seconds: 1));

      _log.info('Adding BLE service...');
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
      */

      // Short breathing room after adding service
      await Future.delayed(const Duration(milliseconds: 500));

      _log.info('Starting BLE advertising with local name: $localName');
      await BlePeripheral.startAdvertising(
        services: [serviceUuid],
        localName: localName,
      );
    } catch (e) {
      _log.severe('Failed to start advertising: $e');
      // Attempt to cleanup on failure
      await BlePeripheral.stopAdvertising();
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
