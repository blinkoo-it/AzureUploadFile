library azure_upload_file;

import 'dart:async';
import 'dart:convert';

import 'package:async/async.dart';
import 'package:azure_upload_file/src/azure_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';
import 'package:cross_file/cross_file.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

export 'src/azure_storage.dart';

class AzureUploadFile {
  late SharedPreferences _prefs;
  AzureStorage? _azureStorage;
  late int _chunkSize;

  bool _initialized = false;
  bool _isPaused = true;

  static const String _filePathKey = 'filePath';
  static const String _fileNameWithoutExtKey = 'fileNameWithoutExt';
  static const String _sasLinkKey = 'sasLinkKey';

  static const String _offsetHeaderKey = 'x-ms-blob-condition-appendpos';
  static const String _md5ChecksumHeaderKey = 'Content-MD5';

  AzureUploadFile();

  void initWithSasLink(String sasLink) {
    if (!_initialized) {
      throw Exception("You have to call first config()");
    }
    _azureStorage = AzureStorage.parseSasLink(sasLink);
    _prefs.setString(_sasLinkKey, sasLink);
  }

  Future<void> config({int chunkSize = 1024 * 1024}) async {
    if (!_initialized) {
      _initialized = true;
      _chunkSize = chunkSize;
      _prefs = await SharedPreferences.getInstance();
    }
  }

  Stream<double> uploadFile(
    XFile file, {
    String fileNameWithoutExt = 'video',
    bool resume = false,
  }) {
    if (!_initialized) {
      throw Exception("You have to call first config()");
    }
    _uploadStream(
      file,
      fileNameWithoutExt: fileNameWithoutExt,
      resume: resume,
    );

    return _azureStorage!.progressStream;
  }

  Stream<double> resumeUploadFile() {
    if (!_initialized) {
      throw Exception("You have to call first config()");
    }
    final String? filePath = _prefs.getString(_filePathKey);
    final String? fileNameWithoutExt = _prefs.getString(_fileNameWithoutExtKey);
    final String? sasLink = _prefs.getString(_sasLinkKey);

    if (filePath == null || fileNameWithoutExt == null || sasLink == null) {
      throw Exception("Not found upload to resume");
    }
    if (_azureStorage == null && sasLink.isNotEmpty) {
      initWithSasLink(sasLink);
    }
    final XFile file = XFile(filePath);

    return uploadFile(
      file,
      fileNameWithoutExt: fileNameWithoutExt,
      resume: true,
    );
  }

  void pauseUploadFile() {
    _isPaused = true;
  }

  Future<void> _deletePrefs() async {
    await _prefs.remove(_filePathKey);
    await _prefs.remove(_fileNameWithoutExtKey);
    await _prefs.remove(_sasLinkKey);
  }

  bool isPresentUploadToResume() {
    if (!_initialized) {
      throw Exception("You have to call first config()");
    }
    final String? filePath = _prefs.getString(_filePathKey);
    final String? fileNameWithoutExt = _prefs.getString(_fileNameWithoutExtKey);
    final String? sasLink = _prefs.getString(_sasLinkKey);

    return filePath != null && fileNameWithoutExt != null && sasLink != null;
  }

  Future<Map<String, String>> _getVideoMeta(String fileName) =>
      _azureStorage!.getBlobMetaData(fileName);

  Future<int> _getVideoContentLength(String fileName) async {
    final Map<String, String> res = await _getVideoMeta(fileName);
    return int.tryParse(res['content-length'] ?? '0') ?? 0;
  }

  Future<void> _uploadStream(
    XFile file, {
    String fileNameWithoutExt = 'video',
    bool resume = false,
  }) async {
    final String fileName = "$fileNameWithoutExt.${file.path.split('.').last}";
    final int end = await file.length();
    final String? contentType = lookupMimeType(file.path);
    int offsetPos = 0;

    if (resume) {
      offsetPos = await _getVideoContentLength(fileName);
    }

    _prefs.setString(_filePathKey, file.path);
    _prefs.setString(_fileNameWithoutExtKey, fileNameWithoutExt);

    final ChunkedStreamReader<int> fileReader =
        ChunkedStreamReader(file.openRead(offsetPos));
    Uint8List? nextBytes;
    _isPaused = false;
    try {
      nextBytes = await fileReader.readBytes(_chunkSize);
      // when there are no listeners, we pause uploading.
      // with firstCall we can resume correctly after a pause since
      // there are no listeners yet
      while (nextBytes!.isNotEmpty && !_isPaused) {
        final Map<String, String> headers = {
          _offsetHeaderKey: offsetPos.toString()
        };
        final Digest digestBlock = md5.convert(nextBytes);
        final String md5Checksum = base64.encode(digestBlock.bytes);
        headers.addAll({_md5ChecksumHeaderKey: md5Checksum});
        if (offsetPos == 0) {
          await _azureStorage!.putBlob(
            fileName,
            bodyBytes: nextBytes,
            contentType: contentType,
            type: BlobType.appendBlob,
            appendHeaders: headers,
            fileSize: end,
          );
        } else {
          await _azureStorage!.appendBlock(
            fileName,
            part: offsetPos ~/ _chunkSize,
            bodyBytes: nextBytes,
            headers: headers,
            contentType: contentType,
            fileSize: end,
          );
        }
        offsetPos += nextBytes.length;

        nextBytes = await fileReader.readBytes(_chunkSize);
      }
      if (nextBytes.isEmpty == true) {
        _deletePrefs();
        debugPrint('AzureUploadFile: completed');
      }
    } finally {
      fileReader.cancel();
      if (nextBytes?.isEmpty == true) {
        _azureStorage!.closeStream();
        _isPaused = true;
      }
      debugPrint('AzureUploadFile: exited');
    }
  }
}
