// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'found_devices.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(FoundDevicesState)
final foundDevicesStateProvider = FoundDevicesStateProvider._();

final class FoundDevicesStateProvider
    extends $AsyncNotifierProvider<FoundDevicesState, List<DiscoveredDevice>> {
  FoundDevicesStateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'foundDevicesStateProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$foundDevicesStateHash();

  @$internal
  @override
  FoundDevicesState create() => FoundDevicesState();
}

String _$foundDevicesStateHash() => r'e9da82451df42ebb36e4a7e56abc52754423b6e5';

abstract class _$FoundDevicesState
    extends $AsyncNotifier<List<DiscoveredDevice>> {
  FutureOr<List<DiscoveredDevice>> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<List<DiscoveredDevice>>, List<DiscoveredDevice>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<List<DiscoveredDevice>>,
                List<DiscoveredDevice>
              >,
              AsyncValue<List<DiscoveredDevice>>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
