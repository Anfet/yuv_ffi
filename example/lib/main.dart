import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:async';

import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_ffi_example/camera_screen.dart';
import 'package:yuv_ffi_example/yuv_image_widget.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  YuvImage? image;

  bool imageExists = false;

  @override
  void initState() {
    verifyExisting();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Native Packages'),
        ),
        body: Builder(builder: (context) {
          return Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton(onPressed: () => pickImage(context), child: Text('Pick Image')),
                    SizedBox(width: 24),
                    ElevatedButton(onPressed: imageExists ? () => loadExisting() : null, child: Text('Load existing')),
                  ],
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(24),
                    child: AspectRatio(
                      aspectRatio: image == null ? 1.0 : image!.width / image!.height,
                      child: image != null
                          ? YuvImageWidget(image: image!)
                          : Container(
                              width: MediaQuery.of(context).size.width,
                              height: MediaQuery.of(context).size.height,
                              color: Colors.black,
                            ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12),
                  child: Wrap(
                    spacing: 12,
                    children: [
                      IconButton(onPressed: () => rotateClockWise(), icon: Icon(Icons.rotate_right, size: 40)),
                      IconButton(onPressed: () => rotateCouterClockwise(), icon: Icon(Icons.rotate_left, size: 40)),
                      IconButton(onPressed: () => flitVertically(), icon: Icon(MdiIcons.flipVertical, size: 40)),
                      IconButton(onPressed: () => flitHorizontally(), icon: Icon(MdiIcons.flipHorizontal, size: 40)),
                      IconButton(onPressed: () => cropImage(), icon: Icon(Icons.crop, size: 40)),
                      IconButton(onPressed: () => grayscaleImage(), icon: Icon(CupertinoIcons.color_filter, size: 40)),
                      IconButton(onPressed: () => blackwhiteImage(), icon: Icon(MdiIcons.imageFilterBlackWhite, size: 40)),
                      IconButton(onPressed: () => invertImage(), icon: Icon(MdiIcons.invertColors, size: 40)),
                      IconButton(onPressed: () => blurImage(), icon: Icon(MdiIcons.blur, size: 40)),
                      IconButton(onPressed: () => meanBlurImage(), icon: Icon(MdiIcons.blurLinear, size: 40)),
                    ],
                  ),
                )
              ],
            ),
          );
        }),
      ),
    );
  }

  Future pickImage(BuildContext context) async {
    final image = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) {
          return CameraScreen();
        },
        settings: RouteSettings(name: 'camera'),
      ),
    );

    if (image is! YuvImage) {
      return;
    }

    var json = image.toJson();
    var dir = await getTemporaryDirectory();
    var path = '${dir.path}/image.json';
    var file = File(path);
    await file.writeAsString(json);
    imageExists = true;
    loadExisting();
  }

  Future verifyExisting() async {
    var dir = await getTemporaryDirectory();
    var path = '${dir.path}/image.json';
    var file = File(path);
    imageExists = file.existsSync();
    if (imageExists) loadExisting();
  }

  Future loadExisting() async {
    var dir = await getTemporaryDirectory();
    var path = '${dir.path}/image.json';
    var file = File(path);
    if (!file.existsSync()) {
      return;
    }

    var json = await file.readAsString();
    image = YuvImage.fromJson(jsonDecode(json));
    setState(() {});
  }

  void rotateClockWise() {
    logTimed(() => image = rotate(image!, YuvImageRotation.rotation90));
  }

  void rotateCouterClockwise() {
    logTimed(() => image = rotate(image!, YuvImageRotation.rotation270));
  }

  void flitVertically() {
    logTimed(() => image = flipVertically(image!));
  }

  void flitHorizontally() {
    logTimed(() => image = flipHorizontally(image!));
  }

  void cropImage() {
    logTimed(() => image = crop(image!, Rect.fromLTWH(0, 0, 100, 200)));
  }

  void grayscaleImage() {
    logTimed(() => image = grayscale(image!));
  }

  void blackwhiteImage() {

    logTimed(() => image = blackwhite(image!));
  }

  void invertImage() {
    logTimed(() => image = negate(image!));
  }

  void blurImage() {
    logTimed(() => image = gaussianBlur(image!, radius: 10, sigma: 10));
  }

  void meanBlurImage() {
    logTimed(() => image = meanBlur(image!, radius: 10));
  }

  void logTimed(VoidCallback execution) {
    var t = DateTime.now();
    execution();
    var d = t.difference(DateTime.now()).abs().inMilliseconds;
    print('time = $d msec');
    setState(() {});
  }
}
