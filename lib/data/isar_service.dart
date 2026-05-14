import 'package:ble_test/data/found_device.dart';
import 'package:ble_test/data/message.dart';
import 'package:isar_community/isar.dart';
import 'package:path_provider/path_provider.dart';

class IsarService {
  static final IsarService _instance = IsarService._internal();
  Isar? _isar;

  factory IsarService() => _instance;

  IsarService._internal();

  Isar get db {
    if (_isar == null) {
      throw Exception("Isar not initialized. Call initialize() first.");
    }
    return _isar!;
  }

  bool get isOpen => _isar?.isOpen ?? false;

  Future<void> initialize() async {
    if (_isar != null && _isar!.isOpen) return;

    final dir = await getApplicationDocumentsDirectory();
    _isar = await Isar.open(
      [FoundDeviceSchema, MessageSchema],
      directory: dir.path,
    );
  }

  Stream<List<FoundDevice>> watchFoundDevices() {
    return db.foundDevices.where().sortByLastSeenDesc().watch(fireImmediately: true);
  }

  Stream<List<Message>> watchMessages() {
    return db.messages.where().sortByTimestampDesc().watch(fireImmediately: true);
  }

  Future<void> putFoundDevice(FoundDevice device) async {
    await db.writeTxn(() async {
      await db.foundDevices.put(device);
    });
  }

  Future<void> putMessage(Message message) async {
    await db.writeTxn(() async {
      await db.messages.put(message);
    });
  }

  Future<List<FoundDevice>> findActiveNeighbors(int excludeId) async {
    final sixtySecondsAgo = DateTime.now().subtract(const Duration(seconds: 60));
    return await db.foundDevices
        .filter()
        .lastSeenGreaterThan(sixtySecondsAgo)
        .not()
        .stableIdEqualTo(excludeId)
        .findAll();
  }

  Future<FoundDevice?> findDeviceByRemoteId(String remoteId) async {
    return await db.foundDevices.filter().remoteIdEqualTo(remoteId).findFirst();
  }

  Future<void> clearDevices() async {
    await db.writeTxn(() async {
      await db.foundDevices.clear();
      await db.messages.clear();
    });
  }
}
