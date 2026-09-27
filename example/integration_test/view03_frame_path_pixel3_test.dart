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
import 'package:yuv_ffi_example/widgets/yuv_camera_preview.dart';

/// VIEW-03: full "frame delivered by the platform -> frame shown" path on a
/// real Pixel 3 camera, through the same public [YuvCameraPreview] contract
/// `CameraScreen` uses (`transform` -> [YuvFramePresenter.present] ->
/// `onFramePresented`).
///
/// ## What "before/after" means here
///
/// The task asks to compare the full path before/after the VIEW-00..02 cycle.
/// That comparison cannot run as one test file on both revisions: before
/// VIEW-01, `YuvCameraPreview` had no `onFramePresented`/`onStreamStopped`
/// contract at all (`transform` was the only hook, and the FPS counter it fed
/// counted conversions, not draws -- see VIEW-01's executor report for why
/// that number was wrong and completed.md for the full history). Adding those
/// callbacks to the pre-cycle widget to make it comparable would mean
/// benchmarking a patched baseline, not the code that actually shipped before
/// VIEW-00..02.
///
/// So this file is the **candidate** measurement (current HEAD, after
/// VIEW-00..02). The **before** side is `view03_frame_path_pixel3_baseline_test.dart`
/// (kept in `doc/perf/results/view03_pixel3_raw/` as the exact source used
/// against commit `9d14f83`, since that commit's `YuvCameraPreview` no longer
/// exists on this branch and the file cannot live in `example/integration_test/`
/// without failing analysis against the current widget).
///
/// ## Methodology
///
/// Real front camera on `-d 8B1X11QLW`, resolution/format identical to
/// `CameraScreen` (`ResolutionPreset.medium`, `enableAudio: false`). Per the
/// causal experiment in `doc/perf/results/bgra_review_2026-09-27.md` (screen
/// on/off caused a 4x swing on this same device), the runner must record
/// `adb shell dumpsys power | grep -E "mWakefulness|mScreenOn"` immediately
/// before starting the drive and keep the screen on throughout -- this file
/// cannot enforce that from inside the app, so it is a documented run
/// precondition, not part of the JSON output.
///
/// Three counts answer different questions, per the independent review's
/// condition 2, because `_YuvCameraPreviewMobile` drops frames *before*
/// calling `transform`:
///
/// - **delivered**: a new platform frame arrived (`CameraPlatform.instance.
///   onStreamedFrameAvailable` fired). Measured by the **second** `testWidgets`
///   below, in isolation, with no `YuvCameraPreview`/presenter in the tree at
///   all -- `MethodChannelCamera.onStreamedFrameAvailable` is not safe to call
///   a second time on the same camera while something else already listens
///   to it: each call replaces the platform interface's one internal
///   `StreamController` and re-subscribes its one native listener, so a
///   second caller *steals* the stream away from an existing subscriber
///   rather than observing it alongside it (confirmed by trying exactly that
///   in-tree and getting `frames_delivered: 0` for the widget's own
///   subscription). There is no way to observe this stream a second time
///   without taking it over, so "delivered" cannot be measured in the same
///   run as "accepted"/"presented" -- it is measured under the identical
///   camera, resolution and warm-up, immediately before or after, instead.
/// - **accepted**: `transform` was called for a frame (i.e. the preview's own
///   busy-gate let it through). Timestamped by [DateTime.now] at the *start*
///   of `transform`, before any conversion runs inside it. Measured by the
///   first `testWidgets`, through the public `YuvCameraPreview` contract.
/// - **presented**: `onFramePresented` fired, i.e. the frame `transform`
///   returned was actually decoded and drawn. Same run as `accepted`.
///
/// `accepted - presented` is the count [YuvFramePresenter] itself dropped (a
/// decode in flight when a newer frame arrived) and is measured directly.
/// `delivered - accepted` -- what the mobile preview's own gate drops before
/// `transform` ever runs -- can only be estimated by comparing the delivered
/// rate of the second run against the accepted rate of the first, not
/// computed frame-for-frame; the report must say so and must not present a
/// single combined "drop rate", which is what the previous version of this
/// file got wrong by counting `accepted` as if it were `delivered`.
///
/// The `accepted_to_shown_us` latency pairs the *last* `accepted` timestamp
/// with the next `presented` event: since the preview accepts at most one
/// frame at a time (the whole point of [YuvFramePresenter]), the pending
/// accepted timestamp when `onFramePresented` fires always belongs to the
/// frame that was just drawn -- there is never a second accepted frame
/// in flight to confuse the pairing. This starts the clock at the true start
/// of `transform`, before any conversion, per the independent review's
/// condition 1 -- the previous version of this file started it only after
/// `transform` had already finished converting the frame.
///
/// Conversion cost (`toBgraBytes()`, the same call `YuvFramePresenter.present()`
/// runs right after `transform` returns) is measured by the **third**
/// `testWidgets` below, also with no `YuvCameraPreview` in the tree: calling
/// `toBgraBytes()` a second time inside `transform` would add work the real
/// preview never does, which is what the previous version of this file did
/// and the independent review flagged.
///
/// Run (from `example/`), screen on and unlocked:
/// ```
/// adb shell dumpsys power | grep -E "mWakefulness|mScreenOn"
/// flutter drive --driver=test_driver/integration_test.dart \
///   --target=integration_test/view03_frame_path_pixel3_test.dart \
///   -d 8B1X11QLW --profile
/// ```
/// `flutter drive` refuses `--release` on non-web devices
/// ("Use --profile mode for testing application performance"); `--profile`
/// is the practical ceiling for this tool, as for every earlier Pixel 3 card.
///
/// Memory is read from outside the test process, immediately after the run
/// while the app is still on the preview screen (this file holds it there for
/// `holdForMemorySeconds` after measuring):
/// ```
/// adb shell dumpsys meminfo com.example.yuv_ffi_example
/// ```
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const warmupSeconds = 3;
  const measureSeconds = 10;
  const holdForMemorySeconds = 8;

  testWidgets('VIEW-03 Pixel 3: accepted/presented frame counts and the accepted-to-shown path', (tester) async {
    expect(kIsWeb, isFalse, reason: 'this measurement is for the mobile preview path on a physical device');
    await YuvFfi.initialize();

    final cameras = await availableCameras();
    expect(cameras, isNotEmpty, reason: 'a physical camera must be available on the driving device');
    final camera = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cameras.first);
    final controller = CameraController(camera, ResolutionPreset.medium, enableAudio: false, fps: 30);
    await controller.initialize();
    addTearDown(controller.dispose);

    var accepted = 0;
    var presented = 0;
    var warmedUp = false;
    final pathUs = <double>[];
    DateTime? lastAcceptedAt;

    YuvImage onFrame(YuvImage image) {
      if (warmedUp) {
        accepted++;
        lastAcceptedAt = DateTime.now();
      }
      return image;
    }

    void onPresented() {
      final acceptedAt = lastAcceptedAt;
      if (warmedUp) {
        presented++;
        if (acceptedAt != null) {
          pathUs.add(DateTime.now().difference(acceptedAt).inMicroseconds.toDouble());
        }
      }
      lastAcceptedAt = null;
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: YuvCameraPreview(cameraController: controller, transform: onFrame, onFramePresented: onPresented),
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
    accepted = 0;
    presented = 0;
    pathUs.clear();
    lastAcceptedAt = null;
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
    // What the presenter itself dropped (a decode/draw in flight when a
    // newer accepted frame arrived); the preview's own pre-transform drops
    // are not observable here, see the file-level doc comment.
    final droppedByPresenter = accepted - presented;

    debugPrint(
      jsonEncode({
        'card': 'VIEW-03',
        'device': 'pixel3',
        'phase': 'measure',
        'platform': Platform.operatingSystem,
        'measured_seconds': measuredSeconds,
        'frames_accepted': accepted,
        'frames_presented': presented,
        'dropped_by_presenter': droppedByPresenter,
        'display_fps': displayFps,
        'accepted_to_shown_us': _summary(pathUs),
      }),
    );

    expect(presented, greaterThan(0), reason: 'no frame reached onFramePresented; the preview never drew anything during the measured window');

    // Held here, camera still streaming, so `adb shell dumpsys meminfo` run
    // from the host right after this test finishes still sees the live
    // preview state rather than a torn-down widget tree.
    final holdStopwatch = Stopwatch()..start();
    while (holdStopwatch.elapsed < const Duration(seconds: holdForMemorySeconds)) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    }

    debugPrint(jsonEncode({'card': 'VIEW-03', 'device': 'pixel3', 'phase': 'ready_for_meminfo'}));
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('VIEW-03 Pixel 3 diagnostic: platform frame delivery rate in isolation', (tester) async {
    // Separate from the path measurement above, with no YuvCameraPreview or
    // YuvFramePresenter in the tree: CameraPlatform.instance.
    // onStreamedFrameAvailable is single-listener (see the file-level doc
    // comment), so this run is the only listener on this camera for its
    // whole duration, under the same resolution/warm-up as the path run.
    expect(kIsWeb, isFalse);
    await YuvFfi.initialize();

    final cameras = await availableCameras();
    expect(cameras, isNotEmpty, reason: 'a physical camera must be available on the driving device');
    final camera = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cameras.first);
    final controller = CameraController(camera, ResolutionPreset.medium, enableAudio: false, fps: 30);
    await controller.initialize();
    addTearDown(controller.dispose);

    var delivered = 0;
    var warmedUp = false;

    final subscription = CameraPlatform.instance.onStreamedFrameAvailable(controller.cameraId).listen((_) {
      if (warmedUp) delivered++;
    });
    addTearDown(subscription.cancel);

    final warmupStopwatch = Stopwatch()..start();
    while (warmupStopwatch.elapsed < const Duration(seconds: warmupSeconds)) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    }
    delivered = 0;
    warmedUp = true;

    final measureStopwatch = Stopwatch()..start();
    while (measureStopwatch.elapsed < const Duration(seconds: measureSeconds)) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    warmedUp = false;

    final measuredSeconds = measureStopwatch.elapsed.inMicroseconds / 1000000;

    debugPrint(
      jsonEncode({
        'card': 'VIEW-03',
        'device': 'pixel3',
        'phase': 'delivery_diagnostic',
        'platform': Platform.operatingSystem,
        'measured_seconds': measuredSeconds,
        'frames_delivered': delivered,
        'delivery_rate_hz': delivered / measuredSeconds,
      }),
    );

    expect(delivered, greaterThan(0), reason: 'no frame was delivered by the platform during the diagnostic window');
  }, timeout: const Timeout(Duration(minutes: 1)));

  testWidgets('VIEW-03 Pixel 3 diagnostic: BGRA conversion cost in isolation', (tester) async {
    // Separate from the path measurement above: this is the only place
    // toBgraBytes() runs here, so it cannot add a second conversion to a
    // frame the real preview also converts inside YuvFramePresenter.present().
    expect(kIsWeb, isFalse);
    await YuvFfi.initialize();

    final cameras = await availableCameras();
    expect(cameras, isNotEmpty, reason: 'a physical camera must be available on the driving device');
    final camera = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cameras.first);
    final controller = CameraController(camera, ResolutionPreset.medium, enableAudio: false, fps: 30);
    await controller.initialize();
    addTearDown(controller.dispose);

    const targetSamples = 30;
    final conversionUs = <double>[];
    final frequency = Stopwatch().frequency;
    var warmedUp = false;
    var warmupSeen = 0;

    final subscription = CameraPlatform.instance.onStreamedFrameAvailable(controller.cameraId).listen((data) {
      if (!warmedUp) {
        warmupSeen++;
        if (warmupSeen >= 5) warmedUp = true;
        return;
      }
      if (conversionUs.length >= targetSamples) return;

      final rotation = YuvImageRotation.values.firstWhere((e) => e.degrees == camera.sensorOrientation.abs());
      var yuv = CameraImage.fromPlatformInterface(data).toYuvImage();
      if (Platform.isAndroid) {
        yuv = yuv.applyRotation(rotation.toZero());
      }

      final sw = Stopwatch()..start();
      yuv.toBgraBytes();
      sw.stop();
      conversionUs.add(sw.elapsedTicks * 1000000 / frequency);
    });
    addTearDown(subscription.cancel);

    final stopwatch = Stopwatch()..start();
    while (conversionUs.length < targetSamples && stopwatch.elapsed < const Duration(seconds: 30)) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    }

    debugPrint(
      jsonEncode({
        'card': 'VIEW-03',
        'device': 'pixel3',
        'phase': 'conversion_diagnostic',
        'platform': Platform.operatingSystem,
        'conversion_us': _summary(conversionUs),
      }),
    );

    expect(conversionUs, isNotEmpty, reason: 'no frame was converted during the diagnostic window');
  }, timeout: const Timeout(Duration(minutes: 1)));
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
