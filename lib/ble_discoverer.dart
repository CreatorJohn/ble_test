import 'dart:async';
import 'dart:io';

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

  factory BleDiscoverer() => _instance;

  BleDiscoverer._internal();

  Future<bool> initialize() async {
    if (_initialized) return true;

    // Safety delay for Chromebook/Android container initialization
    await Future.delayed(const Duration(milliseconds: 500));
    _initialized = true;

    try {
      if (Platform.isAndroid || Platform.isIOS) {
        final permissions = await [
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          Permission.location,
          Permission.locationWhenInUse,
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
      } else {
        _log.info('Skipping runtime permissions on non-mobile platform');
      }
    } catch (e) {
      _log.severe('Error requesting permissions: $e');
      _initialized = false;
      return false;
    }

    // Check whether supported using flutter_blue_plus
    try {
      final isSupported = await FlutterBluePlus.isSupported == true;
      if (!isSupported) {
        _log.severe('BLE Scanner mode is not supported on this device');
        _initialized = false;
        return false;
      }

      FlutterBluePlus.onScanResults.listen((results) async {
        for (final result in results) {
          final BluetoothDevice device = result.device;
          final DateTime datetime = result.timeStamp;

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
    } catch (e) {
      _log.severe('Error checking support or setting up listener: $e');
      _initialized = false;
      return false;
    }
  }

  Stream<bool> get isDiscoveringStream => FlutterBluePlus.isScanning;

  Future<List<DiscoveredDevice>> discover({
    void Function(double progress)? onProgress,
  }) async {
    if (!_initialized) {
      _log.warning('BleDiscoverer not initialized, initializing now');
      final success = await initialize();

      if (!success) {
        _log.severe(
          'Failed to initialize BleDiscoverer, cannot start discovering',
        );
        throw Exception(
          'Failed to initialize BleDiscoverer, cannot start discovering',
        );
      }
    }

    if (FlutterBluePlus.isScanningNow) {
      _log.severe("Wait until the previous scan is finished");
      throw Exception("Wait until the previous scan is finished");
    }

    final currentResults = <ScanResult>[];
    final subscription = FlutterBluePlus.onScanResults.listen(
      (results) => currentResults.addAll(results),
    );

    final timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (onProgress != null) onProgress(timer.tick / 10);

      if (timer.tick == 10) timer.cancel();
    });

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

    await subscription.cancel();

    timer.cancel();

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

    return resolvedDevices;
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
