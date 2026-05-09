// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'advertising_name.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

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

String _$advertisingNameHash() => r'a61896801e89a3cb06ed907048fe2d368940d32e';

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
