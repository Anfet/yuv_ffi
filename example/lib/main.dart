import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_ffi_example/camera_screen.dart';
import 'package:yuv_ffi_example/ext.dart';
import 'package:yuv_ffi_example/widgets/crop_targets.dart';
import 'package:yuv_ffi_example/widgets/face_rect_paint.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Optional<YuvImage> image = Optional.absent();

  YuvImage get requireImage => image.value;
  bool isLoading = false;
  bool isSaving = false;

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
                IconButton(onPressed: isSaving ? null : () => takePhoto(context), icon: Icon(Icons.camera), tooltip: 'Take photo'),
                IconButton(onPressed: isSaving ? null : () => loadExisting(), icon: Icon(Icons.file_upload_outlined), tooltip: 'Load existing'),
                IconButton(onPressed: isSaving ? null : () => loadImage(), icon: Icon(Icons.drive_folder_upload), tooltip: 'Load image'),
              ],
            ),
            body: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(child: ColoredBox(color: Colors.black)),
                Positioned.fill(
                  child: Column(
                    mainAxisSize: MainAxisSize.max,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _ImageWidget(image: image.orNull, faceBox: faceBox),
                      ),
                      Container(
                        color: Colors.white,
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
                            IconButton(onPressed: () => toI420(), icon: Text('To i420', style: TextStyle(fontSize: 12)), tooltip: 'To i420'),
                            IconButton(onPressed: () => toNV21(), icon: Text('To Nv21', style: TextStyle(fontSize: 12)), tooltip: 'To NV21'),
                            IconButton(onPressed: () => toBGRA(), icon: Text('To BGRA', style: TextStyle(fontSize: 12)), tooltip: 'To BGRA8888'),
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
                    child: Text('$lastOpTiming msec', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white)),
                  ),
                if (image.isNotEmpty)
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Text('${image.value}', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white)),
                  ),
                if (isSaving)
                  Positioned(
                    left: 8,
                    top: 8,
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(),
                  ),
                if (isLoading)
                  Center(
                    child: CircularProgressIndicator(),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future takePhoto(BuildContext context) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) {
          return CameraScreen();
        },
        settings: RouteSettings(name: 'camera'),
      ),
    );

    if (result is! YuvImage) {
      return;
    }

    await Future.delayed(Duration(seconds: 1));

    setState(() {
      image = Optional.of(result);
      faceBox = null;
      isSaving = true;
    });

    var dir = await getTemporaryDirectory();
    var path = '${dir.path}/image.yuv';
    var file = File(path);

    var sink = file.openWrite();
    await image.value.save(sink);
    await sink.flush();
    await sink.close();

    setState(() {
      isLoading = false;
      isSaving = false;
    });
  }

  Future verifyExisting() async {
    var dir = await getTemporaryDirectory();
    var path = '${dir.path}/image.yuv';
    var file = File(path);
    imageExists = file.existsSync();
  }

  Future loadExisting() async {
    logTimed(() async {
      var dir = await getTemporaryDirectory();
      var definitionFile = '${dir.path}/image.yuv';
      var file = File(definitionFile);
      if (!file.existsSync()) {
        return;
      }

      setState(() {
        isLoading = true;
        isSaving = false;
      });

      YuvImage result = YuvImage.bgra(1, 1);
      await result.load(file.openRead());

      setState(() {
        isLoading = false;
        image = Optional.of(result);

        // image = image!.toYuvI420();
        // image = image!.toYuvNv21();

        faceBox = null;
      });
    }, name: 'loadExisting');
  }

  void rotateClockWise() {
    logTimed(() => requireImage.rotate(YuvImageRotation.rotation90), name: '$image rotateClockWise');
  }

  void rotateCouterClockwise() {
    logTimed(() => requireImage.rotate(YuvImageRotation.rotation270), name: '$image rotateCouterClockwise');
  }

  Future flipImageVertically() async {
    logTimed(() async => requireImage.flipVertically(), name: '$image flipVertically');
  }

  void flitImageHorizontally() {
    logTimed(() => requireImage.flipHorizontally(), name: '$image flitHorizontally');
  }

  void cropImage() {
    var cropTarget = CropTarget.percented(top: .15, bottom: .75, left: .15, right: .85);
    var r = cropTarget.place(requireImage.size);

    logTimed(() => requireImage.crop(r), name: '$image cropImage');
  }

  void grayscaleImage() {
    logTimed(() => requireImage.grayscale(), name: '$image grayscaleImage');
  }

  void blackwhiteImage() {
    logTimed(() => requireImage.blackwhite(), name: '$image blackwhiteImage');
  }

  void invertImage() {
    logTimed(() => requireImage.negate(), name: '$image invertImage');
  }

  void gaussianBlurImage() {
    logTimed(() => requireImage.gaussianBlur(radius: 10, sigma: 10), name: '$image gaussianBlurImage');
  }

  void meanBlurImage() {
    logTimed(() => requireImage.meanBlur(radius: 10), name: '$image meanBlurImage');
  }

  Future logTimed(FutureOr Function() execution, {String? name}) async {
    var t = DateTime.now();
    await execution();
    var d = t.difference(DateTime.now()).abs().inMilliseconds;
    lastOpTiming = d;
    debugPrint('${name ?? ''} > $d msec');
    setState(() {});
  }

  void boxBlurImage() {
    logTimed(() => requireImage.boxBlur(radius: 10), name: '$image boxBlurImage');
  }

  Future loadImage() async {
    final xfile = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (xfile == null) {
      return;
    }
    setState(() {
      isLoading = true;
    });

    Uint8List? bytes = await xfile.readAsBytes();
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    final ui.Image img = frame.image;

    ByteData? rgbaBytes = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    bytes = null;
    img.dispose();

    if (rgbaBytes == null) throw Exception('Could not decode image');
    setState(() {
      image = Optional.of(YuvImage.bgra(img.width, img.height)..fromRgba8888(rgbaBytes!.buffer.asUint8List()));
      faceBox = null;
      imageExists = false;
      isLoading = false;
      isSaving = true;
    });

    // if (image!.height > 1024 && image!.width > 1024) {
    //   setState(() {
    //     if (kDebugMode) {
    //       print('Warning; Image is too large to save');
    //     }
    //   });
    //
    //   return;
    // }
    rgbaBytes = null;
    var dir = await getTemporaryDirectory();
    var file = File('${dir.path}/image.yuv');
    var sink = file.openWrite();
    image.value.save(sink);
    await sink.flush();
    await sink.close();

    setState(() {
      imageExists = true;
      isSaving = false;
    });
  }

  Future doFaceDetection() async {
    final FaceDetector detector = FaceDetector(
      options: FaceDetectorOptions(enableClassification: true, performanceMode: FaceDetectorMode.accurate, enableTracking: true),
    );

    var inputImage = (Platform.isIOS ? requireImage.toYuvBgra8888() : requireImage.toYuvNv21()).toInputImage();

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

  Future toI420() async {
    logTimed(() => image = Optional.of(requireImage.toYuvI420()), name: '$image toI420');
  }

  Future toNV21() async {
    logTimed(() => image = Optional.of(requireImage.toYuvNv21()), name: '$image toNV21');
  }

  Future toBGRA() async {
    logTimed(() => image = Optional.of(requireImage.toYuvBgra8888()), name: '$image toBGRA');
  }
}

class _ImageWidget extends StatelessWidget {
  final YuvImage? image;
  final ui.Rect? faceBox;

  const _ImageWidget({required this.image, required this.faceBox});

  @override
  Widget build(BuildContext context) {
    if (image == null) {
      return SizedBox();
    }

    final i = image!;

    return FittedBox(
      fit: BoxFit.contain,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: i.width.toDouble(),
        height: i.height.toDouble(),
        child: Stack(
          clipBehavior: Clip.antiAlias,
          fit: StackFit.expand,
          children: [
            YuvImageWidget(image: i, boxFit: BoxFit.none),
            if (faceBox != null)
              CustomPaint(
                painter: FaceRectPainter(rect: faceBox!, image: i, strokeWidth: 10),
              ),
          ],
        ),
      ),
    );
  }
}

extension on Rect {
  double get area => width * height;
}
