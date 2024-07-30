import 'dart:async';
import 'dart:typed_data';

import 'package:azure_upload_file/src/azure_storage_exception.dart';
import 'package:dio/dio.dart';

/// Blob type
enum BlobType {
  blockBlob,
  appendBlob,
}

class AzureStorage {
  late Map<String, String> _config;
  final Dio _dio = Dio();

  static const String queryPathKey = 'QueryPath';
  static const String queryParamsKey = 'QueryParams';

  AzureStorage.parseSasLink(String sasLink) {
    try {
      final Map<String, String> m = {};
      final List<String> urlSplitted = sasLink.split('?');
      m[queryPathKey] = urlSplitted[0];
      m[queryParamsKey] = urlSplitted[1];
      _config = m;
    } catch (e) {
      throw Exception('Parse error.');
    }
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
  }) async {
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
    );
    if (response.statusCode == 201) {
      if (type == BlobType.appendBlob && (body != null || bodyBytes != null)) {
        await appendBlock(
          fileName,
          body: body,
          bodyBytes: bodyBytes,
          headers: appendHeaders,
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
    String? body,
    Uint8List? bodyBytes,
    Map<String, String>? headers,
    String? contentType,
  }) async {
    dynamic requestBody = bodyBytes ?? body;

    final Response<String> response = await _dio.putUri(
      _uri(fileName: fileName, queryParameters: {'comp': 'appendblock'}),
      data: requestBody,
      options: Options(
        contentType: contentType,
        headers: headers,
      ),
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
