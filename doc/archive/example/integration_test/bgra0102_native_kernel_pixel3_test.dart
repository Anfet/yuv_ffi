import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

import 'helpers/bgra_round_trip_oracle.dart';

/// Pixel 3 benchmark for the public NV12/I420 `toBgraBytes()` call.
///
/// The source frame and independent BT.601 oracle are prepared before timing;
/// each sample measures only the conversion call. The result is checked after
/// the stopwatch stops. Run this same file from separate git worktrees at the
/// commits immediately before and after each native optimization to attribute
/// a speed difference to BGRA-01 or BGRA-02. This public call includes Dart
/// staging, destination allocation, the native kernel, and copy-out; the
/// Windows direct-FFI runner measures the C kernel separately.
///
/// Keep the Pixel 3 awake with its screen on and keyguard dismissed throughout
/// each run. The host must record those states because this test cannot read
/// them without adding a platform channel.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const width = 720;
  const height = 360;
  const warmup = 5;
  const runs = 30;

  testWidgets('BGRA-01/BGRA-02 Pixel 3 720x360: toBgraBytes() native kernel confirmation for NV12/I420 -> BGRA', (tester) async {
    await YuvFfi.initialize();

    for (final source in _SourceFormat.values) {
      final rgba = _deterministicRgba(width, height);
      final expectedBgra = oracleRgbaThroughYuv420ToBgra(rgba, width, height);
      final expectedHash = sha256.convert(expectedBgra).toString();
      final image = _buildSourceImage(source, width, height)..applyRgbaBytes(rgba);

      final samplesUs = <double>[];

      Uint8List runToBgraBytes() => image.toBgraBytes();

      for (var i = 0; i < warmup; i++) {
        runToBgraBytes();
      }

      for (var i = 0; i < runs; i++) {
        final sw = Stopwatch()..start();
        final bytes = runToBgraBytes();
        sw.stop();
        samplesUs.add(sw.elapsedTicks * 1000000 / sw.frequency);

        final actualHash = sha256.convert(bytes).toString();
        expect(actualHash, expectedHash, reason: '${source.label}->BGRA toBgraBytes() byte mismatch at run $i');
      }

      _report(card: source.card, pair: '${source.label}->BGRA', width: width, height: height, samplesUs: samplesUs, checksum: expectedHash);
    }

    debugPrint(
      jsonEncode({
        'device': 'pixel3',
        'note':
            'Measures only public toBgraBytes() on this build. Compare output from adjacent commits '
            'for a per-card before/after result; the source frame is prepared outside the stopwatch.',
      }),
    );
  });
}

enum _SourceFormat {
  nv12('NV12', 'BGRA-01'),
  i420('I420', 'BGRA-02');

  const _SourceFormat(this.label, this.card);
  final String label;
  final String card;
}

YuvImage _buildSourceImage(_SourceFormat format, int width, int height) => switch (format) {
  _SourceFormat.nv12 => YuvImage.nv12(width, height),
  _SourceFormat.i420 => YuvImage.i420(width, height),
};

/// A fixed, non-uniform RGBA source: the same per-pixel formula style as
/// `bgra00_stage_breakdown_pixel3_test.dart`, so a backend that returned
/// zeroes, or a wrong-format echo, cannot pass by coincidence.
Uint8List _deterministicRgba(int width, int height) {
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
  return rgba;
}

void _report({
  required String card,
  required String pair,
  required int width,
  required int height,
  required List<double> samplesUs,
  required String checksum,
}) {
  final sorted = samplesUs.toList()..sort();
  final medianUs = sorted[sorted.length ~/ 2];
  debugPrint(
    jsonEncode({
      'card': card,
      'device': 'pixel3',
      'pair': pair,
      'stage': 'full_call_toBgraBytes',
      'width': width,
      'height': height,
      'n': samplesUs.length,
      'median_ms': medianUs / 1000,
      'min_ms': sorted.first / 1000,
      'max_ms': sorted.last / 1000,
      'raw_ms': samplesUs.map((sampleUs) => sampleUs / 1000).toList(),
      'checksum_sha256': checksum,
    }),
  );
}
