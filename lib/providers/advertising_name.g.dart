// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'advertising_name.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(CanAdvertise)
final canAdvertiseProvider = CanAdvertiseProvider._();

final class CanAdvertiseProvider
    extends $NotifierProvider<CanAdvertise, bool?> {
  CanAdvertiseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'canAdvertiseProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$canAdvertiseHash();

  @$internal
  @override
  CanAdvertise create() => CanAdvertise();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool?>(value),
    );
  }
}

String _$canAdvertiseHash() => r'd40a1f1c6d58831285089bb3eb74054dd66d93a9';

abstract class _$CanAdvertise extends $Notifier<bool?> {
  bool? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<bool?, bool?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool?, bool?>,
              bool?,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

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

String _$isAdvertisingHash() => r'e35f3a366fea82435ab604ad375603ba56369699';

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

String _$advertisingNameHash() => r'2cf78be572eaf4729c6cbb4c6dfe08edf62d809a';

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
