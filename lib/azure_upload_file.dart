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

class AzureProgressMessage {
  final double progress;
  final Object? error;
  final bool completed;

  AzureProgressMessage({
    required this.progress,
    this.error,
    this.completed = false,
  });

  @override
  bool operator ==(covariant AzureProgressMessage other) {
    if (identical(this, other)) return true;

    return other.progress == progress &&
        other.error == error &&
        other.completed == completed;
  }

  @override
  int get hashCode => progress.hashCode ^ error.hashCode ^ completed.hashCode;
}

class AzureUploadFile {
  late SharedPreferences _prefs;
  AzureStorage? _azureStorage;
  BehaviorSubject<Object?>? _errorSubj;
  late int _chunkSize;

  bool _initialized = false;
  bool _isPaused = true;

  static const String _filePathKey = "filePath";
  static const String _fileNameWithoutExtKey = "fileNameWithoutExt";
  static const String _sasLinkKey = "sasLinkKey";
  static const String _progressMapKey = "progressMapKey";

  static const String _offsetHeaderKey = "x-ms-blob-condition-appendpos";
  static const String _md5ChecksumHeaderKey = "Content-MD5";

  AzureUploadFile();

  Stream<AzureProgressMessage> get _progressStream =>
      CombineLatestStream.combine2(
        _azureStorage!.progressStream.doOnData((data) async {
          await _prefs.setString(_progressMapKey, jsonEncode(data));
        }),
        _errorSubj!.stream,
        (progressMap, e) {
          double progress = (progressMap as Map<String, int>).isEmpty
              ? 0
              : progressMap.values.reduce((a, b) => a + b) /
                  _azureStorage!.fileSize;
          progress = double.parse(progress.toStringAsFixed(2));
          if (e != null) debugPrint("error $e");
          return AzureProgressMessage(progress: progress, error: e);
        },
      ).distinct();

  void emitError(Object? e) {
    _errorSubj!.add(e);
  }

  Future<void> initWithSasLink(String sasLink, {bool isResume = false}) async {
    try {
      if (!_initialized) {
        throw Exception("You have to call first config()");
      }
      Map<String, int> progressMap = const {};
      if (isResume) {
        final String mapString = _prefs.getString(_progressMapKey)!;
        progressMap = jsonDecode(mapString) as Map<String, int>;
      }

      _azureStorage = AzureStorage.parseSasLink(
        sasLink,
        actualProgress: progressMap,
      );
      await _prefs.setString(_sasLinkKey, sasLink);
    } catch (e) {
      emitError(e);
    }
  }

  Future<void> config({int chunkSize = 1024 * 1024}) async {
    if (!_initialized) {
      _initialized = true;
      _chunkSize = chunkSize;
      _prefs = await SharedPreferences.getInstance();
    }
  }

  Stream<AzureProgressMessage> uploadFile(
    XFile file, {
    String fileNameWithoutExt = "video",
    bool resume = false,
  }) {
    try {
      if (!_initialized) {
        throw Exception("You have to call first config()");
      }
      _errorSubj?.close();
      _errorSubj = BehaviorSubject.seeded(null);
      _uploadStream(
        file,
        fileNameWithoutExt: fileNameWithoutExt,
        resume: resume,
      );
    } catch (e) {
      emitError(e);
    }

    return _progressStream;
  }

  void resumeUploadFile() {
    try {
      if (!_initialized) {
        throw Exception("You have to call first config()");
      }
      final String? filePath = _prefs.getString(_filePathKey);
      final String? fileNameWithoutExt =
          _prefs.getString(_fileNameWithoutExtKey);
      final String? sasLink = _prefs.getString(_sasLinkKey);

      if (filePath == null || fileNameWithoutExt == null || sasLink == null) {
        throw Exception("Not found upload to resume");
      }
      if (_azureStorage == null && sasLink.isNotEmpty) {
        initWithSasLink(sasLink, isResume: true);
      }

      // remove previous errors
      _errorSubj!.add(null);

      final XFile file = XFile(filePath);
      uploadFile(
        file,
        fileNameWithoutExt: fileNameWithoutExt,
        resume: true,
      );
    } catch (e) {
      emitError(e);
    }
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
        _azureStorage!.closeStream();
        _errorSubj?.close();
        _errorSubj = null;
        _isPaused = true;
        debugPrint("AzureUploadFile: completed");
      }
      debugPrint("AzureUploadFile: exited");
    } catch (e) {
      emitError(e);
    }
  }
}
