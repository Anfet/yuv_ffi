import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:async';

import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_ffi_example/camera_screen.dart';

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
  int? lastOpTiming;

  @override
  void initState() {
    verifyExisting();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Builder(builder: (context) {
        return Scaffold(
          appBar: AppBar(
            forceMaterialTransparency: true,
            title: const Text('YUV FFI'),
            actions: [
              IconButton(onPressed: () => takePhoto(context), icon: Icon(Icons.camera), tooltip: 'Take photo'),
              IconButton(onPressed: () => loadExisting(), icon: Icon(Icons.file_upload_outlined), tooltip: 'Load existing'),
              IconButton(onPressed: () => loadImage(), icon: Icon(Icons.drive_folder_upload), tooltip: 'Load image'),
            ],
          ),
          body: Stack(
            children: [
              Positioned.fill(
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: image != null
                          ? SingleChildScrollView(
                              child: AspectRatio(
                                aspectRatio: image == null ? 1.0 : image!.width / image!.height,
                                child: YuvImageWidget(image: image!),
                              ),
                            )
                          : Container(color: Colors.black),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 12),
                      child: Wrap(
                        spacing: 12,
                        children: [
                          IconButton(onPressed: () => rotateClockWise(), icon: Icon(Icons.rotate_right, size: 32), tooltip: 'Rotate Clockwise'),
                          IconButton(
                            onPressed: () => rotateCouterClockwise(),
                            icon: Icon(Icons.rotate_left, size: 32),
                            tooltip: 'Rotate Couterclockwise',
                          ),
                          IconButton(
                            onPressed: () => flipImageVertically(),
                            icon: Icon(MdiIcons.flipVertical, size: 32),
                            tooltip: 'Flip vertically',
                          ),
                          IconButton(
                              onPressed: () => flitImageHorizontally(), icon: Icon(MdiIcons.flipHorizontal, size: 32), tooltip: 'Flip horizontally'),
                          IconButton(onPressed: () => cropImage(), icon: Icon(Icons.crop, size: 32), tooltip: 'crop image'),
                          IconButton(onPressed: () => grayscaleImage(), icon: Icon(CupertinoIcons.color_filter, size: 32), tooltip: 'Grayscale'),
                          IconButton(
                            onPressed: () => blackwhiteImage(),
                            icon: Icon(MdiIcons.imageFilterBlackWhite, size: 32),
                            tooltip: 'Black&White',
                          ),
                          IconButton(
                            onPressed: () => invertImage(),
                            icon: Icon(MdiIcons.invertColors, size: 32),
                            tooltip: 'Negate',
                          ),
                          IconButton(onPressed: () => gaussianBlurImage(), icon: Icon(MdiIcons.blur, size: 32), tooltip: 'Gaussian blur'),
                          IconButton(onPressed: () => meanBlurImage(), icon: Icon(MdiIcons.blurLinear, size: 32), tooltip: 'Mean blur'),
                          IconButton(onPressed: () => boxBlurImage(), icon: Icon(MdiIcons.blurOff, size: 32), tooltip: 'Box blur'),
                        ],
                      ),
                    )
                  ],
                ),
              ),
              if (lastOpTiming != null)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Text('${lastOpTiming} msec', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white)),
                )
            ],
          ),
        );
      }),
    );
  }

  Future takePhoto(BuildContext context) async {
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
  }

  Future loadExisting() async {
    logTimed(() async {
      var dir = await getTemporaryDirectory();
      var path = '${dir.path}/image.json';
      var file = File(path);
      if (!file.existsSync()) {
        return;
      }

      var json = await file.readAsString();
      image = YuvImage.fromJson(jsonDecode(json));
      setState(() {});
    }, name: 'loadExisting');
  }

  void rotateClockWise() {
    logTimed(() => image = rotate(image!, YuvImageRotation.rotation90), name: '$image rotateClockWise');
  }

  void rotateCouterClockwise() {
    logTimed(() => image = rotate(image!, YuvImageRotation.rotation270), name: '$image rotateCouterClockwise');
  }

  Future flipImageVertically() async {
    logTimed(() async => image = await flipVertically(image!), name: '$image flipVertically');
  }

  void flitImageHorizontally() {
    logTimed(() => image = flipHorizontally(image!), name: '$image flitHorizontally');
  }

  void cropImage() {
    logTimed(
        () => image =
            crop(image!, Rect.fromCenter(center: Offset(image!.width / 2, image!.height / 2), width: image!.width / 2, height: image!.height / 2)),
        name: '$image cropImage');
  }

  void grayscaleImage() {
    logTimed(() => image = grayscale(image!), name: '$image grayscaleImage');
  }

  void blackwhiteImage() {
    logTimed(() => image = blackwhite(image!), name: '$image blackwhiteImage');
  }

  void invertImage() {
    logTimed(() => image = negate(image!), name: '$image invertImage');
  }

  void gaussianBlurImage() {
    logTimed(() => image = gaussianBlur(image!, radius: 10, sigma: 10), name: '$image gaussianBlurImage');
  }

  void meanBlurImage() {
    logTimed(() => image = meanBlur(image!, radius: 10), name: '$image meanBlurImage');
  }

  Future logTimed(FutureOr Function() execution, {String? name}) async {
    var t = DateTime.now();
    await execution();
    var d = t.difference(DateTime.now()).abs().inMilliseconds;
    lastOpTiming = d;
    print('${name ?? ''} > $d msec');
    setState(() {});
  }

  void boxBlurImage() {
    logTimed(() => image = boxBlur(image!, radius: 5), name: '$image boxBlurImage');
  }

  Future loadImage() async {
    final xfile = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (xfile == null) {
      return;
    }

    final byteData = await xfile.readAsBytes();
    final bytes = byteData.buffer.asUint8List();

    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    final ui.Image img = frame.image;

    final rgbaBytes = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (rgbaBytes == null) throw Exception('Could not decode image');

    var rgbaBuffer = rgbaBytes.buffer.asUint8List();
    var image = YuvImage.fromRGBA(rgbaBuffer, img.width, img.height);
    var json = image.toJson();
    var dir = await getTemporaryDirectory();
    var path = '${dir.path}/image.json';
    var file = File(path);
    await file.writeAsString(json);
    imageExists = true;
    loadExisting();
  }
}
