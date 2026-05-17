import 'dart:async';
import 'dart:ui';

import 'package:ble_test/ble_advertiser.dart';
import 'package:ble_test/ble_discoverer.dart';
import 'package:ble_test/data/isar_service.dart';
import 'package:ble_test/message_handler.dart';
import 'package:ble_test/profile_manager.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();
  if (await service.isRunning()) return;

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'scanning_status',
    'BLE Status',
    importance: Importance.low,
  );
  final notificationPlugin = FlutterLocalNotificationsPlugin();
  await notificationPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: "scanning_status",
      initialNotificationTitle: "BLE Mesh Active",
      initialNotificationContent: "Monitoring mesh network",
      foregroundServiceTypes: [
        AndroidForegroundType.location,
        AndroidForegroundType.connectedDevice,
      ],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
      onBackground: (_) async => true,
    ),
  );
}

final Logger log = Logger('BackgroundService');

@pragma("vm:entry-point")
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  final advertiser = BLEAdvertiser();

  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen(
    (r) => service.invoke('log', {
      'message':
          '[BG] [${r.time.hour}:${r.time.minute}:${r.time.second}] [${r.level.name}] ${r.loggerName}: ${r.message}',
      'level': r.level.name,
      'loggerName': r.loggerName,
    }),
  );

  log.info('Service isolate started');
  if (!BLEAdvertiser.initialized) {
    await advertiser.initialize(ignorePermissions: true).then((_) {
      log.info("BLEAdvertiser initialized!");
    }).catchError((_) {
      log.severe("Failed to initialized BLEAdvertiser!");
    });
  }

  runZonedGuarded(
    () async => await _startServiceLogic(service, advertiser),
    (error, stack) => log.severe('Top-level error: $error', error, stack),
  );
}

Future<void> _startServiceLogic(
  ServiceInstance service,
  BLEAdvertiser advertiser,
) async {
  await Future.delayed(const Duration(seconds: 1));
  final prefs = await SharedPreferences.getInstance();
  String currentName = prefs.getString('advertising_name_v2') ?? "BLE Node";
  bool advertisingOn = prefs.getBool('advertising_on') ?? false;
  double currentLat = 0.0, currentLon = 0.0;
  bool isOnline = false, isAdUpdating = false, needsTrailingUpdate = false;

  Future<void> updateAd() async {
    if (!advertisingOn || !BLEAdvertiser.initialized) return;
    if (isAdUpdating || BLEAdvertiser.hasInboundConnections) {
      needsTrailingUpdate = true;
      return;
    }
    isAdUpdating = true;
    needsTrailingUpdate = false;
    try {
      await advertiser.startAdvertising(
        localName: currentName,
        latitude: currentLat,
        longitude: currentLon,
        isOnline: isOnline,
      );
      await prefs.setBool('advertising_on', true);
      service.invoke("advertisingChange", {"active": true});
    } catch (e) {
      log.severe('Ad update fail: $e');
    }
    Timer(const Duration(seconds: 5), () {
      isAdUpdating = false;
      if (needsTrailingUpdate && advertisingOn) updateAd();
    });
  }

  BLEAdvertiser.connectionStream.listen((event) {
    if (!event.values.first && needsTrailingUpdate && advertisingOn) updateAd();
  });

  Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    ),
  ).listen((p) {
    currentLat = p.latitude;
    currentLon = p.longitude;
    if (advertisingOn) updateAd();
  });

  final isar = IsarService();
  await isar.initialize();
  await isar.pruneDatabase();
  MessageHandler.initialize(service: service);

  final myStableId = await ProfileManager.getStableDeviceId();

  // Start Discovery Engine
  BLEDiscoverer().start(service, isar, myStableId);

  Timer.periodic(const Duration(minutes: 2), (_) => MessageHandler.checkExpiredMessages());

  service.on('stopService').listen((_) async {
    BLEDiscoverer().stop();
    await advertiser.stopAdvertising();
    service.stopSelf();
  });
  
  service.on('startAdvertising').listen((e) async {
    final String? name = e?['name'];
    advertisingOn = true;
    await prefs.setBool('advertising_on', true);
    if (name != null) {
      currentName = name;
      updateAd();
    }
  });
  
  service.on('setOnlineStatus').listen((e) {
    final status = e?['isOnline'];
    if (status is bool) {
      isOnline = status;
      if (advertisingOn) updateAd();
    }
  });
  
  service.on("stopAdvertising").listen((_) async {
    advertisingOn = false;
    await prefs.setBool('advertising_on', false);
    await advertiser.stopAdvertising();
    service.invoke("advertisingChange", {"active": false});
  });
  
  service.on("updateLocalProfile").listen((_) => updateAd());
  
  service.on('sendMessage').listen((e) async {
    final targetId = e?['targetId'];
    final content = e?['content'];
    if (targetId is int && content is String) {
      await MessageHandler.sendMessage(targetStableId: targetId, content: content);
    }
  });
}
