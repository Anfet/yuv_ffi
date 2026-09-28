// VIEW-03 baseline source, preserved for reproducibility per the independent
// review's condition 3 (2026-09-27): this file cannot live in
// example/integration_test/ on release/0.4.2, because it targets the
// pre-VIEW-00..02 `YuvCameraPreview` (commit 9d14f83, the parent of VIEW-00's
// first commit 5b5dc56), whose widget signature no longer exists on this
// branch -- it would fail analysis against the current widget.
//
// To reproduce: `git worktree add <dir> 9d14f83`, `flutter pub get` inside
// `<dir>/example`, drop this file at
// `<dir>/example/integration_test/view03_frame_path_pixel3_baseline_test.dart`,
// then from `<dir>/example`:
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/view03_frame_path_pixel3_baseline_test.dart \
//     -d 8B1X11QLW --profile
//
// See ../view03_pixel3_frame_path_2026-09-27.md for why this measures
// transform-arrival rate and ImageCache growth rather than a shown-frame
// latency: the pre-cycle widget has no draw-confirmation event at all.

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_ffi_example/widgets/yuv_camera_preview.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const warmupSeconds = 3;
  const measureSeconds = 10;

  testWidgets('VIEW-03 baseline Pixel 3: pre-cycle transform-arrival rate and ImageCache growth', (tester) async {
    expect(kIsWeb, isFalse);
    await YuvFfi.initialize();

    final cameras = await availableCameras();
    expect(cameras, isNotEmpty, reason: 'a physical camera must be available on the driving device');
    final camera = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cameras.first);
    final controller = CameraController(camera, ResolutionPreset.medium, enableAudio: false, fps: 30);
    await controller.initialize();
    addTearDown(controller.dispose);

    var arrived = 0;
    var warmedUp = false;

    YuvImage onFrame(YuvImage image) {
      if (warmedUp) arrived++;
      return image;
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: YuvCameraPreview(cameraController: controller, transform: onFrame),
        ),
      ),
    );
    await tester.pump();

    final stopwatch = Stopwatch()..start();
    while (stopwatch.elapsed < const Duration(seconds: warmupSeconds)) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    }
    arrived = 0;
    warmedUp = true;
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();

    stopwatch
      ..reset()
      ..start();
    while (stopwatch.elapsed < const Duration(seconds: measureSeconds)) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    warmedUp = false;

    final measuredSeconds = stopwatch.elapsed.inMicroseconds / 1000000;
    final cache = PaintingBinding.instance.imageCache;

    debugPrint(
      jsonEncode({
        'card': 'VIEW-03',
        'device': 'pixel3',
        'phase': 'baseline_measure',
        'commit': '9d14f83',
        'platform': Platform.operatingSystem,
        'measured_seconds': measuredSeconds,
        'transform_arrivals': arrived,
        'transform_arrival_rate_hz': arrived / measuredSeconds,
        'image_cache_current_size': cache.currentSize,
        'image_cache_live_image_count': cache.liveImageCount,
      }),
    );

    expect(arrived, greaterThan(0), reason: 'no frame reached transform during the measured window');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
