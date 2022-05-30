library azure_upload_file;

import 'package:azure_upload_file/src/azure_storage.dart';
import 'package:hive_flutter/adapters.dart';
import 'package:mime_type/mime_type.dart';
import 'package:rxdart/rxdart.dart';
import 'package:async/async.dart';
import 'package:cross_file/cross_file.dart';

export 'src/azure_storage.dart';

class AzureUploadFile {
  late BehaviorSubject<double> _progress;
  late CancelableOperation _uploadProcessToken;
  late Box _box;
  AzureStorage? _azureStorage;
  late int _chunkSize;

  bool _initialized = false;

  static const String _filePathKey = 'filePath';
  static const String _fileNameWithoutExtKey = 'fileNameWithoutExt';
  static const String _sasLinkKey = 'sasLinkKey';

  AzureUploadFile();

  void initWithSasLink(String sasLink) {
    if(!_initialized) {
      throw Exception("You have to call first config()");
    }
    _azureStorage = AzureStorage.parseSasLink(sasLink);
    _box.put(_sasLinkKey, sasLink);
  }

  Future config({int chunkSize = 1024 * 1024}) async {
    if(!_initialized) {
      _chunkSize = chunkSize;
      _box = await Hive.openBox('fileUpload');
      _initialized = true;
    }
  }

  Stream<double> uploadFile(XFile file, {String fileNameWithoutExt = 'video'}) {
    if(!_initialized) {
      throw Exception("You have to call first config()");
    }
    _isInPause = false;
    _progress = BehaviorSubject<double>();
    _uploadProcessToken =  CancelableOperation.fromFuture(_uploadFileInternal(file, fileNameWithoutExt: fileNameWithoutExt));
    return _progress;
  }

  Stream<double> resumeUploadFile() {
    if(!_initialized) {
      throw Exception("You have to call first config()");
    }
    _progress = BehaviorSubject<double>();
    if(!_box.isOpen && _box.isEmpty) {
      throw Exception("Not found upload to resume");
    }
    var filePath = _box.get(_filePathKey) as String;
    
    var fileNameWithoutExt = _box.get(_fileNameWithoutExtKey, defaultValue: 'video') as String;
    var sasLink = _box.get(_sasLinkKey, defaultValue: '') as String;
    if(_azureStorage == null && sasLink.isNotEmpty) {
      initWithSasLink(sasLink);
    }
    var file = XFile(filePath);
    _uploadProcessToken =  CancelableOperation.fromFuture(_uploadFileInternal(file, fileNameWithoutExt: fileNameWithoutExt, resume: true));
    return _progress;
  }

  Future<void> _onCancelUpload() async {
    if(!_isInPause) {
      await _box.clear();
      await _box.close();
    }
  }

  Future<void> stopUpload() async {
    _isInPause = false;
    await _uploadProcessToken.cancel();
  }

  bool _isInPause = false;
  Future<void> pauseUpload() async {
    if(_box.isOpen && _box.isNotEmpty) {
      _isInPause = true;
      await _uploadProcessToken.cancel();
    }
  }

  bool isPresentUploadToResume() {
    if(!_initialized) {
      throw Exception("You have to call first config()");
    }
    return _box.isNotEmpty;
  }

  Future<Map<String, String>> _getVideoMeta(String fileName) async {
    // var filePath = _box.get(_filePathKey) as String;
    // String fileName = "$fileNameWithoutExt.${filePath.split('.').last}";
    var res = await _azureStorage!.getBlobMetaData(fileName);
    return res;
  }

  Future<int> _getVideoContentLength(String fileName) async {
    // var filePath = _box.get(_filePathKey) as String;
    // String fileName = "$fileNameWithoutExt.${filePath.split('.').last}";

    var res = await _getVideoMeta(fileName);
    return int.tryParse(res['content-length']??'0') ?? 0;
  }


  Future<void> _uploadFileInternal(XFile file, { String fileNameWithoutExt = 'video', bool resume = false }) async {
    String fileName = "$fileNameWithoutExt.${file.path.split('.').last}";
    int end = await file.length();
    var offsetPos = 0;
    if (resume) {
      offsetPos = await _getVideoContentLength(fileName);
    }

    if(!_box.isOpen) {
      _box = await Hive.openBox('fileUpload');
    }
    if(_box.isNotEmpty) {
      await _box.clear();
    }


    await _box.put(_filePathKey, file.path);
    await _box.put(_fileNameWithoutExtKey, fileNameWithoutExt);

    var fileReader = ChunkedStreamReader(file.openRead(offsetPos));
    try {
      _progress.add(offsetPos / end);
      var nextBytes = await fileReader.readBytes(_chunkSize);
      while(nextBytes.isNotEmpty && !_uploadProcessToken.isCanceled) {
        if(offsetPos == 0) {
          await _azureStorage!.putBlob(fileName, bodyBytes: nextBytes, contentType: mime(file.path), type: BlobType.AppendBlob);
        } else {
          await _azureStorage!.appendBlock(fileName, bodyBytes: nextBytes);
        }
        offsetPos += nextBytes.length;

        if(nextBytes.length < _chunkSize) {
          _progress.add(1.0);
        } else {
          _progress.add(offsetPos / end);
        }

        nextBytes = await fileReader.readBytes(_chunkSize);
      }
      if(!_uploadProcessToken.isCanceled) {
        _progress.close();
        _box.clear();
      } else {
        await _onCancelUpload();
      }
    } catch(e) {
      _progress.addError(e);
    }
    finally {
      fileReader.cancel();
    }
  }
}
