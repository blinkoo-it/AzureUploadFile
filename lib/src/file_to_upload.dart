import 'package:hive_flutter/adapters.dart';

part 'file_to_upload.g.dart';

@HiveType(typeId: 0)
class FileToUpload extends HiveObject {

  @HiveField(0)
  late String path;

  @HiveField(1)
  late int positionUploaded;
}