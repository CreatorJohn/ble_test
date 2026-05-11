// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'found_devices.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(isarService)
final isarServiceProvider = IsarServiceProvider._();

final class IsarServiceProvider
    extends $FunctionalProvider<IsarService, IsarService, IsarService>
    with $Provider<IsarService> {
  IsarServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'isarServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$isarServiceHash();

  @$internal
  @override
  $ProviderElement<IsarService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  IsarService create(Ref ref) {
    return isarService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(IsarService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<IsarService>(value),
    );
  }
}

String _$isarServiceHash() => r'48546af1c1c2e7183e454863ef0ea57e5c0996f5';

@ProviderFor(isScanning)
final isScanningProvider = IsScanningProvider._();

final class IsScanningProvider
    extends $FunctionalProvider<AsyncValue<bool>, bool, Stream<bool>>
    with $FutureModifier<bool>, $StreamProvider<bool> {
  IsScanningProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'isScanningProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$isScanningHash();

  @$internal
  @override
  $StreamProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<bool> create(Ref ref) {
    return isScanning(ref);
  }
}

String _$isScanningHash() => r'a9bd21abaed46d3c198975088eed7554068a5d0a';

@ProviderFor(isServiceRunning)
final isServiceRunningProvider = IsServiceRunningProvider._();

final class IsServiceRunningProvider
    extends $FunctionalProvider<AsyncValue<bool>, bool, Stream<bool>>
    with $FutureModifier<bool>, $StreamProvider<bool> {
  IsServiceRunningProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'isServiceRunningProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$isServiceRunningHash();

  @$internal
  @override
  $StreamProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<bool> create(Ref ref) {
    return isServiceRunning(ref);
  }
}

String _$isServiceRunningHash() => r'2f3234e477cfcc8713abf0179f099f0182dead13';

@ProviderFor(scanStatus)
final scanStatusProvider = ScanStatusProvider._();

final class ScanStatusProvider
    extends
        $FunctionalProvider<
          AsyncValue<Map<String, dynamic>>,
          Map<String, dynamic>,
          Stream<Map<String, dynamic>>
        >
    with
        $FutureModifier<Map<String, dynamic>>,
        $StreamProvider<Map<String, dynamic>> {
  ScanStatusProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'scanStatusProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$scanStatusHash();

  @$internal
  @override
  $StreamProviderElement<Map<String, dynamic>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<Map<String, dynamic>> create(Ref ref) {
    return scanStatus(ref);
  }
}

String _$scanStatusHash() => r'64dd908ae4d2d0ce7c57cced4a0ce582f763f238';

@ProviderFor(scanProgress)
final scanProgressProvider = ScanProgressProvider._();

final class ScanProgressProvider
    extends $FunctionalProvider<AsyncValue<double>, double, Stream<double>>
    with $FutureModifier<double>, $StreamProvider<double> {
  ScanProgressProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'scanProgressProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$scanProgressHash();

  @$internal
  @override
  $StreamProviderElement<double> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<double> create(Ref ref) {
    return scanProgress(ref);
  }
}

String _$scanProgressHash() => r'709a7700a96e0ef30f2df9fe6f02fcbf320eeba0';

@ProviderFor(discoveredDevices)
final discoveredDevicesProvider = DiscoveredDevicesProvider._();

final class DiscoveredDevicesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<FoundDevice>>,
          List<FoundDevice>,
          Stream<List<FoundDevice>>
        >
    with
        $FutureModifier<List<FoundDevice>>,
        $StreamProvider<List<FoundDevice>> {
  DiscoveredDevicesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'discoveredDevicesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$discoveredDevicesHash();

  @$internal
  @override
  $StreamProviderElement<List<FoundDevice>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<FoundDevice>> create(Ref ref) {
    return discoveredDevices(ref);
  }
}

String _$discoveredDevicesHash() => r'b954b70f1d3f9ca8f6697e3c24d9a4de860470ef';

@ProviderFor(messages)
final messagesProvider = MessagesProvider._();

final class MessagesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Message>>,
          List<Message>,
          Stream<List<Message>>
        >
    with $FutureModifier<List<Message>>, $StreamProvider<List<Message>> {
  MessagesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'messagesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$messagesHash();

  @$internal
  @override
  $StreamProviderElement<List<Message>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<Message>> create(Ref ref) {
    return messages(ref);
  }
}

String _$messagesHash() => r'692355e034e57ca435ef255c9ca7b9faa24a4198';
