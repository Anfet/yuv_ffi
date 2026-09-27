import 'dart:convert';
import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_ffi_example/widgets/impl/yuv_camera_preview_io.dart';
import 'package:yuv_ffi_example/widgets/yuv_camera_preview.dart';

/// VIEW-03: full "frame delivered by the platform -> frame shown" path on a
/// real Pixel 3 camera, measured inside the mobile preview's one existing
/// platform subscription (`_YuvCameraPreviewMobile.onNewImageAvailable`).
///
/// ## Why the second-pass measurement was rejected
///
/// The second pass split delivered/accepted/presented across three separate
/// test runs (the platform's `onStreamedFrameAvailable` cannot be listened to
/// a second time without stealing the stream from the widget under test).
/// The independent review rejected that: `delivered` under an idle listener
/// with no preview work running is not the same signal as `delivered` while
/// the real subscription's callback is doing YUV conversion, rotation and
/// feeding `YuvFramePresenter`, so the ~78% "drop" figure computed from two
/// different runs did not actually prove anything about drops inside a
/// running preview. It also flagged a real gap the second pass never
/// explained: at 6.25-6.55 shown fps, the period between two `presented`
/// events is ~153-160 ms, while the measured `transform -> presented`
/// latency was only 33-41 ms -- over 110 ms unaccounted for.
///
/// ## What this file does instead
///
/// [debugYuvCameraPreviewMobileEvent] (`yuv_camera_preview_io.dart`, example-only,
/// `null` outside a measurement run) is set once, before pumping the widget,
/// and raised from inside the mobile preview's single real subscription at
/// four points, all sharing one clock ([debugYuvCameraPreviewMobileClock]):
///
/// - `delivered`: the instant `onNewImageAvailable` is entered, before
///   `mounted`/generation/`isBusy` are even checked.
/// - `droppedBeforeTransform` (with `reason: 'stale'` or `'busy'`): the frame
///   was dropped before `transform` ever ran.
/// - `yuvImageReady`: `CameraImage.toYuvImage()` (the plane copy from
///   platform data, `example/lib/ext.dart`) has just returned, before any
///   rotation/flip -- isolates plane-copy cost from rotation cost, per the
///   architect's decision to measure YUV preparation and rotation
///   separately.
/// - `acceptedForTransform`: rotation/flip have also run, and
///   `presentCameraFrame` (which calls `transform`) is about to be called --
///   this isolates the whole YUV-preparation/rotation stretch, which the
///   second pass's timer started *after*, per the independent review's
///   point about that gap.
///
/// `presented` reuses the existing public `onFramePresented` callback, read
/// against the same clock from inside this test -- no second hook needed for
/// an event the public API already exposes.
///
/// This is the *same* subscription `YuvCameraPreview` uses for real preview
/// work: the hook only records a timestamp, it does not skip, delay or
/// duplicate anything on the frame's actual path, so delivered/dropped/
/// accepted here are true counts of one live, working preview, not of an
/// idle listener.
///
/// ## Methodology
///
/// Real front camera on `-d 8B1X11QLW`, resolution/format identical to
/// `CameraScreen` (`ResolutionPreset.medium`, `enableAudio: false`). Per the
/// causal experiment in `doc/perf/results/bgra_review_2026-09-27.md` (screen
/// on/off caused a 4x swing on this same device), the runner must record
/// `adb shell dumpsys power | grep -E "mWakefulness|mScreenOn"` immediately
/// before starting the drive and keep the screen on throughout.
///
/// `flutter drive` refuses `--release` on non-web devices ("Use --profile
/// mode for testing application performance"); `--profile` is the practical
/// ceiling for this tool, as for every earlier Pixel 3 card.
///
/// Run (from `example/`), screen on and unlocked:
/// ```
/// flutter drive --driver=test_driver/integration_test.dart \
///   --target=integration_test/view03_frame_path_pixel3_test.dart \
///   -d 8B1X11QLW --profile
/// ```
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const warmupSeconds = 3;
  const measureSeconds = 10;

  testWidgets('VIEW-03 Pixel 3: delivered/dropped/accepted/presented in one running subscription', (tester) async {
    expect(kIsWeb, isFalse, reason: 'this measurement is for the mobile preview path on a physical device');
    await YuvFfi.initialize();

    final cameras = await availableCameras();
    expect(cameras, isNotEmpty, reason: 'a physical camera must be available on the driving device');
    final camera = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cameras.first);
    final controller = CameraController(camera, ResolutionPreset.medium, enableAudio: false, fps: 30);
    await controller.initialize();
    addTearDown(controller.dispose);

    debugYuvCameraPreviewMobileClock
      ..reset()
      ..start();
    addTearDown(() {
      debugYuvCameraPreviewMobileEvent = null;
      debugYuvCameraPreviewMobileClock.stop();
    });

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
    final toYuvImageUs = <double>[]; // delivered -> yuvImageReady (CameraImage.toYuvImage(): plane copy)
    final rotationUs = <double>[]; // yuvImageReady -> rotationApplied (applyRotation alone)
    final flipUs = <double>[]; // rotationApplied -> acceptedForTransform (applyFlipHorizontal alone)
    final acceptedToPresentedUs = <double>[]; // acceptedForTransform -> presented (transform + decode + draw)
    final presentedGapUs = <double>[]; // presented(N) -> presented(N+1): the true display period
    Duration? lastPresentedAt;

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

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: YuvCameraPreview(cameraController: controller, onFramePresented: onPresented),
        ),
      ),
    );
    await tester.pump();

    // Real camera frames arrive off the Flutter test clock, so this loop
    // drives wall-clock time via runAsync rather than tester.pump(duration):
    // pumping virtual time would not wait for the platform channel at all.
    final stopwatch = Stopwatch()..start();
    while (stopwatch.elapsed < const Duration(seconds: warmupSeconds)) {
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

    stopwatch
      ..reset()
      ..start();
    while (stopwatch.elapsed < const Duration(seconds: measureSeconds)) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    warmedUp = false;

    final measuredSeconds = stopwatch.elapsed.inMicroseconds / 1000000;
    final displayFps = presented / measuredSeconds;

    debugPrint(
      jsonEncode({
        'card': 'VIEW-03',
        'device': 'pixel3',
        'phase': 'single_subscription_measure',
        'platform': Platform.operatingSystem,
        'measured_seconds': measuredSeconds,
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
      }),
    );

    expect(presented, greaterThan(0), reason: 'no frame reached onFramePresented; the preview never drew anything during the measured window');
    expect(delivered, greaterThan(0), reason: 'the platform never delivered a frame during the measured window');
  }, timeout: const Timeout(Duration(minutes: 2)));
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
