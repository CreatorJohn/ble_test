import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:ble_test/ble_advertiser.dart';
import 'package:ble_test/chunked_transfer_manager.dart';
import 'package:ble_test/data/found_device.dart';
import 'package:ble_test/data/isar_service.dart';
import 'package:ble_test/mesh_packet_encoder.dart';
import 'package:ble_test/message_handler.dart';
import 'package:ble_test/profile_manager.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:isar_community/isar.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();
  final serviceRunning = await service.isRunning();

  if (serviceRunning) {
    log.warning("Service is already running");
    return;
  }

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'scanning_status',
    'BLE Scanning Status',
    description: 'This channel is used for BLE scanning status.',
    importance: Importance.low,
  );

  final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: "scanning_status",
      initialNotificationTitle: "BLE Scanner",
      initialNotificationContent: "Monitoring nearby devices",
      foregroundServiceTypes: [
        AndroidForegroundType.location,
        AndroidForegroundType.connectedDevice,
      ],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma("vm:entry-point")
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

final Logger log = Logger('BackgroundService');

@pragma("vm:entry-point")
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final advertiser = BLEAdvertiser();

  // 1. Setup isolate-level logging
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    service.invoke('log', {
      'message':
          '[BG] [${record.time.hour}:${record.time.minute}:${record.time.second}] [${record.level.name}] ${record.loggerName}: ${record.message}',
      'level': record.level.name,
    });
  });

  log.info('Service isolate started');

  // Catch unhandled errors in the background isolate
  runZonedGuarded(
    () async {
      await _startServiceLogic(service, advertiser);
    },
    (error, stack) {
      log.severe('Top-level background error: $error', error, stack);
    },
  );
}

Future<void> _startServiceLogic(
  ServiceInstance service,
  BLEAdvertiser advertiser,
) async {
  await Future.delayed(const Duration(seconds: 1));

  final prefs = await SharedPreferences.getInstance();
  String currentName = prefs.getString('advertising_name_v2') ?? "BLE Test";
  bool advertisingOn = prefs.getBool('advertising_on') ?? false;
  double currentLat = 0.0;
  double currentLon = 0.0;
  bool isOnline = false;

  bool isAdUpdating = false;
  bool needsTrailingUpdate = false;
  bool isScanOperationInProgress = false;

  Future<void> updateAd() async {
    if (!advertisingOn || !BLEAdvertiser.initialized) return;

    if (isAdUpdating || isScanOperationInProgress || BLEAdvertiser.hasInboundConnections) {
      // Already in cooldown, scanning, or being accessed by neighbor
      needsTrailingUpdate = true;
      return;
    }

    isAdUpdating = true;
    needsTrailingUpdate = false;

    try {
      log.info('Updating advertisement: name=$currentName, online=$isOnline');
      await advertiser.startAdvertising(
        localName: currentName,
        latitude: currentLat,
        longitude: currentLon,
        isOnline: isOnline,
      );
    } catch (e) {
      log.severe('updateAd failed: $e');
    }

    // Start 5-second cooldown
    Timer(const Duration(seconds: 5), () {
      isAdUpdating = false;
      // If data changed during cooldown, perform one final sync
      if (needsTrailingUpdate && advertisingOn) {
        updateAd();
      }
    });
  }

  // Listen for neighbor disconnections to trigger deferred ad updates
  BLEAdvertiser.connectionStream.listen((event) {
    final isConnected = event.values.first;
    if (!isConnected && needsTrailingUpdate && advertisingOn) {
      log.info('Neighbor disconnected, triggering deferred ad update...');
      updateAd();
    }
  });

  log.info('Setting up location stream...');
  Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    ),
  ).listen(
    (Position position) {
      log.fine('Location update: ${position.latitude}, ${position.longitude}');
      currentLat = position.latitude;
      currentLon = position.longitude;

      if (advertisingOn) updateAd();
    },
    onError: (e) {
      log.warning('Location stream error: $e');
    },
  );

  final isarService = IsarService();
  try {
    log.info('Initializing IsarService...');
    await isarService.initialize();
    log.info('IsarService initialized');
  } catch (e) {
    log.severe('IsarService initialization failed: $e');
    return;
  }

  // Ensure MessageHandler is listening to ChunkedTransferManager in background isolate
  MessageHandler.initialize();

  final myStableId = await ProfileManager.getStableDeviceId();
  final Map<int, BluetoothDevice> syncQueue = {};
  final Map<int, DateTime> lastSyncAttempt = {};

  FlutterBluePlus.scanResults.listen((results) async {
    if (!isarService.isOpen) return;

    for (final ScanResult result in results) {
      final advData = result.advertisementData;
      final remoteId = result.device.remoteId.toString();

      // Manufacturer ID 0xFFFF is used for our custom mesh payload
      final meshDataRaw = advData.manufacturerData[0xFFFF];
      if (meshDataRaw == null || meshDataRaw.length < 5) continue;

      final meshData = Uint8List.fromList(meshDataRaw);

      int? stableId;
      int? versionTag;
      String? profileHash;
      double? lat;
      double? lon;

      if (meshData.length == 5) {
        // Main Packet: [ID(4)][Version/Flags(1)]
        final buffer = ByteData.view(meshData.buffer);
        stableId = buffer.getUint32(0, Endian.big);
        versionTag = (meshData[4] >> 2) & 0x3F;
      } else if (meshData.length == 12) {
        // Scan Response: [Lat(3)][Lon(3)][Hash(6)]
        lat = MeshPacketEncoder.decodeCoordinate(
          (meshData[0] << 16) | (meshData[1] << 8) | meshData[2],
          true,
        );
        lon = MeshPacketEncoder.decodeCoordinate(
          (meshData[3] << 16) | (meshData[4] << 8) | meshData[5],
          false,
        );
        profileHash = meshData
            .sublist(6, 12)
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
      } else if (meshData.length >= 17) {
        // Merged: [Main(5)][ScanResponse(12)]
        final buffer = ByteData.view(meshData.buffer);
        stableId = buffer.getUint32(0, Endian.big);
        versionTag = (meshData[4] >> 2) & 0x3F;

        lat = MeshPacketEncoder.decodeCoordinate(
          (meshData[5] << 16) | (meshData[6] << 8) | meshData[7],
          true,
        );
        lon = MeshPacketEncoder.decodeCoordinate(
          (meshData[8] << 16) | (meshData[9] << 8) | meshData[10],
          false,
        );
        profileHash = meshData
            .sublist(11, 17)
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
      }

      // If we don't have a stableId in this packet, try to find it in the DB by remoteId
      if (stableId == null) {
        final existingByRemote = await isarService.db.foundDevices
            .where()
            .remoteIdEqualTo(remoteId)
            .findFirst();
        if (existingByRemote != null) {
          stableId = existingByRemote.stableId;
        }
      }

      if (stableId == null || stableId == myStableId) {
        continue;
      }

      FoundDevice device;
      final existing = await isarService.db.foundDevices
          .where()
          .stableIdEqualTo(stableId)
          .findFirst();

      if (existing != null) {
        device = existing;
      } else {
        device = FoundDevice()..stableId = stableId;
      }

      // Update volatile fields
      device.remoteId = remoteId;
      device.rssi = result.rssi;
      device.lastSeen = DateTime.now();

      // Only update metadata if present in this packet
      if (advData.advName.isNotEmpty) {
        device.name = advData.advName;
      }
      if (versionTag != null) device.versionTag = versionTag;
      if (profileHash != null) device.profileHash = profileHash;
      if (lat != null) device.latitude = lat;
      if (lon != null) device.longitude = lon;

      try {
        bool needsMetadataUpdate = false;

        if (existing != null) {
          bool versionChanged =
              versionTag != null && existing.versionTag != versionTag;
          bool needsForcedSync =
              existing.lastPictureSync == null ||
              DateTime.now().difference(existing.lastPictureSync!).inHours >=
                  24;

          if (versionChanged || needsForcedSync) {
            needsMetadataUpdate = true;
          }
        } else {
          needsMetadataUpdate = true;
        }

        // Save the basic device info first
        await isarService.putFoundDevice(device);

        if (needsMetadataUpdate) {
          final lastAttempt = lastSyncAttempt[stableId];
          final bool isCooldownActive =
              lastAttempt != null &&
              DateTime.now().difference(lastAttempt).inMinutes < 5;

          if (!isCooldownActive) {
            syncQueue[stableId] = result.device;
          }
        }
      } catch (e) {
        log.warning('Error processing scan result for $stableId: $e');
      }
    }
  });

  const scanDuration = Duration(seconds: 20);
  const waitDuration = Duration(seconds: 80);
  DateTime? lastScanStartTime;

  Future<void> startSafeScan() async {
    if (isScanOperationInProgress) {
      log.info('Scan operation already in progress, skipping trigger.');
      return;
    }

    // If a neighbor is connected to us, defer scan to avoid dropping their connection
    int deferCount = 0;
    while (BLEAdvertiser.hasInboundConnections && deferCount < 6) {
      log.info('Inbound connection active, deferring scan (attempt ${deferCount + 1}/6)...');
      await Future.delayed(const Duration(seconds: 5));
      deferCount++;
    }

    if (BLEAdvertiser.hasInboundConnections) {
      log.warning('Inbound connection still active after 30s, skipping this scan cycle.');
      return;
    }

    isScanOperationInProgress = true;

    try {
      log.info('Attempting startSafeScan...');
      service.invoke("updateAdvertisingName", {"name": currentName});

      if (!await FlutterBluePlus.isSupported) {
        log.warning('Bluetooth not supported on this device');
        return;
      }

      // Ensure adapter is ON
      var state = await FlutterBluePlus.adapterState.first;
      if (state != BluetoothAdapterState.on) {
        log.info('Bluetooth state is $state, waiting for ON...');
        try {
          state = await FlutterBluePlus.adapterState
              .where((s) => s == BluetoothAdapterState.on)
              .first
              .timeout(const Duration(seconds: 15));
        } catch (_) {
          log.warning('Bluetooth did not turn ON in time, skipping scan');
        }
      } else {
        log.info('Bluetooth state is $state');
      }

      final isScanning = FlutterBluePlus.isScanningNow;
      if (isScanning) {
        log.info('Scan already in progress, stopping first...');
        await FlutterBluePlus.stopScan();
        await Future.delayed(const Duration(seconds: 1));
      }

      log.info('Starting BLE scan (duration: ${scanDuration.inSeconds}s)...');
      lastScanStartTime = DateTime.now();

      await FlutterBluePlus.startScan(
        timeout: scanDuration,
        withServices: [Guid(BLEAdvertiser.serviceUuid)],
        androidScanMode: AndroidScanMode.balanced,
        oneByOne: true,
      );

      // Wait for scan to actually start (state flips to true)
      try {
        await FlutterBluePlus.isScanning
            .where((s) => s == true)
            .first
            .timeout(const Duration(seconds: 2));
      } catch (_) {
        // If it was super fast or already started, ignore timeout
      }

      // Wait for scan to actually stop
      await FlutterBluePlus.isScanning.where((s) => s == false).first;
      log.info('BLE scan complete.');

      if (syncQueue.isNotEmpty) {
        log.info('Processing sync queue (${syncQueue.length} devices)...');
        for (final entry in syncQueue.entries) {
          final id = entry.key;
          final device = entry.value;

          lastSyncAttempt[id] = DateTime.now();
          log.info('Syncing metadata for $id...');
          await _fetchFullMetadata(device, isarService, id, log);
        }
        syncQueue.clear();
        log.info('Sync queue processed.');
      }
    } catch (e) {
      log.severe('startSafeScan failed: $e');
      lastScanStartTime = null;
    } finally {
      isScanOperationInProgress = false;
      if (needsTrailingUpdate && advertisingOn) {
        updateAd();
      }
    }
  }

  // Progress and Status emitter
  Timer.periodic(const Duration(milliseconds: 500), (t) {
    final now = DateTime.now();
    if (FlutterBluePlus.isScanningNow && lastScanStartTime != null) {
      final elapsed = now.difference(lastScanStartTime!);
      final progress = elapsed.inMilliseconds / scanDuration.inMilliseconds;
      service.invoke('updateProgress', {'value': progress.clamp(0.0, 1.0)});
    } else if (lastScanStartTime != null) {
      // We are in wait period
      final elapsedSinceScanStart = now.difference(lastScanStartTime!);
      final totalCycle = scanDuration + waitDuration;
      final remainingWaitMs =
          totalCycle.inMilliseconds - elapsedSinceScanStart.inMilliseconds;
      final remainingSeconds = (remainingWaitMs / 1000).ceil();
      final progress = remainingWaitMs / waitDuration.inMilliseconds;
      service.invoke('updateProgress', {
        'value': progress.clamp(0.0, 1.0),
        'remainingSeconds': remainingSeconds.clamp(0, waitDuration.inSeconds),
      });
    } else {
      service.invoke('updateProgress', {'value': 0.0});
    }
  });

  Timer.periodic(waitDuration + scanDuration, (timer) async {
    log.info('Scanning cycle timer fired');
    await startSafeScan();
  });

  log.info('Performing initial scan...');
  await startSafeScan();

  service.on('stopService').listen((event) async {
    log.info('Stop service command received');
    await advertiser.stopAdvertising();
    service.stopSelf();
  });

  service.on('startAdvertising').listen((event) async {
    final name = event?['name'];
    if (!BLEAdvertiser.initialized) {
      await advertiser.initialize(ignorePermissions: true);
    }
    advertisingOn = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('advertising_on', true);
    service.invoke("advertisingChange", {"active": true});

    log.info("Preparing to advertise with $name...");
    if (name is String) {
      log.info('Setting advertising name to: $name');
      currentName = name;
      updateAd();
    }
  });

  service.on('setOnlineStatus').listen((event) {
    final status = event?['isOnline'];
    if (status is bool) {
      log.info('Setting online status to: $status');
      isOnline = status;
      if (advertisingOn) updateAd();
    }
  });

  service.on("stopAdvertising").listen((_) async {
    advertisingOn = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('advertising_on', false);
    service.invoke("advertisingChange", {"active": false});
    await advertiser.stopAdvertising();
  });
}

Future<void> _fetchFullMetadata(
  BluetoothDevice device,
  IsarService isar,
  int stableId,
  Logger log,
) async {
  try {
    // Small delay and explicit disconnect to clear any pending registration issues
    try {
      await device.disconnect();
      await Future.delayed(const Duration(milliseconds: 1000));
    } catch (_) {}

    log.info('Connecting to $stableId to fetch metadata...');
    try {
      await device.connect(
        autoConnect: false,
        license: License.free,
        timeout: const Duration(seconds: 20),
      );
      log.info('Connected to $stableId');
    } catch (e) {
      if (e.toString().contains('already_connected')) {
        log.info('Already connected to $stableId');
      } else {
        rethrow;
      }
    }

    // Small delay after connection for stability
    await Future.delayed(const Duration(milliseconds: 500));

    final services = await device.discoverServices();

    // Another delay after service discovery
    await Future.delayed(const Duration(milliseconds: 500));

    BluetoothCharacteristic? picChar;
    BluetoothCharacteristic? hashChar;
    BluetoothCharacteristic? locChar;
    BluetoothCharacteristic? keyChar;

    for (final s in services) {
      if (s.uuid.toString().toLowerCase() ==
          BLEAdvertiser.serviceUuid.toLowerCase()) {
        for (final c in s.characteristics) {
          final charId = c.uuid.toString().toLowerCase();
          if (charId == BLEAdvertiser.profilePicCharUuid.toLowerCase()) {
            picChar = c;
          }
          if (charId == BLEAdvertiser.fullHashCharUuid.toLowerCase()) {
            hashChar = c;
          }
          if (charId == BLEAdvertiser.locationCharUuid.toLowerCase()) {
            locChar = c;
          }
          if (charId == BLEAdvertiser.publicKeyCharUuid.toLowerCase()) {
            keyChar = c;
          }
        }
      }
    }

    Future<List<int>> robustRead(BluetoothCharacteristic char) async {
      int attempts = 0;
      while (attempts < 3) {
        try {
          return await char.read().timeout(const Duration(seconds: 5));
        } catch (e) {
          attempts++;
          if (attempts >= 3) rethrow;
          log.warning('Read failed, retrying ($attempts/3)... $e');
          await Future.delayed(const Duration(seconds: 1));
        }
      }
      return [];
    }

    if (hashChar != null) {
      log.info('Reading full hash from $stableId...');
      final hashBytes = await robustRead(hashChar);
      final hashHex = hashBytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();

      final existing = await isar.db.foundDevices
          .where()
          .stableIdEqualTo(stableId)
          .findFirst();

      if (existing != null) {
        log.info('Comparing hashes for $stableId: Local=${existing.profileHash}, Remote=$hashHex');
        log.info('Local picture status for $stableId: ${existing.profilePicture == null ? "MISSING" : "Present (${existing.profilePicture!.length} bytes)"}');

        bool hashMismatched = existing.profileHash != hashHex;
        bool pictureMissing = existing.profilePicture == null;

        existing.profileHash = hashHex;

        if (keyChar != null) {
          log.info('Syncing public key for $stableId...');
          existing.publicKey = await robustRead(keyChar);
        }

        if (picChar != null && (pictureMissing || hashMismatched)) {
          log.info(
            'CONDITION MET: Requesting profile picture sync from $stableId (Missing=$pictureMissing, Mismatch=$hashMismatched)',
          );

          final syncCompleter = Completer<void>();
          final subscription = ChunkedTransferManager.onPayloadComplete.listen((
            event,
          ) {
            if (event['senderStableId'] == stableId) {
              final payload = event['payload'] as Uint8List;
              // MessageHandler.typeRelay (0x04) is the wrapper for mesh payloads
              if (payload.isNotEmpty && payload[0] == 0x04) {
                syncCompleter.complete();
              }
            }
          });

          try {
            log.info('Attempting push-style sync from $stableId...');
            // Trigger push from neighbor
            await picChar.write([0x01], withoutResponse: false);

            log.info('Waiting for profile picture chunks from $stableId...');
            await syncCompleter.future.timeout(
              const Duration(seconds: 15),
            );
          } catch (e) {
            log.info(
              'Push sync failed or timed out ($e), falling back to direct GATT read...',
            );
            try {
              // Direct read fallback for non-advertising or legacy devices
              final bytes = await picChar.read().timeout(
                const Duration(seconds: 30),
              );
              if (bytes.isNotEmpty) {
                log.info('Direct read successful: ${bytes.length} bytes');
                // Re-fetch existing to update with new picture
                final current = await isar.db.foundDevices
                    .where()
                    .stableIdEqualTo(stableId)
                    .findFirst();
                if (current != null) {
                  current.profilePicture = Uint8List.fromList(bytes);
                  await isar.putFoundDevice(current);
                }
              }
            } catch (readErr) {
              log.warning('Direct read fallback also failed: $readErr');
            }
          } finally {
            await subscription.cancel();
          }
        } else if (picChar == null) {
          log.warning('Profile picture characteristic NOT FOUND for $stableId');
        } else {
          log.info('Sync not needed for $stableId: Hash matches and picture exists');
        }

        if (locChar != null) {
          await robustRead(locChar);
        }

        existing.lastPictureSync = DateTime.now();

        // Re-fetch to avoid overwriting volatile fields (RSSI, lastSeen) updated by scan
        final latest = await isar.db.foundDevices
            .where()
            .stableIdEqualTo(stableId)
            .findFirst();

        if (latest != null) {
          log.info('Updating Isar with synced metadata for $stableId');
          latest.profileHash = existing.profileHash;
          latest.publicKey = existing.publicKey;
          latest.lastPictureSync = existing.lastPictureSync;
          await isar.putFoundDevice(latest);
        } else {
          log.warning('Device $stableId vanished during sync, saving current state');
          await isar.putFoundDevice(existing);
        }
        log.info('Metadata sync complete for $stableId');
      } else {
        log.warning('Device $stableId not found in Isar, skipping metadata sync');
      }
    }
  } catch (e) {
    log.warning('Failed to fetch full metadata for $stableId: $e');
  } finally {
    try {
      await device.disconnect();
    } catch (_) {}
  }
}
