import 'dart:async';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// Azure Storage Exception
class AzureStorageException implements Exception {
  final String message;
  final int statusCode;
  final Map<String, String> headers;
  AzureStorageException(this.message, this.statusCode, this.headers);
}

/// Blob type
enum BlobType {
  BlockBlob,
  AppendBlob,
}

class AzureStorage {

  late Map<String, String> _config;

  static const String QueryPath = 'QueryPath';
  static const String QueryParams = 'QueryParams';

  AzureStorage.parseSasLink(String sasLink) {
    try {
      var m = <String, String>{};
      var urlSplitted = sasLink.split('?');
      m[QueryPath] = urlSplitted[0];
      m[QueryParams] = urlSplitted[1];
      _config = m;
    } catch (e) {
      throw Exception('Parse error.');
    }
  }

  @override
  String toString() {
    return _config.toString();
  }

  Uri _uri({String fileName = '/', Map<String, String>? queryParameters}) {
    var queryPath = _config[QueryPath];
    var queryParams = _config[QueryParams];
    var url = '$queryPath/$fileName?$queryParams';

    if(queryParameters != null) {
      List<String> list = List.empty(growable: true);
      queryParameters.forEach((k, v) => list.add('$k=$v'));
      url = '$url&${list.join('&')}';
    }

    return Uri.parse(url);
  }

  /// Put Blob.
  ///
  /// `body` and `bodyBytes` are exclusive and mandatory.
  Future<void> putBlob(String fileName,
      {String? body,
        Uint8List? bodyBytes,
        String? contentType,
        BlobType type = BlobType.BlockBlob,
        Map<String, String>? headers}) async {
    var request = http.Request('PUT', _uri(fileName: fileName));
    request.headers['x-ms-blob-type'] =
    type.toString() == 'BlobType.AppendBlob' ? 'AppendBlob' : 'BlockBlob';
    request.headers['x-ms-blob-content-disposition'] = 'inline';
    if (headers != null) {
      headers.forEach((key, value) {
        request.headers['x-ms-meta-$key'] = value;
      });
    }
    if (contentType != null) request.headers['content-type'] = contentType;
    if (type == BlobType.BlockBlob) {
      if (bodyBytes != null) {
        request.bodyBytes = bodyBytes;
      } else if (body != null) {
        request.body = body;
      }
    } else {
      request.body = '';
    }
    var res = await request.send();
    if (res.statusCode == 201) {
      await res.stream.drain();
      if (type == BlobType.AppendBlob && (body != null || bodyBytes != null)) {
        await appendBlock(fileName, body: body, bodyBytes: bodyBytes);
      }
      return;
    }

    var message = await res.stream.bytesToString();
    throw AzureStorageException(message, res.statusCode, res.headers);
  }

  /// Append block to blob.
  Future<void> appendBlock(String fileName,
      {String? body, Uint8List? bodyBytes}) async {
    var request = http.Request(
        'PUT', _uri(fileName: fileName, queryParameters: {'comp': 'appendblock'}));
    if (bodyBytes != null) {
      request.bodyBytes = bodyBytes;
    } else if (body != null) {
      request.body = body;
    }
    var res = await request.send();
    if (res.statusCode == 201) {
      await res.stream.drain();
      return;
    }

    var message = await res.stream.bytesToString();
    throw AzureStorageException(message, res.statusCode, res.headers);
  }
}
