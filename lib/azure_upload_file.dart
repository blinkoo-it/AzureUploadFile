library azure_upload_file;

import 'package:azure_upload_file/src/azure_storage.dart';
import 'package:hive_flutter/adapters.dart';
import 'package:mime_type/mime_type.dart';
import 'package:rxdart/rxdart.dart';
import 'package:async/async.dart';
import 'package:cross_file/cross_file.dart';

export 'src/azure_storage.dart';

class AzureUploadFile {
  late BehaviorSubject<double> progress;
  late CancelableOperation uploadProcessToken;
  late Box box;
  late ChunkedStreamReader<int> fileReader;
  late AzureStorage azureStorage;

  static const String _filePathKey = 'filePath';
  static const String _positionUploadedKey = 'positionUploaded';
  static const String _fileNameWithoutExtKey = 'fileNameWithoutExt';

  AzureUploadFile.initWithSasLink(String sasLink) {
    azureStorage = AzureStorage.parseSasLink(sasLink);
  }

  Stream<double> uploadFile(XFile file, {String fileNameWithoutExt = 'video'}) {
    progress = BehaviorSubject<double>();
    uploadProcessToken =  CancelableOperation.fromFuture(_uploadFileInternal(file, fileNameWithoutExt: fileNameWithoutExt));
    return progress;
  }

  Stream<double> resumeUploadFile() {
    progress = BehaviorSubject<double>();
    if(box.isEmpty) {
      throw Exception("Not found upload to resume");
    }
    var filePath = box.get(_filePathKey) as String;
    var positionToUpload = box.get(_positionUploadedKey) as int;
    var fileNameWithoutExt = box.get(_fileNameWithoutExtKey, defaultValue: 'video') as String;
    var file = XFile(filePath);
    uploadProcessToken =  CancelableOperation.fromFuture(_uploadFileInternal(file, fileNameWithoutExt: fileNameWithoutExt, fromPosition: positionToUpload));
    return progress;
  }

  Future<void> _clearUpload() async {
    // We always cancel the ChunkedStreamReader, this ensures the underlying
    // stream is cancelled.
    fileReader.cancel();
  }

  Future<void> _onCancelUpload() async {
    await _clearUpload();
    await box.clear();
    await box.close();
  }

  Future<void> stopUpload() async {
    uploadProcessToken.cancel();
  }

  Future<void> _uploadFileInternal(XFile file, {int fromPosition = 0, String fileNameWithoutExt = 'video'}) async {
    const int chunkSize = 1024 * 1024;
    String fileName = "$fileNameWithoutExt.${file.path.split('.').last}";
    int end = await file.length();
    int positionUploaded = fromPosition;
    box = await Hive.openBox('fileUpload');

    if(box.isNotEmpty) {
      await box.clear();
    }

    await box.put(_filePathKey, file.path);
    await box.put(_positionUploadedKey, positionUploaded);
    await box.put(_fileNameWithoutExtKey, fileNameWithoutExt);

    fileReader = ChunkedStreamReader(file.openRead(positionUploaded * chunkSize));
    try {
      progress.add((positionUploaded * chunkSize) / end);
      var nextBytes = await fileReader.readBytes(chunkSize);
      while(nextBytes.isNotEmpty && !uploadProcessToken.isCanceled) {
        if(positionUploaded == 0) {
          await azureStorage.putBlob(fileName, bodyBytes: nextBytes, contentType: mime(file.path), type: BlobType.AppendBlob);
        } else {
          await azureStorage.appendBlock(fileName, bodyBytes: nextBytes);
        }
        positionUploaded++;
        await box.put(_positionUploadedKey, positionUploaded);
        if(nextBytes.length < chunkSize) {
          progress.add(1.0);
        } else {
          progress.add((positionUploaded * chunkSize) / end);
        }
        nextBytes = await fileReader.readBytes(chunkSize);
      }
      if(!uploadProcessToken.isCanceled) {
        progress.close();
        box.clear();
      } else {
        await _onCancelUpload();
      }
    } catch(e) {
      progress.addError(e);
    }
    finally {
      _clearUpload();
    }
  }
}
