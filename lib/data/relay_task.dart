import 'package:isar_community/isar.dart';

part 'relay_task.g.dart';

@collection
class RelayTask {
  Id id = Isar.autoIncrement;

  @Index()
  late int messageId;
  
  @Index()
  late int originId;

  late int targetId; // Final destination for Relay, or specific neighbor for ACK
  
  late int type; // typeRelay (0x04) or typeAck (0x05)

  late List<int> data; // The raw packet bytes

  // For ACKs: Who still needs to receive this?
  // For Relays: Who has already received this?
  late List<int> pendingNeighborIds;

  @Index()
  late DateTime createdAt;

  int sentCount = 0;
}
