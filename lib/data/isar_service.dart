import 'package:ble_test/data/found_device.dart';
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
      [FoundDeviceSchema],
      directory: dir.path,
    );
  }

  Stream<List<FoundDevice>> watchFoundDevices() {
    return db.foundDevices.where().sortByLastSeenDesc().watch(fireImmediately: true);
  }

  Future<void> putFoundDevice(FoundDevice device) async {
    await db.writeTxn(() async {
      await db.foundDevices.put(device);
    });
  }

  Future<void> clearDevices() async {
    await db.writeTxn(() async {
      await db.foundDevices.clear();
    });
  }
}
