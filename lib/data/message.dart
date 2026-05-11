import 'package:isar_community/isar.dart';

part 'message.g.dart';

@Collection()
class Message {
  Id id = Isar.autoIncrement;

  late int senderStableId;
  late int receiverStableId;
  late String content;
  late DateTime timestamp;

  late bool isReceived;
  late bool isImage;
  List<int>? data;
}
