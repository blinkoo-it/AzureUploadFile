/// Azure Storage Exception
class AzureStorageException implements Exception {
  final String message;
  final int statusCode;
  final Map<String, dynamic> headers;
  AzureStorageException(this.message, this.statusCode, this.headers);
}
