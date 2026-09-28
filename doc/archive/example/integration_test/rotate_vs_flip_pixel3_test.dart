import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Ad-hoc verification, not a VIEW-03 deliverable: isolates `applyRotation()`
/// vs `applyFlipHorizontal()` cost on-device, with no camera and no example
/// preview code at all -- a direct A/B on the same public API call the
/// mobile preview measurement found ~94 ms vs ~8 ms for, to check whether
/// that gap is a property of the operations themselves on this device, or an
/// artifact of the preview measurement.
///
/// A Windows host bench on a real 1477x1065 photo (`test/scratch_golden/
/// golden_rotate_bench_test.dart`, not committed) found rotate and flip
/// costing the *same*, ~64-70 ms, at every rotation angle -- consistent with
/// the already-documented `native-perf-regression-0-4` generic per-pixel
/// kernel finding, which slowed both operations similarly on 1080p. The
/// on-device 8 ms flip number contradicts that: if the same generic-driver
/// overhead applied on Android, flip should cost close to what rotate costs
/// here, not an order of magnitude less. This file checks which of the two
/// findings is the artifact, at the exact geometry the camera preview uses
/// (720x480 I420, matching Pixel 3 ResolutionPreset.medium).
///
/// Run (from `example/`), screen on:
/// ```
/// flutter drive --driver=test_driver/integration_test.dart \
///   --target=integration_test/rotate_vs_flip_pixel3_test.dart -d 8B1X11QLW --profile
/// ```
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const width = 720;
  const height = 480;
  const warmup = 5;
  const runs = 30;

  testWidgets('rotate vs flip cost at camera-preview geometry, no camera involved', (tester) async {
    await YuvFfi.initialize();

    final rgba = Uint8List(width * height * 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = (y * width + x) * 4;
        rgba[i] = (x * 3 + 10) & 0xFF;
        rgba[i + 1] = (y * 5 + 20) & 0xFF;
        rgba[i + 2] = (x * 7 + y * 11 + 30) & 0xFF;
        rgba[i + 3] = 255;
      }
    }
    final source = YuvImage.i420(width, height)..applyRgbaBytes(rgba);
    final frequency = Stopwatch().frequency;

    final result = <String, Map<String, double>>{};

    for (final rotation in YuvImageRotation.values) {
      for (var i = 0; i < warmup; i++) {
        source.copy().applyRotation(rotation);
      }
      final samplesUs = <double>[];
      for (var i = 0; i < runs; i++) {
        final copy = source.copy();
        final sw = Stopwatch()..start();
        copy.applyRotation(rotation);
        sw.stop();
        samplesUs.add(sw.elapsedTicks * 1000000 / frequency);
      }
      samplesUs.sort();
      result['rotate_${rotation.degrees}'] = {
        'median_ms': samplesUs[samplesUs.length ~/ 2] / 1000,
        'min_ms': samplesUs.first / 1000,
        'max_ms': samplesUs.last / 1000,
      };
    }

    for (var i = 0; i < warmup; i++) {
      source.copy().applyFlipHorizontal();
    }
    final flipSamplesUs = <double>[];
    for (var i = 0; i < runs; i++) {
      final copy = source.copy();
      final sw = Stopwatch()..start();
      copy.applyFlipHorizontal();
      sw.stop();
      flipSamplesUs.add(sw.elapsedTicks * 1000000 / frequency);
    }
    flipSamplesUs.sort();
    result['flip_horizontal'] = {
      'median_ms': flipSamplesUs[flipSamplesUs.length ~/ 2] / 1000,
      'min_ms': flipSamplesUs.first / 1000,
      'max_ms': flipSamplesUs.last / 1000,
    };

    debugPrint(
      jsonEncode({
        'card': 'rotate_vs_flip_adhoc',
        'device': 'pixel3',
        'platform': Platform.operatingSystem,
        'width': width,
        'height': height,
        ...result,
      }),
    );

    expect(result, isNotEmpty);
  });
}
