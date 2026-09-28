import 'dart:convert';
import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_ffi_example/ext.dart';

/// Ad-hoc verification, not a VIEW-03 deliverable. `rotate_vs_flip_pixel3_test.dart`
/// found applyRotation() at ~11-13 ms and applyFlipHorizontal() at ~6 ms on a
/// synthetic 720x480 frame with nothing else running -- an order of
/// magnitude below the ~94 ms this repo's VIEW-03 measurement found for
/// applyRotation() *inside* `_YuvCameraPreviewMobile.onNewImageAvailable`
/// while a real camera stream was active. This file isolates the one
/// remaining difference: a real, live `CameraPlatform.instance.
/// onStreamedFrameAvailable` subscription feeding real camera frames through
/// the exact same `toYuvImage()` -> `applyRotation()` sequence, but with no
/// YuvCameraPreview/YuvFramePresenter/widget tree at all -- so the only two
/// candidate causes left are "real camera frame content/geometry" and
/// "concurrent load while the stream is live", not the presenter or Flutter's
/// build/layout/paint pipeline.
///
/// Run (from `example/`), screen on:
/// ```
/// flutter drive --driver=test_driver/integration_test.dart \
///   --target=integration_test/rotate_under_camera_load_pixel3_test.dart -d 8B1X11QLW --profile
/// ```
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('applyRotation() cost while a real camera stream is live, no widget tree', (tester) async {
    await YuvFfi.initialize();

    final cameras = await availableCameras();
    expect(cameras, isNotEmpty, reason: 'a physical camera must be available on the driving device');
    final camera = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cameras.first);
    final controller = CameraController(camera, ResolutionPreset.medium, enableAudio: false, fps: 30);
    await controller.initialize();
    addTearDown(controller.dispose);

    const targetSamples = 20;
    final rotationUsLive = <double>[]; // rotated inside the live callback, camera stream still open
    var warmupSeen = 0;
    var warmedUp = false;
    YuvImage? savedFrame; // one real camera frame's YUV, kept for the offline re-measurement below

    final subscription = CameraPlatform.instance.onStreamedFrameAvailable(controller.cameraId).listen((data) {
      if (!warmedUp) {
        warmupSeen++;
        if (warmupSeen >= 5) warmedUp = true;
        return;
      }
      if (rotationUsLive.length >= targetSamples) return;

      final rotation = YuvImageRotation.values.firstWhere((e) => e.degrees == camera.sensorOrientation.abs());
      final yuv = CameraImage.fromPlatformInterface(data).toYuvImage();
      savedFrame ??= yuv.copy();

      final sw = Stopwatch()..start();
      yuv.applyRotation(rotation.toZero());
      sw.stop();
      rotationUsLive.add(sw.elapsedTicks * 1000000 / Stopwatch().frequency);
    });

    final stopwatch = Stopwatch()..start();
    while (rotationUsLive.length < targetSamples && stopwatch.elapsed < const Duration(seconds: 30)) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    }

    // Stop the stream, then re-measure the exact same real frame's bytes,
    // now with no camera pipeline running at all -- isolates "real frame
    // content/geometry" from "concurrent camera pipeline load".
    await subscription.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final frame = savedFrame;
    expect(frame, isNotNull, reason: 'no frame was captured to re-measure offline');
    final rotationUsOffline = <double>[];
    final rotation = YuvImageRotation.values.firstWhere((e) => e.degrees == camera.sensorOrientation.abs());
    for (var i = 0; i < 5; i++) {
      frame!.copy().applyRotation(rotation.toZero()); // warm-up
    }
    for (var i = 0; i < targetSamples; i++) {
      final copy = frame!.copy();
      final sw = Stopwatch()..start();
      copy.applyRotation(rotation.toZero());
      sw.stop();
      rotationUsOffline.add(sw.elapsedTicks * 1000000 / Stopwatch().frequency);
    }

    rotationUsLive.sort();
    rotationUsOffline.sort();
    final medianLiveUs = rotationUsLive.isEmpty ? 0.0 : rotationUsLive[rotationUsLive.length ~/ 2];
    final medianOfflineUs = rotationUsOffline[rotationUsOffline.length ~/ 2];

    debugPrint(
      jsonEncode({
        'card': 'rotate_under_camera_load_adhoc',
        'device': 'pixel3',
        'platform': Platform.operatingSystem,
        'sensor_orientation': camera.sensorOrientation,
        'frame_size': '${frame!.width}x${frame.height}',
        'planes': [
          for (final p in frame.planes)
            {'bytesPerRow': p.bytesPerRow, 'pixelStride': p.pixelStride, 'expectedTightRowBytes': frame.width * p.pixelStride},
        ],
        'live_n': rotationUsLive.length,
        'live_median_ms': medianLiveUs / 1000,
        'live_min_ms': rotationUsLive.isEmpty ? 0.0 : rotationUsLive.first / 1000,
        'live_max_ms': rotationUsLive.isEmpty ? 0.0 : rotationUsLive.last / 1000,
        'offline_n': rotationUsOffline.length,
        'offline_median_ms': medianOfflineUs / 1000,
        'offline_min_ms': rotationUsOffline.first / 1000,
        'offline_max_ms': rotationUsOffline.last / 1000,
      }),
    );

    expect(rotationUsLive, isNotEmpty, reason: 'no frame was rotated during the measurement window');
  }, timeout: const Timeout(Duration(minutes: 1)));
}
