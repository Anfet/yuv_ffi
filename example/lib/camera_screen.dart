import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_ffi_example/ext.dart';
import 'package:yuv_ffi_example/widgets/yuv_camera_widget.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? cameraController;

  CameraController get controller => cameraController!;
  Object? cameraError;
  Completer<YuvImage>? nextFrameCompleter;

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
                      // return CameraPreview(
                      //   controller,
                      // );
                      return YuvCameraWidget(
                        cameraController: controller,
                        transform: (image) {
                          if (nextFrameCompleter != null && nextFrameCompleter?.isCompleted != true) {
                            nextFrameCompleter?.complete(image);
                          }
                          return image;
                        },
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
                      onPressed: () => takePicture(context),
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

      final camera = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cameras.first);
      cameraController = CameraController(camera, ResolutionPreset.medium, enableAudio: false, fps: 60);
      await controller.initialize();
    } catch (ex) {
      cameraError = '$ex';
    } finally {
      setState(() {});
    }
  }

  Future takePicture(BuildContext context) async {
    assert(controller.value.isStreamingImages);
    nextFrameCompleter = Completer();
    try {
      final yuv = await nextFrameCompleter!.future;
      await Future.delayed(Duration(seconds: 1));
      Navigator.of(context).pop(yuv);
    } finally {
      nextFrameCompleter = null;
    }
  }
}
