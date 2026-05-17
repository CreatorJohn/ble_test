import 'dart:async';
import 'dart:typed_data';

import 'package:ble_test/data/found_device.dart';
import 'package:ble_test/data/isar_service.dart';
import 'package:ble_test/mesh_packet_encoder.dart';
import 'package:ble_test/utils/constants.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:isar_community/isar.dart';

class BLEDiscoverer {
  /// Processes scan results, updates Isar database, and manages the sync queue.
  static Future<void> processScanResults({
    required List<ScanResult> results,
    required IsarService isar,
    required int myStableId,
    required Map<int, BluetoothDevice> syncQueue,
    required Map<int, DateTime> lastSyncAttempt,
  }) async {
    if (!isar.isOpen) return;

    for (final r in results) {
      // Check for our mesh data in common manufacturer IDs (0x1234 or 0xFFFF)
      final meshDataRaw = r.advertisementData.manufacturerData[MeshConstants.manufacturerId] ??
          r.advertisementData.manufacturerData[0xFFFF];
      
      if (meshDataRaw == null || meshDataRaw.length < 5) continue;
      final meshData = Uint8List.fromList(meshDataRaw);
      int? stableId, versionTag;
      String? profileHash;
      double? lat, lon;

      if (meshData.length == 5) {
        final bd = ByteData.view(meshData.buffer);
        stableId = bd.getUint32(0, Endian.big);
        versionTag = (meshData[4] >> 2) & 0x3F;
      } else if (meshData.length == 12) {
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
        final bd = ByteData.view(meshData.buffer);
        stableId = bd.getUint32(0, Endian.big);
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

      if (stableId == null) {
        final dev = await isar.db.foundDevices
            .where()
            .remoteIdEqualTo(r.device.remoteId.toString())
            .findFirst();
        if (dev != null) stableId = dev.stableId;
      }

      if (stableId == null || stableId == myStableId) continue;
      
      final dev = (await isar.db.foundDevices
              .where()
              .stableIdEqualTo(stableId)
              .findFirst()) ??
          (FoundDevice()..stableId = stableId);
      
      dev.remoteId = r.device.remoteId.toString();
      dev.rssi = r.rssi;
      dev.lastSeen = DateTime.now();
      
      if (r.advertisementData.advName.isNotEmpty) {
        dev.name = r.advertisementData.advName;
      }
      if (versionTag != null) dev.versionTag = versionTag;
      if (profileHash != null) dev.profileHash = profileHash;
      if (lat != null) dev.latitude = lat;
      if (lon != null) dev.longitude = lon;

      bool needsUpdate = dev.profilePicture == null ||
          (versionTag != null && dev.versionTag != versionTag) ||
          (dev.lastPictureSync == null ||
              DateTime.now().difference(dev.lastPictureSync!).inHours >= 24);

      await isar.putFoundDevice(dev);
      
      if (needsUpdate) {
        final last = lastSyncAttempt[stableId];
        if (last == null || DateTime.now().difference(last).inMinutes >= 5) {
          syncQueue[stableId] = r.device;
        }
      }
    }
  }
}
