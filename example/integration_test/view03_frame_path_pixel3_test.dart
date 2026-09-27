import 'dart:convert';
import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_ffi_example/widgets/yuv_camera_preview.dart';

/// VIEW-03: full "frame received -> frame shown" path on a real Pixel 3
/// camera, through the same public [YuvCameraPreview] contract `CameraScreen`
/// uses (`transform` -> [YuvFramePresenter.present] -> `onFramePresented`).
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
/// VIEW-00..02): it reports the one thing the task's own metric --
/// "received frame -> shown frame" -- means on this contract. The **before**
/// side is reported qualitatively from the pre-cycle source at commit
/// `9d14f83` (the commit right before VIEW-00's `5b5dc56`): the old
/// `_YuvCameraPreviewMobile` had no busy-frame gate on the receive side (see
/// VIEW-01 executor report point 1: "30 frames arrived before the first
/// decode finished, pendingImageCount = 30"), kept every decoded frame in the
/// global `ImageCache` until LRU eviction (point 2), and its FPS ticker
/// incremented in `transform`, i.e. on arrival, not on draw (point 3) -- so a
/// "received -> shown" latency and a real display FPS are not numbers the
/// pre-cycle code could produce even in principle; there was no single frame
/// whose receipt and display could be paired up under load. That absence is
/// itself the "before" data point this task asks to record, not a gap in
/// this file.
///
/// ## Methodology
///
/// Real front camera on `-d 8B1X11QLW`, resolution/format identical to
/// `CameraScreen` (`ResolutionPreset.medium`, `enableAudio: false`), a plain
/// `YuvCameraPreview` (no capture UI) collecting per-frame timestamps for
/// `MEASURE_SECONDS` after a `WARMUP_SECONDS` warm-up. Per the causal
/// experiment in `doc/perf/results/bgra_review_2026-09-27.md` (screen
/// on/off caused a 4x swing on this same device), the runner must record
/// `adb shell dumpsys power | grep -E "mWakefulness|mScreenOn"` immediately
/// before starting the drive and keep the screen on throughout -- this file
/// cannot enforce that from inside the app, so it is a documented run
/// precondition, not part of the JSON output.
///
/// Run (from `example/`), once per build mode, screen on and unlocked:
/// ```
/// adb shell dumpsys power | grep -E "mWakefulness|mScreenOn"
/// flutter drive --driver=test_driver/integration_test.dart \
///   --target=integration_test/view03_frame_path_pixel3_test.dart \
///   -d 8B1X11QLW --profile
/// flutter drive --driver=test_driver/integration_test.dart \
///   --target=integration_test/view03_frame_path_pixel3_test.dart \
///   -d 8B1X11QLW --release
/// ```
/// Memory is read from outside the test process, immediately after each run
/// while the app is still on the capture screen (this file holds it there
/// for `HOLD_FOR_MEMORY_SECONDS` after measuring, see below):
/// ```
/// adb shell dumpsys meminfo com.example.yuv_ffi_example
/// ```
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const warmupSeconds = 3;
  const measureSeconds = 10;
  const holdForMemorySeconds = 8;

  testWidgets('VIEW-03 Pixel 3: received-frame to shown-frame path, FPS, drops', (tester) async {
    expect(kIsWeb, isFalse, reason: 'this measurement is for the mobile preview path on a physical device');
    await YuvFfi.initialize();

    final cameras = await availableCameras();
    expect(cameras, isNotEmpty, reason: 'a physical camera must be available on the driving device');
    final camera = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cameras.first);
    final controller = CameraController(camera, ResolutionPreset.medium, enableAudio: false, fps: 30);
    await controller.initialize();
    addTearDown(controller.dispose);

    var received = 0;
    var presented = 0;
    var warmedUp = false;
    final conversionUs = <double>[];
    final pathUs = <double>[];
    final frequency = Stopwatch().frequency;

    YuvImage onFrame(YuvImage image) {
      received++;
      // toBgraBytes() does not mutate image; this measures the same
      // conversion YuvFramePresenter.present() runs right after transform
      // returns, without replacing the frame the presenter itself decodes.
      final sw = Stopwatch()..start();
      image.toBgraBytes();
      sw.stop();
      if (warmedUp) {
        conversionUs.add(sw.elapsedTicks * 1000000 / frequency);
      }
      _arrivalStopwatch = Stopwatch()..start();
      return image;
    }

    void onPresented() {
      presented++;
      final arrival = _arrivalStopwatch;
      if (warmedUp && arrival != null) {
        pathUs.add(arrival.elapsedTicks * 1000000 / arrival.frequency);
      }
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
    received = 0;
    presented = 0;
    conversionUs.clear();
    pathUs.clear();
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
    final dropped = received - presented;
    final dropRate = received == 0 ? 0.0 : dropped / received;

    debugPrint(
      jsonEncode({
        'card': 'VIEW-03',
        'device': 'pixel3',
        'phase': 'measure',
        'platform': Platform.operatingSystem,
        'measured_seconds': measuredSeconds,
        'frames_received': received,
        'frames_presented': presented,
        'frames_dropped': dropped,
        'drop_rate': dropRate,
        'display_fps': displayFps,
        'conversion_us': _summary(conversionUs),
        'received_to_shown_us': _summary(pathUs),
      }),
    );

    expect(presented, greaterThan(0), reason: 'no frame reached onFramePresented; the preview never drew anything during the measured window');
    expect(dropRate, lessThan(1.0), reason: 'every received frame was dropped; the presenter never freed up during the measured window');

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
}

Stopwatch? _arrivalStopwatch;

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
