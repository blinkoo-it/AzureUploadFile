import 'dart:async';

import 'package:azure_upload_file/src/azure_storage_exception.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:rxdart/rxdart.dart';

/// Blob type
enum BlobType {
  blockBlob,
  appendBlob,
}

class AzureStorage {
  late Map<String, String> _config;
  Map<int, int> _progressValue = {};
  final Dio _dio = Dio();
  late BehaviorSubject<Map<int, int>> _progressSubj;
  late int _fileSize;

  static const String queryPathKey = 'QueryPath';
  static const String queryParamsKey = 'QueryParams';

  AzureStorage.parseSasLink(String sasLink) {
    try {
      final Map<String, String> m = {};
      final List<String> urlSplitted = sasLink.split('?');
      m[queryPathKey] = urlSplitted[0];
      m[queryParamsKey] = urlSplitted[1];
      _config = m;
      _progressSubj = BehaviorSubject.seeded(_progressValue);
    } catch (e) {
      throw Exception('Parse error.');
    }
  }

  void closeStream() {
    _progressSubj.close();
  }

  Stream<double> get progressStream => _progressSubj.stream
      .share()
      .map<double>(
        (progressMap) => (progressMap.values.isEmpty
            ? 0
            : progressMap.values.reduce((a, b) => a + b) / _fileSize),
      )
      .map((val) => double.parse(val.toStringAsFixed(2)))
      .distinct();

  void _updateProgressSubj(int part, int count) {
    _progressValue = {..._progressSubj.value, part: count};
    _progressSubj.add(_progressValue);
  }

  @override
  String toString() {
    return _config.toString();
  }

  Uri _uri({
    String fileName = '/',
    Map<String, String>? queryParameters,
  }) {
    final String? queryPath = _config[queryPathKey];
    final String? queryParams = _config[queryParamsKey];
    String url = '$queryPath/$fileName?$queryParams';

    if (queryParameters != null) {
      final List<String> list = List.empty(growable: true);
      queryParameters.forEach((k, v) => list.add('$k=$v'));
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
    _fileSize = fileSize;
    final Map<String, dynamic> requestHeaders = {
      'x-ms-blob-type':
          type == BlobType.appendBlob ? 'AppendBlob' : 'BlockBlob',
      'x-ms-blob-content-disposition': 'inline',
    };
    headers?.forEach((key, value) {
      requestHeaders['x-ms-meta-$key'] = value;
    });

    dynamic requestBody;
    if (type == BlobType.blockBlob) {
      if (bodyBytes != null) {
        requestBody = bodyBytes;
      } else if (body != null) {
        requestBody = body;
      }
    } else {
      requestBody = '';
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
    if (response.statusCode == 201) {
      if (type == BlobType.appendBlob && (body != null || bodyBytes != null)) {
        await appendBlock(
          fileName,
          part: 0,
          body: body,
          bodyBytes: bodyBytes,
          headers: appendHeaders,
          fileSize: _fileSize,
        );
      }
      return;
    }

    final String message = response.data ?? '';
    throw AzureStorageException(
      message,
      response.statusCode ?? 0,
      response.headers.map,
    );
  }

  ///
  /// GetBlobMeta
  ///
  /// `body` and `bodyBytes` are exclusive and mandatory.
  Future<Map<String, String>> getBlobMetaData(
    String fileName, {
    Map<String, String>? headers,
  }) async {
    final Map<String, dynamic> requestHeaders = {};
    headers?.forEach((key, value) {
      requestHeaders['x-ms-meta-$key'] = value;
    });

    final Response<String> response = await _dio.headUri(
      _uri(fileName: fileName),
      options: Options(
        contentType: "plain/text",
        headers: headers,
      ),
    );
    if (response.statusCode == 200) {
      return response.headers.map.map(
        (key, value) => MapEntry(key, value.join(',')),
      );
    }

    final String message = response.data ?? '';
    throw AzureStorageException(
      message,
      response.statusCode ?? 0,
      response.headers.map,
    );
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
    _fileSize = fileSize;
    debugPrint("Filesize: $fileSize");
    debugPrint("part: $part");

    dynamic requestBody = bodyBytes ?? body;

    final Response<String> response = await _dio.putUri(
      _uri(fileName: fileName, queryParameters: {'comp': 'appendblock'}),
      data: requestBody,
      options: Options(
        contentType: contentType,
        headers: headers,
      ),
      onSendProgress: (count, total) => _updateProgressSubj(part, count),
    );

    if (response.statusCode == 201) return;

    final String message = response.data ?? '';
    throw AzureStorageException(
      message,
      response.statusCode ?? 0,
      response.headers.map,
    );
  }
}
