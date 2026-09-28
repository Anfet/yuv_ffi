import 'dart:convert';
import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_ffi_example/ext.dart';
import 'package:yuv_ffi_example/widgets/impl/yuv_camera_preview_io.dart';
import 'package:yuv_ffi_example/widgets/yuv_camera_preview.dart';

/// PACK-00: compares the padded camera import
/// ([kYuvCameraPreviewPackPlanes] = `false`) against the tightly packed
/// import (`true` -- the default since PACK-01C; no row padding, PACK-00's
/// experimental switch) of the same real Pixel 3 camera frames, inside one running
/// `_YuvCameraPreviewMobile` subscription -- the same VIEW-03 methodology and
/// diagnostic hook (`debugYuvCameraPreviewMobileEvent`,
/// `example/lib/widgets/impl/yuv_camera_preview_io.dart`), so delivered,
/// dropped, accepted and presented counts are of one live, working preview,
/// not an idle listener. Neither variant subscribes to the camera twice or
/// runs a second conversion in the frame's real path.
///
/// Both variants also run through `applyRotation` and (implicitly, via
/// `YuvFramePresenter`) `toBgraBytes`, so the `to_yuv_image_us`, `rotation_us`
/// and `accepted_to_presented_us` intervals this file records answer PACK-00's
/// "separately measure the cost of import, rotate, BGRA and the full path"
/// requirement without adding a second conversion of the same frame.
///
/// `transform` (`recordGeometry` below) runs after rotation/flip, so its
/// plane geometry is the *rotated* output, not the padded/packed import this
/// run means to compare -- recorded separately as `rotated_bytes_per_row` for
/// transparency, but not the number that proves the variant took effect. The
/// import geometry that does prove it (`import_bytes_per_row`) is captured
/// once per run from a one-off, separate listen on the same platform stream,
/// *before* the measured widget mounts and *after* it is cancelled -- not
/// concurrent with the measured subscription, so it does not compete for or
/// steal frames from it.
///
/// Two runs per variant, order alternated (padded, packed, packed, padded),
/// on the same camera configuration `CameraScreen` uses
/// (`ResolutionPreset.medium`, front camera), all four runs inside one
/// `testWidgets` body so each run's widget tree is pumped by the same
/// `WidgetTester`. Per the causal experiment in
/// `doc/perf/results/bgra_review_2026-09-27.md` (screen on/off caused a 4x
/// swing on this device), the runner must keep the screen on throughout.
///
/// `flutter drive` refuses `--release` on non-web devices; `--profile` is the
/// practical ceiling for this tool, as for every earlier Pixel 3 card.
///
/// Run (from `example/`), screen on and unlocked:
/// ```
/// flutter drive --driver=test_driver/integration_test.dart \
///   --target=integration_test/pack00_pack_vs_padded_pixel3_test.dart \
///   -d 8B1X11QLW --profile
/// ```
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const warmupSeconds = 3;
  const measureSeconds = 10;

  Future<Map<String, Object?>> measureOneRun(WidgetTester tester, {required bool packPlanes, required int runIndex}) async {
    kYuvCameraPreviewPackPlanes = packPlanes;

    final cameras = await availableCameras();
    expect(cameras, isNotEmpty, reason: 'a physical camera must be available on the driving device');
    final camera = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cameras.first);
    final controller = CameraController(camera, ResolutionPreset.medium, enableAudio: false, fps: 30);
    await controller.initialize();

    debugYuvCameraPreviewMobileClock
      ..reset()
      ..start();

    var warmedUp = false;
    var delivered = 0;
    var droppedStale = 0;
    var droppedBusy = 0;
    var accepted = 0;
    var presented = 0;
    Duration? lastDeliveredAt;
    Duration? lastAcceptedAt;
    Duration? lastYuvImageReadyAt;
    Duration? lastRotationAppliedAt;
    final toYuvImageUs = <double>[]; // delivered -> yuvImageReady (plane copy, padded or packed)
    final rotationUs = <double>[]; // yuvImageReady -> rotationApplied (applyRotation alone)
    final flipUs = <double>[]; // rotationApplied -> acceptedForTransform (applyFlipHorizontal alone)
    final acceptedToPresentedUs = <double>[]; // acceptedForTransform -> presented (transform + toBgraBytes + draw)
    final presentedGapUs = <double>[]; // presented(N) -> presented(N+1): the real display period
    Duration? lastPresentedAt;
    List<int>? planeBytesPerRow;
    List<int>? planePixelStride;
    List<int>? rotatedBytesPerRow;
    List<int>? rotatedPixelStride;

    debugYuvCameraPreviewMobileEvent = (kind, at, {reason}) {
      if (!warmedUp) return;
      switch (kind) {
        case DebugYuvCameraPreviewMobileEventKind.delivered:
          delivered++;
          lastDeliveredAt = at;
        case DebugYuvCameraPreviewMobileEventKind.droppedBeforeTransform:
          if (reason == 'busy') {
            droppedBusy++;
          } else {
            droppedStale++;
          }
        case DebugYuvCameraPreviewMobileEventKind.yuvImageReady:
          lastYuvImageReadyAt = at;
          final deliveredAt = lastDeliveredAt;
          if (deliveredAt != null) {
            toYuvImageUs.add((at - deliveredAt).inMicroseconds.toDouble());
          }
        case DebugYuvCameraPreviewMobileEventKind.rotationApplied:
          lastRotationAppliedAt = at;
          final yuvImageReadyAt = lastYuvImageReadyAt;
          if (yuvImageReadyAt != null) {
            rotationUs.add((at - yuvImageReadyAt).inMicroseconds.toDouble());
          }
        case DebugYuvCameraPreviewMobileEventKind.acceptedForTransform:
          accepted++;
          lastAcceptedAt = at;
          final rotationAppliedAt = lastRotationAppliedAt;
          if (rotationAppliedAt != null) {
            flipUs.add((at - rotationAppliedAt).inMicroseconds.toDouble());
          }
      }
    };

    void onPresented() {
      final at = debugYuvCameraPreviewMobileClock.elapsed;
      if (!warmedUp) return;
      presented++;
      final acceptedAt = lastAcceptedAt;
      if (acceptedAt != null) {
        acceptedToPresentedUs.add((at - acceptedAt).inMicroseconds.toDouble());
      }
      final previousPresentedAt = lastPresentedAt;
      if (previousPresentedAt != null) {
        presentedGapUs.add((at - previousPresentedAt).inMicroseconds.toDouble());
      }
      lastPresentedAt = at;
    }

    // recordGeometry runs as `transform`, called by `presentCameraFrame`
    // *after* applyRotation()/applyFlipHorizontal() (see
    // `_YuvCameraPreviewMobile.onNewImageAvailable`), so its plane geometry
    // is the rotated output, not the raw padded/packed import this run means
    // to compare. The import geometry is captured separately below, once,
    // straight off the platform stream before the measured widget mounts.
    YuvImage recordGeometry(YuvImage image) {
      rotatedBytesPerRow ??= [for (final p in image.planes) p.bytesPerRow];
      rotatedPixelStride ??= [for (final p in image.planes) p.pixelStride];
      return image;
    }

    YuvImage? capturedImport;
    final geometrySubscription = CameraPlatform.instance.onStreamedFrameAvailable(controller.cameraId).listen((data) {
      capturedImport ??= CameraImage.fromPlatformInterface(data).toYuvImage();
    });
    final geometryStopwatch = Stopwatch()..start();
    while (capturedImport == null && geometryStopwatch.elapsed < const Duration(seconds: 5)) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    await geometrySubscription.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (capturedImport != null) {
      planeBytesPerRow = [for (final p in capturedImport!.planes) p.bytesPerRow];
      planePixelStride = [for (final p in capturedImport!.planes) p.pixelStride];
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: YuvCameraPreview(cameraController: controller, transform: recordGeometry, onFramePresented: onPresented),
        ),
      ),
    );
    await tester.pump();

    final warmupStopwatch = Stopwatch()..start();
    while (warmupStopwatch.elapsed < const Duration(seconds: warmupSeconds)) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    }
    delivered = 0;
    droppedStale = 0;
    droppedBusy = 0;
    accepted = 0;
    presented = 0;
    toYuvImageUs.clear();
    rotationUs.clear();
    flipUs.clear();
    acceptedToPresentedUs.clear();
    presentedGapUs.clear();
    lastDeliveredAt = null;
    lastYuvImageReadyAt = null;
    lastRotationAppliedAt = null;
    lastAcceptedAt = null;
    lastPresentedAt = null;
    warmedUp = true;

    final measureStopwatch = Stopwatch()..start();
    while (measureStopwatch.elapsed < const Duration(seconds: measureSeconds)) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    warmedUp = false;

    debugYuvCameraPreviewMobileEvent = null;
    debugYuvCameraPreviewMobileClock.stop();

    // Unmount this run's widget tree before the next run opens the camera
    // again, so the previous presenter/image cache state does not leak in.
    await tester.pumpWidget(const SizedBox.shrink());
    await controller.dispose();
    kYuvCameraPreviewPackPlanes = false;

    final measuredSeconds = measureStopwatch.elapsed.inMicroseconds / 1000000;
    final displayFps = presented / measuredSeconds;
    final importMedianMs = _summary(toYuvImageUs)['median_ms'] ?? 0;
    final rotationMedianMs = _summary(rotationUs)['median_ms'] ?? 0;

    return {
      'card': 'PACK-00',
      'device': 'pixel3',
      'variant': packPlanes ? 'packed' : 'padded',
      'run_index': runIndex,
      'platform': Platform.operatingSystem,
      'measured_seconds': measuredSeconds,
      'import_bytes_per_row': planeBytesPerRow,
      'import_pixel_stride': planePixelStride,
      'rotated_bytes_per_row': rotatedBytesPerRow,
      'rotated_pixel_stride': rotatedPixelStride,
      'frames_delivered': delivered,
      'dropped_stale': droppedStale,
      'dropped_busy': droppedBusy,
      'frames_accepted': accepted,
      'frames_presented': presented,
      'display_fps': displayFps,
      'delivery_rate_hz': delivered / measuredSeconds,
      'to_yuv_image_us': _summary(toYuvImageUs),
      'rotation_us': _summary(rotationUs),
      'flip_us': _summary(flipUs),
      'accepted_to_presented_us': _summary(acceptedToPresentedUs),
      'presented_gap_us': _summary(presentedGapUs),
      'import_plus_rotation_median_ms': importMedianMs + rotationMedianMs,
    };
  }

  testWidgets('PACK-00 Pixel 3: padded vs packed camera import, alternated order, one running subscription per run', (tester) async {
    expect(kIsWeb, isFalse, reason: 'this measurement is for the mobile preview path on a physical device');
    await YuvFfi.initialize();

    final results = <Map<String, Object?>>[];
    // Alternated order: padded, packed, packed, padded -- cancels a
    // monotonic drift (thermal, camera warm-up) from favoring either variant.
    final plan = [false, true, true, false];
    for (var i = 0; i < plan.length; i++) {
      final result = await measureOneRun(tester, packPlanes: plan[i], runIndex: i);
      results.add(result);
      debugPrint(jsonEncode(result));
      // Let the platform fully release the previous camera session before
      // the next run opens it again.
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
    }

    for (final result in results) {
      expect(
        result['frames_presented'],
        greaterThan(0),
        reason: 'no frame reached onFramePresented in run ${result['run_index']} (${result['variant']})',
      );
      expect(
        result['frames_delivered'],
        greaterThan(0),
        reason: 'the platform never delivered a frame in run ${result['run_index']} (${result['variant']})',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}

Map<String, double> _summary(List<double> samplesUs) {
  if (samplesUs.isEmpty) {
    return {'n': 0, 'median_ms': 0, 'p95_ms': 0, 'min_ms': 0, 'max_ms': 0};
  }
  final sorted = samplesUs.toList()..sort();
  final medianUs = sorted[sorted.length ~/ 2];
  final p95Us = sorted[(sorted.length * 0.95).floor().clamp(0, sorted.length - 1)];
  return {
    'n': sorted.length.toDouble(),
    'median_ms': medianUs / 1000,
    'p95_ms': p95Us / 1000,
    'min_ms': sorted.first / 1000,
    'max_ms': sorted.last / 1000,
  };
}
