import 'dart:async';

import 'package:azure_upload_file/azure_upload_file.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/adapters.dart';
import 'package:image_picker/image_picker.dart';

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

  final ImagePicker _picker = ImagePicker();
  late AzureUploadFile azureStorage;
  StreamSubscription<double>? streamSubscription;

  void _addFile() async {
    streamSubscription?.cancel();
    final XFile? video = await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 2),
    );
    debugPrint(video!.path);
    await Hive.initFlutter();

    azureStorage = AzureUploadFile();
    await azureStorage.config();
    azureStorage.initWithSasLink(
        "https://amsstoragestage.blob.core.windows.net/temp-b90a09d7-8ff4-4484-91d0-2a6871411850?sv=2022-11-02&se=2024-07-31T02%3A21%3A50Z&sr=c&sp=rw&sig=VU7K8DDIG5gmybwN624yQbBXAWf9CIPSm020JDZZ9x0%3D");
    //await azureBlob.putBlob('video.mp4', bodyBytes: await video.readAsBytes(), contentType: 'video/mp4');
    streamSubscription = azureStorage.uploadFile(video).listen((event) {
      setState(() {
        _counter = (event * 100).toInt().toString();
      });
      debugPrint("Your upload progress: $_counter%");
    }, onError: (e, st) {
      debugPrint(e);
      debugPrint(st);
    }, onDone: () {
      debugPrint("Completed");
    }, cancelOnError: true);
  }

  void resumeUpload() async {
    streamSubscription?.cancel();
    streamSubscription = azureStorage.resumeUploadFile().listen((event) {
      setState(() {
        _counter = (event * 100).toInt().toString();
      });
      // debugPrint("Your upload progress: ${event * 100}%");
    }, onError: (e) {
      debugPrint(e.toString());
    }, onDone: () {
      debugPrint("Completed");
    }, cancelOnError: true);
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
