// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'file_to_upload.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class FileToUploadAdapter extends TypeAdapter<FileToUpload> {
  @override
  final int typeId = 0;

  @override
  FileToUpload read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return FileToUpload()
      ..path = fields[0] as String
      ..positionUploaded = fields[1] as int;
  }

  @override
  void write(BinaryWriter writer, FileToUpload obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.path)
      ..writeByte(1)
      ..write(obj.positionUploaded);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FileToUploadAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
