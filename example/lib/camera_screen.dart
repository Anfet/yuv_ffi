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

  // A copy of the frame the preview is about to show while a capture waits.
  // It becomes the capture only once the preview reports it drawn.
  YuvImage? captureCandidate;

  @override
  void initState() {
    initCamera();
    super.initState();
  }

  @override
  void dispose() {
    // The preview is gone and no frame will arrive; a capture still waiting
    // would otherwise never complete.
    cancelCapture();
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
                      return YuvCameraPreview(
                        flipAndroidCameraHorizontally: true,
                        cameraController: controller,
                        showDebugInfo: true,
                        transform: imageCapturer,
                        onFramePresented: confirmCapture,
                        onStreamStopped: cancelCapture,
                      );
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
    if (captureCompleter?.isCompleted == false) {
      // Not completed here: the frame may still be dropped before it is drawn
      // (stream stopped, decode failed). A candidate of a dropped frame is
      // replaced by the next one. Copied because the web preview writes every
      // next frame into the same instance.
      captureCandidate = image.copy();
    }

    return image;
  }

  // The frame from the latest imageCapturer call is on screen now.
  void confirmCapture() {
    final candidate = captureCandidate;
    final capture = captureCompleter;
    captureCandidate = null;
    if (candidate != null && capture != null && !capture.isCompleted) {
      capture.complete(candidate);
    }
  }

  // The stream stopped or the screen closed before a candidate was drawn:
  // the capture ends without a frame rather than returning one never shown.
  void cancelCapture() {
    captureCandidate = null;
    final capture = captureCompleter;
    if (capture != null && !capture.isCompleted) {
      capture.complete(null);
    }
  }
}
