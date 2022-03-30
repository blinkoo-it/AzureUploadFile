library azure_upload_file;

import 'package:azure_upload_file/src/azure_storage.dart';
import 'package:azure_upload_file/src/file_to_upload.dart';
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
    var fileUpload = box.get(0) as FileToUpload;
    var file = XFile(fileUpload.path);
    uploadProcessToken =  CancelableOperation.fromFuture(_uploadFileInternal(file, fromPosition: fileUpload.positionUploaded));
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
    box = await Hive.openBox('fileUpload');

    var fileUpload = FileToUpload()
      ..path = file.path
      ..positionUploaded = fromPosition;
    if(box.isNotEmpty) {
      await box.clear();
    }
    box.add(fileUpload);

    fileReader = ChunkedStreamReader(file.openRead(fileUpload.positionUploaded * chunkSize));
    try {
      progress.add((fileUpload.positionUploaded * chunkSize) / end);
      var nextBytes = await fileReader.readBytes(chunkSize);
      while(nextBytes.isNotEmpty && !uploadProcessToken.isCanceled) {
        if(fileUpload.positionUploaded == 0) {
          await azureStorage.putBlob(fileName, bodyBytes: nextBytes, contentType: mime(fileUpload.path), type: BlobType.AppendBlob);
        } else {
          await azureStorage.appendBlock(fileName, bodyBytes: nextBytes);
        }
        fileUpload.positionUploaded++;
        await fileUpload.save();
        if(nextBytes.length < chunkSize) {
          progress.add(1.0);
        } else {
          progress.add((fileUpload.positionUploaded * chunkSize) / end);
        }
        nextBytes = await fileReader.readBytes(chunkSize);
      }
      if(!uploadProcessToken.isCanceled) {
        progress.close();
        fileUpload.delete();
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
