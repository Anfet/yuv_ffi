import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_ffi_example/camera_screen.dart';
import 'package:yuv_ffi_example/widgets/crop_targets.dart';
import 'package:yuv_ffi_example/widgets/face_rect_paint.dart';
import 'package:yuv_ffi_example/widgets/shades.dart';

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
  Rect? faceBox;

  @override
  void initState() {
    verifyExisting();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Builder(
        builder: (context) {
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
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: Column(
                    mainAxisSize: MainAxisSize.max,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: image != null ? _ImageWidget(image: image, faceBox: faceBox) : Container(color: Colors.black),
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
                              onPressed: () => flitImageHorizontally(),
                              icon: Icon(MdiIcons.flipHorizontal, size: 32),
                              tooltip: 'Flip horizontally',
                            ),
                            IconButton(onPressed: () => cropImage(), icon: Icon(Icons.crop, size: 32), tooltip: 'crop image'),
                            IconButton(onPressed: () => grayscaleImage(), icon: Icon(CupertinoIcons.color_filter, size: 32), tooltip: 'Grayscale'),
                            IconButton(
                              onPressed: () => blackwhiteImage(),
                              icon: Icon(MdiIcons.imageFilterBlackWhite, size: 32),
                              tooltip: 'Black&White',
                            ),
                            IconButton(onPressed: () => invertImage(), icon: Icon(MdiIcons.invertColors, size: 32), tooltip: 'Negate'),
                            IconButton(onPressed: () => gaussianBlurImage(), icon: Icon(MdiIcons.blur, size: 32), tooltip: 'Gaussian blur'),
                            IconButton(onPressed: () => meanBlurImage(), icon: Icon(MdiIcons.blurLinear, size: 32), tooltip: 'Mean blur'),
                            IconButton(onPressed: () => boxBlurImage(), icon: Icon(MdiIcons.box, size: 32), tooltip: 'Box blur'),
                            IconButton(onPressed: () => doFaceDetection(), icon: Icon(MdiIcons.faceManOutline, size: 32), tooltip: 'Face detection'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (lastOpTiming != null)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Text('${lastOpTiming} msec', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white)),
                  ),
              ],
            ),
          );
        },
      ),
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

    var json = flipHorizontally(image).toJson();
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
      faceBox = null;
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
    var cropTarget = CropTarget.percented(top: .15, bottom: .75, left: .15, right: .85);
    var r = cropTarget.place(image!.size);

    logTimed(() => image = crop(image!, r), name: '$image cropImage');
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
    logTimed(() => image = boxBlur(image!, radius: 10), name: '$image boxBlurImage');
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
    var image = Yuv420Image.fromRGBA(rgbaBuffer, img.width, img.height);
    var json = image.toJson();
    var dir = await getTemporaryDirectory();
    var path = '${dir.path}/image.json';
    var file = File(path);
    await file.writeAsString(json);
    imageExists = true;
    loadExisting();
  }

  Future doFaceDetection() async {
    final FaceDetector detector = FaceDetector(
      options: FaceDetectorOptions(enableClassification: true, performanceMode: FaceDetectorMode.accurate, enableTracking: true),
    );

    final rotation = InputImageRotation.rotation0deg;
    final image = this.image!.toNv21();

    final meta = InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: InputImageFormat.nv21,
      bytesPerRow: image.planes.first.bytesPerRow,
    );

    var inputImage = InputImage.fromBytes(bytes: image.getBytes(), metadata: meta);
    final faces = await detector.processImage(inputImage);
    if (faces.isEmpty) {
      faceBox = null;
    } else {
      faces.sort((a, b) => b.boundingBox.area.compareTo(a.boundingBox.area));
      final face = faces.first;
      faceBox = face.boundingBox;
    }

    setState(() {});
  }
}

class _ImageWidget extends StatelessWidget {
  final YuvImage? image;
  final ui.Rect? faceBox;

  const _ImageWidget({super.key, required this.image, required this.faceBox});

  @override
  Widget build(BuildContext context) {
    if (image == null) {
      return ColoredBox(color: Colors.black);
    }

    final i = image!;

    return ColoredBox(
      color: Colors.black,
      child: FittedBox(
        fit: BoxFit.cover,
        alignment: Alignment.center,
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: i.width.toDouble(),
          height: i.height.toDouble(),
          child: Stack(
            clipBehavior: Clip.antiAlias,
            fit: StackFit.expand,
            children: [
              YuvImageWidget(image: i),
              ShadeWidget.oval(target: CropTarget.percented(top: .15, bottom: .75, left: .15, right: .85)),
              if (faceBox != null)
                CustomPaint(
                  painter: FaceRectPainter(rect: faceBox!, image: i),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

extension on Rect {
  double get area => width * height;
}
