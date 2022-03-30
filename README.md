# AzureUploadFile

A Flutter package to upload file on azure with sas link.

## Usage

A simple usage example:

```dart
import 'package:azure_upload_file/azure_upload_file.dart';

main() async {
  final file = XFile('assets/hello.txt');
  var storage = AzureUploadFile.initWithSasLink('your sas link');
  storage
      .uploadFile(file)
      .listen(
        (progress) => print('Your upload progress $progress'),
        onError: (error, stackTrace) {},
        onComplete: () => print('Completed')
  );
}
```

There is the possibility to resume upload

```dart
main() async {
  storage.resumeUploadFile();
}
```

And the possibility to stop it

```dart
main() async {
  storage.stopUpload();
}
```


## License

blinkoo
