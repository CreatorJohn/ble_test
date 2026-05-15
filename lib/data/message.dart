import 'package:isar_community/isar.dart';

part 'message.g.dart';

@Collection()
class Message {
  Id id = Isar.autoIncrement;

  @Index()
  late int senderStableId;
  @Index()
  late int receiverStableId;
  late String content;
  late DateTime timestamp;

  late bool isReceived;
  late bool isImage;
  List<int>? data;

  bool isDelivered = false;
  bool wasSent = false;
  @Index()
  int? messageId;
}
