import 'package:isar_community/isar.dart';

part 'found_device.g.dart';

@Collection()
class FoundDevice {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late int stableId; // The new permanent ID

  @Index()
  late String remoteId; // The volatile MAC address

  String? name;

  late int rssi;

  late DateTime lastSeen;

  @Index()
  String? profileHash;

  List<int>? profilePicture;

  List<int>? publicKey; // 32-byte X25519 public key

  DateTime? lastPictureSync; // Time-based cache invalidation
}
