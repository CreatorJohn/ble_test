// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'system_health.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(SystemHealth)
final systemHealthProvider = SystemHealthProvider._();

final class SystemHealthProvider
    extends $NotifierProvider<SystemHealth, SystemHealthState> {
  SystemHealthProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'systemHealthProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$systemHealthHash();

  @$internal
  @override
  SystemHealth create() => SystemHealth();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SystemHealthState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SystemHealthState>(value),
    );
  }
}

String _$systemHealthHash() => r'bd20fb3c32d53d7f546c35ba1309e3347b9f48bb';

abstract class _$SystemHealth extends $Notifier<SystemHealthState> {
  SystemHealthState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<SystemHealthState, SystemHealthState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SystemHealthState, SystemHealthState>,
              SystemHealthState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
