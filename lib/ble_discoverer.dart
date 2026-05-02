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

class BLEDiscoverer {
  static bool _initialized = false;
  static final Logger _log = Logger('BLEDiscoverer');

  const factory BLEDiscoverer() = BLEDiscoverer._internal;

  const BLEDiscoverer._internal();

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

      FlutterBluePlus.onScanResults.listen((results) {
        _log.info("Scanned ${results.length} devices");
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

    Timer? timer;
    const scanTimeout = Duration(seconds: 10);

    _log.info("Starting scan...");

    try {
      // Android/Chromebook safety: stop any existing scan first
      await FlutterBluePlus.stopScan();
      await Future.delayed(const Duration(milliseconds: 200));

      await FlutterBluePlus.startScan(
        timeout: scanTimeout,
        androidUsesFineLocation: true, // Required for some Android versions
      );

      // 1. Wait for scanning to be TRUE (hardware wake up)
      await FlutterBluePlus.isScanning
          .where((s) => s)
          .first
          .timeout(const Duration(seconds: 2))
          .catchError((_) => true);

      // 2. NOW start the progress timer so it is synced with actual scanning
      if (onProgress != null) {
        timer = Timer.periodic(const Duration(seconds: 1), (t) {
          onProgress(t.tick / 10);
          if (t.tick >= 10) t.cancel();
        });
      }

      // 3. Wait for scanning to be FALSE (scan completed)
      await FlutterBluePlus.isScanning
          .where((s) => !s)
          .first
          .timeout(scanTimeout + const Duration(seconds: 2));

      _log.info("Scan finished");
    } catch (e) {
      _log.warning("Scan stopped or timed out: $e");
    } finally {
      if (onProgress != null) timer?.cancel();
    }

    // Use a Map to ensure unique devices by remoteId
    final Map<String, DiscoveredDevice> uniqueDevices = {};

    for (final result in FlutterBluePlus.lastScanResults) {
      final remoteId = result.device.remoteId.toString();

      // Check advertisement data for the target service UUID (no connection needed)
      final hasTarget = result.advertisementData.serviceUuids
          .any((uuid) => uuid.toString().toLowerCase() == BLEAdvertiser.serviceUuid.toLowerCase());

      uniqueDevices[remoteId] = (
        remoteId: remoteId,
        result: result,
        services: [], // We don't connect to keep discovery fast
        hasTargetService: hasTarget,
      );
    }

    _log.info("Found ${uniqueDevices.length} unique devices");

    return uniqueDevices.values.toList();
  }

  Future<void> stopDiscovering() async {
    final scanning = FlutterBluePlus.isScanningNow;

    if (!scanning) {
      _log.warning('Not currently discovering, cannot stop discovering');
      return;
    }

    await FlutterBluePlus.stopScan();

    _log.info("Scan stopped manually");

    await Future.delayed(const Duration(milliseconds: 500));
  }
}
