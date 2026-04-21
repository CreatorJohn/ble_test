import 'package:ble_test/ble_discoverer.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'found_devices.g.dart';

@Riverpod(keepAlive: true)
class FoundDevicesState extends _$FoundDevicesState {
  final BleDiscoverer _service = BleDiscoverer();

  @override
  FutureOr<List<DiscoveredDevice>> build() async => [];

  Future<void> discover() async {
    state = AsyncLoading(progress: 0);

    try {
      final results = await _service.discover(
        onProgress: (progress) => state = AsyncLoading(progress: progress),
      );

      state = AsyncData(results);
    } catch (e) {
      state = AsyncError(e, StackTrace.current);
    }
  }

  Future<void> cancel() => _service.stopDiscovering();
}
