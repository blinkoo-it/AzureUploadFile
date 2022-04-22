# AzureUploadFile

A Flutter package to upload file on azure with sas link.

## Usage

A simple usage example:

```dart
import 'package:azure_upload_file/azure_upload_file.dart';

main() async {
  final file = XFile('assets/hello.txt');
  var storage = AzureUploadFile();
  await storage.config();
  storage.initWithSasLink('your sas link');
  storage
      .uploadFile(file)
      .listen(
        (progress) => print('Your upload progress $progress'),
        onError: (error, stackTrace) {},
        onComplete: () => print('Completed')
  );
}
```

There is the possibility to pause and resume upload

```dart
main() async {
  await storage.pauseUpload();
  storage
      .resumeUploadFile()
      .listen(
          (progress) => print('Your upload progress $progress'),
          onError: (error, stackTrace) {},
          onComplete: () => print('Completed')
  );
}
```

the ability to check if there is an upload in pause

```dart
main() async {
  if(storage.isPresentUploadToResume()) {
    //Insert code here
  }
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
