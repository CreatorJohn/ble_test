import 'package:ble_test/data/found_device.dart';
import 'package:ble_test/data/relay_task.dart';
import 'package:ble_test/utils/geo_utils.dart';

abstract class MeshRouter {
  /// Returns a list of stableIds that should receive this task.
  /// This doesn't actually send the data, it just selects candidates.
  bool shouldRelayToPeer({
    required RelayTask task,
    required FoundDevice peer,
    required int myId,
    FoundDevice? targetDevice,
    FoundDevice? ourDevice,
  });
}

class DirectedBeamRouter extends MeshRouter {
  @override
  bool shouldRelayToPeer({
    required RelayTask task,
    required FoundDevice peer,
    required int myId,
    FoundDevice? targetDevice,
    FoundDevice? ourDevice,
  }) {
    if (targetDevice == null || targetDevice.latitude == null) return true;
    if (peer.latitude == null) return false;

    final ourDist = ourDevice?.latitude != null
        ? GeoUtils.calculateDistance(
            ourDevice!.latitude!,
            ourDevice.longitude!,
            targetDevice.latitude!,
            targetDevice.longitude!,
          )
        : double.infinity;

    final peerDist = GeoUtils.calculateDistance(
      peer.latitude!,
      peer.longitude!,
      targetDevice.latitude!,
      targetDevice.longitude!,
    );

    // Only relay if peer is closer to target than we are
    return peerDist < ourDist;
  }
}

class StarburstRouter extends MeshRouter {
  @override
  bool shouldRelayToPeer({
    required RelayTask task,
    required FoundDevice peer,
    required int myId,
    FoundDevice? targetDevice,
    FoundDevice? ourDevice,
  }) {
    // Starburst is simple: everyone is a candidate as long as they haven't received it yet.
    // (Filtering of previous recipients is handled in pushQueuedDataToPeer)
    return true;
  }
}
