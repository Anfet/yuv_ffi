import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Ad-hoc verification, not a VIEW-03 deliverable. `rotate_under_camera_load_pixel3_test.dart`
/// found that a real camera frame's `applyRotation()` cost (~93 ms) is
/// identical whether the camera stream is still live or fully stopped --
/// ruling out concurrent camera pipeline load. That test's diagnostic also
/// found the real frame's Y plane has `bytesPerRow=768` against a tight
/// `width * pixelStride = 720` -- 48 bytes of row padding this repo's own
/// synthetic 720x480 test input (built via `YuvImage.i420(w, h)..
/// applyRgbaBytes(rgba)`, which is always tight) never has. This file is the
/// one remaining isolation: build a synthetic 720x480 I420 frame with the
/// *same* padded row stride the camera reports, no camera involved at all,
/// and compare its rotate cost against a tight-stride frame of the same
/// content and geometry.
///
/// Run (from `example/`), screen on:
/// ```
/// flutter drive --driver=test_driver/integration_test.dart \
///   --target=integration_test/rotate_padding_isolated_pixel3_test.dart -d 8B1X11QLW --profile
/// ```
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('applyRotation() cost: tight-stride vs padded-stride synthetic input, same content', (tester) async {
    await YuvFfi.initialize();

    const width = 720;
    const height = 480;
    const paddedRowStride = 768; // matches the real Pixel 3 camera frame's Y plane bytesPerRow
    const chromaWidth = (width + 1) ~/ 2;
    const chromaHeight = (height + 1) ~/ 2;
    const paddedChromaRowStride = 768 ~/ 2; // proportionally padded, same 48-byte-per-720-cols ratio

    int deterministicByte(int index) => (index * 37 + 71) & 0xff;

    YuvImage buildTight() {
      final yBytes = Uint8List(width * height);
      for (var i = 0; i < yBytes.length; i++) {
        yBytes[i] = deterministicByte(i);
      }
      final uBytes = Uint8List(chromaWidth * chromaHeight);
      final vBytes = Uint8List(chromaWidth * chromaHeight);
      for (var i = 0; i < uBytes.length; i++) {
        uBytes[i] = deterministicByte(i + 1000);
        vBytes[i] = deterministicByte(i + 2000);
      }
      return YuvImage.i420(
        width,
        height,
        planes: [YuvPlane(height, width, 1, yBytes), YuvPlane(chromaHeight, chromaWidth, 1, uBytes), YuvPlane(chromaHeight, chromaWidth, 1, vBytes)],
      );
    }

    YuvImage buildPadded() {
      final yBytes = Uint8List(paddedRowStride * height);
      for (var row = 0; row < height; row++) {
        for (var col = 0; col < width; col++) {
          yBytes[row * paddedRowStride + col] = deterministicByte(row * width + col);
        }
      }
      final uBytes = Uint8List(paddedChromaRowStride * chromaHeight);
      final vBytes = Uint8List(paddedChromaRowStride * chromaHeight);
      for (var row = 0; row < chromaHeight; row++) {
        for (var col = 0; col < chromaWidth; col++) {
          uBytes[row * paddedChromaRowStride + col] = deterministicByte(row * chromaWidth + col + 1000);
          vBytes[row * paddedChromaRowStride + col] = deterministicByte(row * chromaWidth + col + 2000);
        }
      }
      return YuvImage.i420(
        width,
        height,
        planes: [
          YuvPlane(height, paddedRowStride, 1, yBytes),
          YuvPlane(chromaHeight, paddedChromaRowStride, 1, uBytes),
          YuvPlane(chromaHeight, paddedChromaRowStride, 1, vBytes),
        ],
      );
    }

    final tight = buildTight();
    final padded = buildPadded();
    final frequency = Stopwatch().frequency;
    const warmup = 5;
    const runs = 20;

    List<double> timeRotate(YuvImage source) {
      for (var i = 0; i < warmup; i++) {
        source.copy().applyRotation(YuvImageRotation.rotation270);
      }
      final samplesUs = <double>[];
      for (var i = 0; i < runs; i++) {
        final copy = source.copy();
        final sw = Stopwatch()..start();
        copy.applyRotation(YuvImageRotation.rotation270);
        sw.stop();
        samplesUs.add(sw.elapsedTicks * 1000000 / frequency);
      }
      samplesUs.sort();
      return samplesUs;
    }

    final tightSamples = timeRotate(tight);
    final paddedSamples = timeRotate(padded);

    debugPrint(
      jsonEncode({
        'card': 'rotate_padding_isolated_adhoc',
        'device': 'pixel3',
        'platform': Platform.operatingSystem,
        'tight_y_bytes_per_row': tight.yPlane.bytesPerRow,
        'padded_y_bytes_per_row': padded.yPlane.bytesPerRow,
        'tight_median_ms': tightSamples[tightSamples.length ~/ 2] / 1000,
        'padded_median_ms': paddedSamples[paddedSamples.length ~/ 2] / 1000,
      }),
    );

    expect(tightSamples, isNotEmpty);
    expect(paddedSamples, isNotEmpty);
  });
}
