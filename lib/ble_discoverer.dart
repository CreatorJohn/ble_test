import 'dart:async';

import 'package:ble_test/ble_advertiser.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart' show Logger;
import 'package:permission_handler/permission_handler.dart';

typedef DiscoveredDevice = ({
  String remoteId,
  List<BluetoothService> services,
  bool hasTargetService,
  ScanResult result,
});

class BleDiscoverer {
  static bool _initialized = false;
  static final BleDiscoverer _instance = BleDiscoverer._internal();
  static final Logger _log = Logger('BleDiscoverer');
  static StreamController<List<DiscoveredDevice>> _resultsController =
      StreamController.broadcast();
  static List<DiscoveredDevice> _currentResults = [];
  static List<DiscoveredDevice> _prevResults = [];

  factory BleDiscoverer() => _instance;

  BleDiscoverer._internal();

  Future<bool> initialize() async {
    if (_initialized) return true;
    _initialized = true;

    // Check whether permissions are granted using permissions_handler or similar package
    // If not granted, request permissions and return false if not granted
    try {
      final isSupported = await FlutterBluePlus.isSupported == true;

      if (!isSupported) {
        _log.severe('BLE Scanner mode is not supported on this device');
        _initialized = false;
        return false;
      }

      _log.fine("BLE Scanner mode is supported on this device");
    } catch (e) {
      _log.severe('Error occurred while checking BLE support: $e');
      _initialized = false;
      return false;
    }

    final permissions = await [
      Permission.bluetoothScan,
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

    FlutterBluePlus.onScanResults.listen((results) async {
      for (final result in results) {
        final BluetoothDevice device = result.device;
        final DateTime datetime = result.timeStamp;
        // final AdvertisementData advData = result.advertisementData;

        final String platform = device.platformName;
        final String advName = device.advName;
        final String remoteId = device.remoteId.toString();

        await device.discoverServices();

        final List<BluetoothService> services = device.servicesList;
        final bool hasTargetService = services.any(
          (service) => service.uuid.toString() == BLEAdvertiser.serviceUuid,
        );

        _log.info(
          'Discovered device: name=$advName, rssi=${result.rssi}, platform=$platform, time=$datetime, remoteId=$remoteId, hasTargetService=$hasTargetService, numberOfServices=${services.length}',
        );
      }
    });

    return true;
  }

  List<DiscoveredDevice> get prevResults => List.unmodifiable(_prevResults);

  Stream<List<DiscoveredDevice>> get resultsStream => _resultsController.stream;

  Stream<bool> get isDiscoveringStream => FlutterBluePlus.isScanning;

  Future<void> discover({
    void Function(
      Stream<List<DiscoveredDevice>> stream,
      List<DiscoveredDevice> initial,
    )?
    freshCb,
  }) async {
    if (!_initialized) {
      _log.warning('BleDiscoverer not initialized, initializing now');
      final success = await initialize();

      if (!success) {
        _log.severe(
          'Failed to initialize BleDiscoverer, cannot start discovering',
        );
        return;
      }
    }

    if (FlutterBluePlus.isScanningNow) {
      _log.severe("Wait until the previous scan is finished");
      return;
    }

    _prevResults = _currentResults;

    if (freshCb != null) {
      _resultsController = StreamController.broadcast();
      freshCb(resultsStream, prevResults);
    }

    final currentResults = <ScanResult>[];
    final subscription = FlutterBluePlus.onScanResults.listen(
      (results) => currentResults.addAll(results),
    );

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

    await subscription.cancel();

    final List<DiscoveredDevice> resolvedDevices = await Future.wait(
      currentResults.map((it) async {
        final services = await it.device.discoverServices();
        final hasTargetService = services.any(
          (it) => it.uuid.str == BLEAdvertiser.serviceUuid,
        );

        return (
          remoteId: it.device.remoteId.toString(),
          services: services,
          hasTargetService: hasTargetService,
          result: it,
        );
      }),
    );

    _resultsController.add(resolvedDevices);

    if (freshCb != null) await _resultsController.close();

    _currentResults = resolvedDevices;
  }

  Future<void> stopDiscovering() async {
    final scanning = FlutterBluePlus.isScanningNow;

    if (!scanning) {
      _log.warning('Not currently discovering, cannot stop discovering');
      return;
    }

    await FlutterBluePlus.stopScan();

    await Future.delayed(const Duration(milliseconds: 500));
  }
}
