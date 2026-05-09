import 'package:isar_community/isar.dart';

part 'message.g.dart';

@Collection()
class Message {
  Id id = Isar.autoIncrement;

  late String senderId;
  late String receiverId;
  late String content;
  late DateTime timestamp;
}
