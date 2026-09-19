import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
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
  bool get _isDesktopWithoutCameraPlugin =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.linux);
  bool get _isPreviewReady => _isDesktopWithoutCameraPlugin || cameraController?.value.isInitialized == true;

  Object? cameraError;
  Completer<YuvImage?>? captureCompleter;

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
                            Text('Camera error', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white)),
                            SizedBox(height: 12),
                            SelectableText('$cameraError',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white), textAlign: TextAlign.center),
                          ],
                        ),
                      );
                    }

                    if (_isPreviewReady) {
                      return YuvCameraPreview(
                        cameraController: _isDesktopWithoutCameraPlugin ? null : controller,
                        showDebugInfo: true,
                        transform: imageCapturer,
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
      if (_isDesktopWithoutCameraPlugin) {
        return;
      }

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
      captureCompleter!.complete(image);
    }

    return image;
  }
}
