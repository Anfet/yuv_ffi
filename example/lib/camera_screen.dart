import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_ffi_example/widgets/yuv_camera_preview.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? cameraController;

  CameraController get controller => cameraController!;
  bool get _isPreviewReady => cameraController?.value.isInitialized == true;

  Object? cameraError;
  Completer<YuvImage?>? captureCompleter;

  @override
  void initState() {
    initCamera();
    super.initState();
  }

  @override
  void dispose() {
    // The preview is gone and no frame will arrive; a capture still waiting
    // would otherwise never complete.
    final capture = captureCompleter;
    if (capture != null && !capture.isCompleted) {
      capture.complete(null);
    }
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
                            Text('Camera error', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white)),
                            SizedBox(height: 12),
                            SelectableText(
                              '$cameraError',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      );
                    }

                    if (_isPreviewReady) {
                      return YuvCameraPreview(cameraController: controller, showDebugInfo: true, transform: imageCapturer);
                    }

                    return Center(child: CircularProgressIndicator());
                  },
                ),
              ),
              if (_isPreviewReady)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 64,
                  child: Center(
                    child: IconButton(
                      onPressed: takePicture,
                      icon: Icon(Icons.camera, color: Colors.white, size: 64),
                      tooltip: 'Capture frame',
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
      // Closed during the lookup: dispose ran before a controller existed, so
      // one created now would never be released.
      if (!mounted) {
        return;
      }
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
      // The screen may be closed while the camera is looked up or initialized;
      // dispose has then already released the controller.
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> takePicture() async {
    // A second tap before the frame arrives joins the pending capture; a new
    // completer would leave the first one waiting forever.
    if (captureCompleter?.isCompleted == false) {
      return;
    }

    try {
      Completer<YuvImage?> capturer = captureCompleter = Completer();
      var yuv = await capturer.future;
      if (yuv == null) {
        return;
      }

      await Future.delayed(Duration(milliseconds: 500));
      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(yuv);
    } catch (ex, stack) {
      debugPrint('takePicture error: $ex');
      debugPrint('$stack');
    }
  }

  YuvImage imageCapturer(YuvImage image) {
    if (captureCompleter != null && !captureCompleter!.isCompleted) {
      // The web preview writes every next frame into the same instance, so
      // completing with `image` itself would let the preview overwrite the
      // captured result while takePicture waits and after pop. The returned
      // `image` is the frame the preview shows next.
      captureCompleter!.complete(image.copy());
    }

    return image;
  }
}
