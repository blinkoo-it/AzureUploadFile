import "dart:async";
import "dart:io";

import "package:azure_upload_file/azure_upload_file.dart";
import "package:azure_upload_file/src/azure_storage_exception.dart";
import "package:dio/dio.dart";
import "package:flutter/foundation.dart";
import "package:rxdart/rxdart.dart";

/// Blob type
enum BlobType {
  blockBlob,
  appendBlob,
}

class AzureStorage {
  late Map<String, String> _config;
  final Dio _dio = Dio();
  late BehaviorSubject<Map<int, int>> _progressSubj;
  late int _fileSize;

  static const String queryPathKey = "QueryPath";
  static const String queryParamsKey = "QueryParams";

  int get fileSize => _fileSize;

  AzureStorage.parseSasLink(
    String sasLink, {
    Map<int, int>? actualProgress,
  }) {
    try {
      _config = {};
      final List<String> urlSplitted = sasLink.split("?");
      _config[queryPathKey] = urlSplitted[0];
      _config[queryParamsKey] = urlSplitted[1];
      initStream(actualProgress);
    } catch (e) {
      throw Exception("Parse error.");
    }
  }

  void initStream(Map<int, int>? actualProgress) {
    _progressSubj = BehaviorSubject.seeded(actualProgress ?? const {});
  }

  void closeStream() {
    _progressSubj.close();
  }

  Stream<Map<int, int>> get progressStream => _progressSubj.stream;

  void _updateProgressSubj(int part, int count) {
    _progressSubj.add({..._progressSubj.value, part: count});
  }

  @override
  String toString() {
    return _config.toString();
  }

  Uri _uri({
    String fileName = "/",
    Map<String, String>? queryParameters,
  }) {
    final String? queryPath = _config[queryPathKey];
    final String? queryParams = _config[queryParamsKey];
    String url = "$queryPath/$fileName?$queryParams";

    if (queryParameters != null) {
      final List<String> list = List.empty(growable: true);
      queryParameters.forEach((k, v) => list.add("$k=$v"));
      url = '$url&${list.join('&')}';
    }

    return Uri.parse(url);
  }

  /// Put Blob.
  ///
  /// `body` and `bodyBytes` are exclusive and mandatory.
  Future<void> putBlob(
    String fileName, {
    String? body,
    Uint8List? bodyBytes,
    String? contentType,
    BlobType type = BlobType.blockBlob,
    Map<String, String>? headers,
    Map<String, String>? appendHeaders,
    required int fileSize,
  }) async {
    assert(
      body != null || bodyBytes != null,
      "'body' or 'bodyBytes' are exclusive and mandatory",
    );
    assert(
      !(body != null && bodyBytes != null),
      "'body' and 'bodyBytes' are exclusive",
    );
    try {
      _fileSize = fileSize;
      final Map<String, dynamic> requestHeaders = {
        "x-ms-blob-type":
            type == BlobType.appendBlob ? "AppendBlob" : "BlockBlob",
        "x-ms-blob-content-disposition": "inline",
      };
      headers?.forEach((key, value) {
        requestHeaders["x-ms-meta-$key"] = value;
      });

      dynamic requestBody;
      if (type == BlobType.blockBlob) {
        if (bodyBytes != null) {
          requestBody = bodyBytes;
        } else if (body != null) {
          requestBody = body;
        }
      } else {
        requestBody = "";
      }

      final Response<String> response = await _dio.putUri(
        _uri(fileName: fileName),
        data: requestBody,
        options: Options(
          contentType: contentType,
          headers: requestHeaders,
        ),
        onSendProgress: (count, total) => _updateProgressSubj(0, count),
      );
      if (response.statusCode == HttpStatus.created) {
        if (type == BlobType.appendBlob &&
            (body != null || bodyBytes != null)) {
          await appendBlock(
            fileName,
            part: 0,
            body: body,
            bodyBytes: bodyBytes,
            headers: appendHeaders,
            contentType: contentType,
            fileSize: _fileSize,
          );
        }
        return;
      }

      final String message = response.data ?? "";
      throw AzureStorageException(
        message,
        response.statusCode ?? 0,
        response.headers.map,
      );
    } catch (e) {
      _progressSubj.addError(e);
      rethrow;
    }
  }

  ///
  /// GetBlobMeta
  ///
  Future<Map<String, String>> getBlobMetaData(
    String fileName, {
    Map<String, String>? headers,
  }) async {
    try {
      final Map<String, dynamic> requestHeaders = {};
      headers?.forEach((key, value) {
        requestHeaders["x-ms-meta-$key"] = value;
      });

      final Response<String> response = await _dio.headUri(
        _uri(fileName: fileName),
        options: Options(
          contentType: "plain/text",
          headers: headers,
        ),
      );
      if (response.statusCode == HttpStatus.ok) {
        return response.headers.map.map(
          (key, value) => MapEntry(key, value.join(",")),
        );
      }

      final String message = response.data ?? "";
      throw AzureStorageException(
        message,
        response.statusCode ?? 0,
        response.headers.map,
      );
    } catch (e) {
      _progressSubj.addError(e);
      rethrow;
    }
  }

  /// Append block to blob.
  Future<void> appendBlock(
    String fileName, {
    required int part,
    String? body,
    Uint8List? bodyBytes,
    Map<String, String>? headers,
    String? contentType,
    required int fileSize,
  }) async {
    assert(
      body != null || bodyBytes != null,
      "'body' or 'bodyBytes' are exclusive and mandatory",
    );
    assert(
      !(body != null && bodyBytes != null),
      "'body' and 'bodyBytes' are exclusive",
    );
    try {
      if (AzureUploadFile.kaboomizer && part == 2) {
        AzureUploadFile.kaboomizer = false;
        throw Exception("KABOOM!!!");
      }

      _fileSize = fileSize;
      // debugPrint("Filesize: $fileSize");
      // debugPrint("part: $part");

      final dynamic requestBody = bodyBytes ?? body;

      final Response<String> response = await _dio.putUri(
        _uri(fileName: fileName, queryParameters: {"comp": "appendblock"}),
        data: requestBody,
        options: Options(
          contentType: contentType,
          headers: headers,
        ),
        onSendProgress: (count, total) => _updateProgressSubj(part, count),
      );

      if (response.statusCode == HttpStatus.created) return;

      final String message = response.data ?? "";
      throw AzureStorageException(
        message,
        response.statusCode ?? 0,
        response.headers.map,
      );
    } catch (e) {
      _progressSubj.addError(e);
      rethrow;
    }
  }
}
