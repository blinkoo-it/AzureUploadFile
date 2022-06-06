library azure_upload_file;

import 'dart:async';
import 'dart:convert';

import 'package:azure_upload_file/src/azure_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:mime_type/mime_type.dart';
import 'package:rxdart/rxdart.dart';
import 'package:async/async.dart';
import 'package:cross_file/cross_file.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

export 'src/azure_storage.dart';

class AzureUploadFile {
  late SharedPreferences _prefs;
  AzureStorage? _azureStorage;
  late int _chunkSize;

  bool _initialized = false;

  static const String _filePathKey = 'filePath';
  static const String _fileNameWithoutExtKey = 'fileNameWithoutExt';
  static const String _sasLinkKey = 'sasLinkKey';

  static const String _offsetHeaderKey = 'x-ms-blob-condition-appendpos';
  static const String _md5ChecksumHeaderKey = 'Content-MD5';

  AzureUploadFile();

  void initWithSasLink(String sasLink) {
    if(!_initialized) {
      throw Exception("You have to call first config()");
    }
    _azureStorage = AzureStorage.parseSasLink(sasLink);
    _prefs.setString(_sasLinkKey, sasLink);
  }

  Future config({int chunkSize = 1024 * 1024}) async {
    if(!_initialized) {
      _initialized = true;
      _chunkSize = chunkSize;
      _prefs = await SharedPreferences.getInstance();
    }
  }

  Stream<double> uploadFile(XFile file, {String fileNameWithoutExt = 'video', bool resume = false}) {
    if(!_initialized) {
      throw Exception("You have to call first config()");
    }

    var outStream = DeferStream(()=> _uploadStream(file, fileNameWithoutExt: fileNameWithoutExt, resume: resume));
    return outStream.publish().refCount();
  }

  Stream<double> resumeUploadFile() {
    if(!_initialized) {
      throw Exception("You have to call first config()");
    }
    var filePath = _prefs.getString(_filePathKey);
    var fileNameWithoutExt = _prefs.getString(_fileNameWithoutExtKey);
    var sasLink = _prefs.getString(_sasLinkKey);
    if(filePath == null || fileNameWithoutExt == null || sasLink == null) {
      throw Exception("Not found upload to resume");
    }
    if(_azureStorage == null && sasLink.isNotEmpty) {
      initWithSasLink(sasLink);
    }
    var file = XFile(filePath);

    
    return uploadFile(file, fileNameWithoutExt: fileNameWithoutExt, resume: true );
  }


  Future<void> _deletePrefs() async {
    await _prefs.remove(_filePathKey);
    await _prefs.remove(_fileNameWithoutExtKey);
    await _prefs.remove(_sasLinkKey);
  }


  bool isPresentUploadToResume() {
    if(!_initialized) {
      throw Exception("You have to call first config()");
    }
    return _prefs.getString(_filePathKey) != null &&
        _prefs.getString(_fileNameWithoutExtKey) != null &&
        _prefs.getString(_sasLinkKey) != null;
  }

  Future<Map<String, String>> _getVideoMeta(String fileName) async {
    var res = await _azureStorage!.getBlobMetaData(fileName);
    return res;
  }

  Future<int> _getVideoContentLength(String fileName) async {
    var res = await _getVideoMeta(fileName);
    return int.tryParse(res['content-length']??'0') ?? 0;
  }


  Stream<double> _uploadStream(XFile file, { String fileNameWithoutExt = 'video', bool resume = false }) async* {
    String fileName = "$fileNameWithoutExt.${file.path.split('.').last}";
    int end = await file.length();
    var offsetPos = 0;
    if (resume) {
      offsetPos = await _getVideoContentLength(fileName);
    }

    _prefs.setString(_filePathKey, file.path);
    _prefs.setString(_fileNameWithoutExtKey, fileNameWithoutExt);

    var fileReader = ChunkedStreamReader(file.openRead(offsetPos));
    try {
      //Lo yield, funge anche da cancel, nel caso di "NESSUN" sottoscrittore
      yield(offsetPos / end);
      
      var nextBytes = await fileReader.readBytes(_chunkSize);
      while(nextBytes.isNotEmpty) {
         
        var headers = {_offsetHeaderKey : offsetPos.toString() };
        var digestBlock = md5.convert(nextBytes);
        var md5Checksum = base64.encode(digestBlock.bytes);
        headers.addAll({_md5ChecksumHeaderKey: md5Checksum});
        if(offsetPos == 0) {
          await _azureStorage!.putBlob(fileName, bodyBytes: nextBytes, contentType: mime(file.path), type: BlobType.AppendBlob, appendHeaders: headers);
        } else {
          await _azureStorage!.appendBlock(fileName, bodyBytes: nextBytes, headers: headers);
        }
        offsetPos += nextBytes.length;

        if(nextBytes.length < _chunkSize) {
          yield(1.0);
        } else {
          yield(offsetPos / end);
        }

        nextBytes = await fileReader.readBytes(_chunkSize);
      }
      

      _deletePrefs();
      if (kDebugMode) {
        print('AzureUploadFile: completed');
      }
    }
    finally {
      fileReader.cancel();
      if (kDebugMode) {
        print('AzureUploadFile: exited');
      }
    }
  }
}
