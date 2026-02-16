import 'dart:async';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? cameraController;

  CameraController get controller => cameraController!;

  Object? cameraError;

  @override
  void initState() {
    initCamera();
    super.initState();
  }

  @override
  void dispose() {
    cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: Builder(
                  builder: (context) {
                    if (cameraError != null) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text('Camera error', style: Theme.of(context).textTheme.titleMedium),
                            SizedBox(height: 12),
                            Text('$cameraError', style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
                          ],
                        ),
                      );
                    }

                    if (cameraController?.value.isInitialized == true) {
                      return CameraPreview(
                        controller,
                        child: Align(
                          alignment: Alignment.bottomLeft,
                          child: ListenableBuilder(
                            listenable: controller,
                            builder: (context, _) {
                              var size = controller.value.previewSize ?? Size.zero;
                              return Text(
                                'W/H [${size.width}:${size.height}]',
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white),
                              );
                            },
                          ),
                        ),
                      );
                    }

                    return Center(child: CircularProgressIndicator());
                  },
                ),
              ),
              if (cameraController?.value.isInitialized == true)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 64,
                  child: Center(
                    child: IconButton(
                      onPressed: takePicture,
                      icon: Icon(Icons.camera, color: Colors.white, size: 64),
                    ),
                  ),
                ),
              Positioned(
                top: 8,
                left: 8,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        cameraError = 'No cameras available on device';
        return;
      }

      final camera = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cameras.first);
      cameraController = CameraController(camera, ResolutionPreset.medium, enableAudio: false, fps: 30);
      await controller.initialize();
    } catch (ex) {
      cameraError = '$ex';
    } finally {
      setState(() {});
    }
  }

  Future<void> takePicture() async {
    try {
      var xfile = await controller.takePicture();
      var bytes = await xfile.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;

      final int width = image.width;
      final int height = image.height;

      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final Uint8List rgba = byteData!.buffer.asUint8List();


      YuvImage yuv = YuvImage.bgra(width, height);
      yuv.fromRgba8888(rgba);

      if (controller.description.lensDirection == CameraLensDirection.front && _isAndroid) {
        yuv = yuv.copy().flipHorizontally();
      }

      await Future.delayed(Duration(seconds: 1));
      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(yuv);
    } catch (ex, stack) {
      print(ex);
      print(stack);
      //skip error
    }
  }
}

bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
