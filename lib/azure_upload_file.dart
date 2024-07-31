library azure_upload_file;

import "dart:async";
import "dart:convert";

import "package:async/async.dart";
import "package:azure_upload_file/src/azure_storage.dart";
import "package:cross_file/cross_file.dart";
import "package:crypto/crypto.dart";
import "package:flutter/foundation.dart";
import "package:mime/mime.dart";
import "package:rxdart/rxdart.dart";
import "package:shared_preferences/shared_preferences.dart";

export "src/azure_storage.dart";

class AzureUploadFile {
  late SharedPreferences _prefs;
  AzureStorage? _azureStorage;
  late int _chunkSize;

  static bool kaboomizer = true;

  bool _initialized = false;
  bool _isPaused = true;
  Map<int, int>? _progressMap;
  XFile? _xFile;

  static const String _filePathKey = "filePath";
  static const String _fileNameWithoutExtKey = "fileNameWithoutExt";
  static const String _sasLinkKey = "sasLinkKey";

  static const String _offsetHeaderKey = "x-ms-blob-condition-appendpos";
  static const String _md5ChecksumHeaderKey = "Content-MD5";

  AzureUploadFile();

  Stream<double> get _progressStream => _azureStorage!.progressStream
      .doOnData((map) {
        _progressMap = map;
      })
      .map<double>(
        (progressMap) => progressMap.values.isEmpty
            ? 0
            : progressMap.values.reduce((a, b) => a + b) /
                _azureStorage!.fileSize,
      )
      .map((val) => double.parse(val.toStringAsFixed(2)))
      .distinct();

  Future<void> initWithSasLink(String sasLink, {bool isResume = false}) async {
    if (!_initialized) {
      throw Exception("You have to call first config()");
    }
    if (!isResume) _progressMap = const {};

    _azureStorage =
        AzureStorage.parseSasLink(sasLink, actualProgress: _progressMap);
    await _prefs.setString(_sasLinkKey, sasLink);
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
    String fileNameWithoutExt = "video",
    bool resume = false,
  }) {
    if (!_initialized) {
      throw Exception("You have to call first config()");
    }
    _xFile = file;
    _uploadStream(
      file,
      fileNameWithoutExt: fileNameWithoutExt,
      resume: resume,
    );

    return _progressStream;
  }

  Future<Stream<double>> resumeUploadFile() async {
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
      await initWithSasLink(sasLink, isResume: true);
    } else if (_azureStorage != null) {
      _azureStorage!.initStream(_progressMap);
    }
    _xFile ??= XFile(filePath);
    return uploadFile(
      _xFile!,
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
    return int.tryParse(res["content-length"] ?? "0") ?? 0;
  }

  Future<void> _uploadStream(
    XFile file, {
    String fileNameWithoutExt = "video",
    bool resume = false,
  }) async {
    final String fileName = "$fileNameWithoutExt.${file.path.split('.').last}";
    final int end = await file.length();
    final String? contentType = lookupMimeType(file.path);
    int offsetPos = 0;

    if (resume) {
      offsetPos = await _getVideoContentLength(fileName);
    }

    await _prefs.setString(_filePathKey, file.path);
    await _prefs.setString(_fileNameWithoutExtKey, fileNameWithoutExt);

    final ChunkedStreamReader<int> fileReader =
        ChunkedStreamReader(file.openRead(offsetPos));
    Uint8List? nextBytes;
    _isPaused = false;
    try {
      nextBytes = await fileReader.readBytes(_chunkSize);
      // when _isPaused is true we pause the upload
      while (nextBytes!.isNotEmpty && !_isPaused) {
        final Map<String, String> headers = {
          _offsetHeaderKey: offsetPos.toString(),
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
        await fileReader.cancel();
        // debugPrint('AzureUploadFile: completed');
      }
    } finally {
      if (nextBytes?.isEmpty == true) {
        _azureStorage!.closeStream();
        _xFile = null;
        _isPaused = true;
      }
      // debugPrint('AzureUploadFile: exited');
    }
  }
}
