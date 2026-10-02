import 'dart:async';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_ffi_example/camera/camera_image_import.dart';
import 'package:yuv_ffi_example/camera/yuv_camera_frame.dart';
import 'package:yuv_ffi_example/camera/yuv_camera_frame_source.dart';

final class YuvCameraFrameSourceImpl implements YuvCameraFrameSource {
  YuvCameraFrameSourceImpl(this.controller, {required this.onFrame, required this.onError});

  final CameraController controller;
  final void Function(YuvCameraFrame frame) onFrame;
  final void Function(Object error) onError;
  final Stopwatch _clock = Stopwatch();
  StreamSubscription<CameraImageData>? _subscription;
  int _generation = 0;
  bool _disposed = false;

  @override
  Future<void> start() async {
    final generation = _generation;
    if (_disposed || !controller.value.isInitialized) return;
    _clock
      ..reset()
      ..start();
    _subscription = CameraPlatform.instance
        .onStreamedFrameAvailable(controller.cameraId)
        .listen(
          (data) {
            if (_disposed || generation != _generation) return;
            final image = CameraImage.fromPlatformInterface(data);
            final format = image.format.group == ImageFormatGroup.bgra8888 ? YuvPixelFormat.bgra8888 : YuvPixelFormat.i420;
            onFrame(
              YuvCameraFrame(
                width: image.width,
                height: image.height,
                format: format,
                orientation: YuvFrameOrientation.upright,
                timestamp: _clock.elapsed,
                load: () => importCameraImage(image),
              ),
            );
          },
          onError: (Object error) {
            if (!_disposed && generation == _generation) {
              stop();
              onError(error);
            }
          },
        );
  }

  @override
  void stop() {
    _generation++;
    _clock.stop();
    _subscription?.cancel();
    _subscription = null;
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
  }
}
