import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:logging/logging.dart';

enum BLEAdvertiserError { permissionsDenied, unknown }

class BLEAdvertiser {
  static final Logger _log = Logger('BLEAdvertiser');
  static final BLEAdvertiser _instance = BLEAdvertiser._internal();
  static final FlutterBlePeripheral _blePeripheral = FlutterBlePeripheral();

  factory BLEAdvertiser() => _instance;

  BLEAdvertiser._internal();

  Future<BLEAdvertiserError?> initialize() async {
    // Request permissions required for BLE advertising

    bool hasPermissions =
        await _blePeripheral.hasPermission() ==
        BluetoothPeripheralState.granted;

    if (!hasPermissions) {
      hasPermissions =
          await _blePeripheral.requestPermission() ==
          BluetoothPeripheralState.granted;
    }

    if (!hasPermissions) {
      return BLEAdvertiserError.permissionsDenied;
    }

    _blePeripheral.onPeripheralStateChanged?.listen((state) {
      _log.info('Peripheral state changed: $state');
    });

    return null; // No error
  }

  Future<void> startAdvertising({
    required String serviceUuid,
    required String localName,
  }) async {
    try {
      await _blePeripheral.start(
        advertiseData: AdvertiseData(
          serviceUuids: [serviceUuid],
          localName: localName,
        ),
      );
    } catch (e) {
      _log.severe(e);
    }
  }

  Future<void> stopAdvertising() async {
    try {
      await _blePeripheral.stop();

      // Ensure stop completes
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      _log.severe(e);
    }
  }
}
