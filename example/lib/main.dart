import 'dart:async';

import 'package:azure_upload_file/azure_upload_file.dart';
import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/adapters.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // Try running your application with "flutter run". You'll see the
        // application has a blue toolbar. Then, without quitting the app, try
        // changing the primarySwatch below to Colors.green and then invoke
        // "hot reload" (press "r" in the console where you ran "flutter run",
        // or simply save your changes to "hot reload" in a Flutter IDE).
        // Notice that the counter didn't reset back to zero; the application
        // is not restarted.
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String _counter = "0";
  String? pathImage;

  final AzureUploadFile azureStorage = AzureUploadFile();
  StreamSubscription<AzureProgressMessage>? streamSubscription;

  void _addFile() async {
    streamSubscription?.cancel();
    final FilePickerResult? pickerResult = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowCompression: false,
    );
    final path = pickerResult?.files.first.path;
    final XFile video = XFile(path!);

    await Hive.initFlutter();

    await azureStorage.config();
    azureStorage.initWithSasLink(
      "https://amsstoragestage.blob.core.windows.net/temp-cbde9b4e-4a15-450d-9bb1-408b62ea5574?sv=2022-11-02&se=2024-08-02T01%3A20%3A43Z&sr=c&sp=rw&sig=C90AR60Ty9Vl5vN14MWz6A8CsWFNTkKe3DSVUquFtSo%3D",
    );
    //await azureBlob.putBlob('video.mp4', bodyBytes: await video.readAsBytes(), contentType: 'video/mp4');
    streamSubscription = (await azureStorage.uploadFile(video)).listen(
      (event) {
        setState(() {
          _counter = (event.progress * 100).toInt().toString();
        });
        debugPrint("Your upload progress: $_counter%");
      },
      onError: (e) {
        debugPrint("$e");
      },
      onDone: () {
        debugPrint("Completed");
      },
      cancelOnError: true,
    );
  }

  void resumeUpload() {
    azureStorage.resumeUploadFile();
  }

  void cancelVideo() async {
    azureStorage.pauseUploadFile();
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Invoke "debug painting" (press "p" in the console, choose the
          // "Toggle Debug Paint" action from the Flutter Inspector in Android
          // Studio, or the "Toggle Debug Paint" command in Visual Studio Code)
          // to see the wireframe for each widget.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            //Image.file(File(pathImage!)),
            Text(
              'Your upload progress: $_counter%',
            ),
            TextButton(
                onPressed: resumeUpload,
                child: const Text(
                  'Resume',
                )),

            TextButton(
                onPressed: cancelVideo,
                child: const Text(
                  'Cancel',
                )),
            // TextButton(onPressed: getVideoMeta, child: const Text(
            //   'GET VIDEO META',
            // ))
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addFile,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}
