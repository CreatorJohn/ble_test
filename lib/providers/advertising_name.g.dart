// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'advertising_name.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(IsAdvertising)
final isAdvertisingProvider = IsAdvertisingProvider._();

final class IsAdvertisingProvider
    extends $NotifierProvider<IsAdvertising, bool> {
  IsAdvertisingProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'isAdvertisingProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$isAdvertisingHash();

  @$internal
  @override
  IsAdvertising create() => IsAdvertising();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$isAdvertisingHash() => r'cd6d84e971367172bea1648dec05f24fba482d83';

abstract class _$IsAdvertising extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

@ProviderFor(AdvertisingName)
final advertisingNameProvider = AdvertisingNameProvider._();

final class AdvertisingNameProvider
    extends $AsyncNotifierProvider<AdvertisingName, String> {
  AdvertisingNameProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'advertisingNameProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$advertisingNameHash();

  @$internal
  @override
  AdvertisingName create() => AdvertisingName();
}

String _$advertisingNameHash() => r'96b38673f252601a2bfe27123550ca28ca9c9095';

abstract class _$AdvertisingName extends $AsyncNotifier<String> {
  FutureOr<String> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<String>, String>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<String>, String>,
              AsyncValue<String>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
