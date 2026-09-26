import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

import 'helpers/bgra_round_trip_oracle.dart';

/// Pixel 3 720x360 confirmation for the already-accepted native fast paths in
/// `src/yuv/abi/yuv_convert_v1.c`: `yuv_convert_nv12_to_bgra` (BGRA-01) and
/// `yuv_convert_i420_to_bgra` (BGRA-02). Both are already present on this
/// HEAD -- this file does not add, gate, or toggle either optimization.
///
/// ## What "measured" means here, and what it does not mean
///
/// todo.md's own methodology (see its "Правила для каждой задачи" section)
/// wants baseline vs. candidate compared on identical data/size/device/build.
/// BGRA-01/02's Windows Executor Report did exactly that by building two
/// separate DLLs (baseline commit `867355b`, candidate commit `0f29bc9`) and
/// diffing `yuv_convert_v1_test.dart`/the stages runner between them. That
/// comparison is **not** reproduced here, on purpose:
///
/// - Both optimizations are already merged into this branch's only C source.
///   There is no unaccelerated build on this checkout to compare against, so
///   there is nothing for an `integration_test` running against the built
///   example app to diff against on-device.
/// - Reproducing the Windows baseline/candidate protocol on Pixel 3 would mean
///   checking out the pre-BGRA-01 commit into a second `git worktree`,
///   cross-building a second `.so` for Android, and installing a second APK
///   next to this one -- entirely outside what a `flutter drive`
///   `integration_test` file can do (it drives one already-built app, not
///   `git`/Gradle/NDK toolchains). That is a real gap, not one this file
///   papers over: if a genuine Pixel 3 before/after number is needed, it is a
///   separate task built around a second worktree and a second APK install,
///   not a variant of this file. Flagging it here rather than silently
///   omitting it.
/// - What an `integration_test` on this device *can* do, and what this file
///   does: confirm that the current (already accelerated) native code is
///   still byte-exact correct against an independent oracle, and record its
///   wall-clock time on real Pixel 3 hardware at the todo.md-specified
///   720x360 geometry, so the accepted C change has at least one real-device
///   number attached to it instead of Windows-only measurements.
///
/// ## Why this is not an isolated C-kernel benchmark either
///
/// Same constraint `bgra00_stage_breakdown_pixel3_test.dart` documents:
/// `YuvAbiV1Runner`, the raw ABI v1 struct layout, and the generated
/// `yuv_convert_v1` binding are all internal to `package:yuv_ffi` and are not
/// reachable from `import 'package:yuv_ffi/yuv_ffi.dart'`, which is what an
/// app-runtime `integration_test` is restricted to (and the only way to
/// exercise the real Android packaging/loading path). So this file cannot
/// isolate the native kernel call the way
/// `speed_00_dart_ffi/test/yuv_convert_v1_bgra_stages_test.dart` does on
/// Windows via direct `dart:ffi` `DynamicLibrary` loading of `yuv_ffi.dll`.
/// There is no equivalent standalone `dart:ffi` runner for the on-device
/// `.so` on Android reachable from this harness, so what follows measures the
/// whole public `toBgraBytes()` call (Dart staging + FFI + native convert +
/// copy-out), not the isolated `yuv_convert_nv12_to_bgra`/
/// `yuv_convert_i420_to_bgra` C functions alone. Whoever wants an
/// Android-side isolated C-kernel number should look at whether an Android
/// cross-compiled `dart:ffi` runner (a different harness, not a variant of
/// this file) can reach the on-device `.so` the way the Windows runner reaches
/// `yuv_ffi.dll` directly.
///
/// ## What this file does measure
///
/// `toBgraBytes()` for NV12->BGRA (exercises `yuv_convert_nv12_to_bgra`,
/// BGRA-01) and I420->BGRA (exercises `yuv_convert_i420_to_bgra`, BGRA-02),
/// at 720x360 -- the todo.md-specified Pixel 3 geometry -- on a deterministic
/// synthetic input, with a 5-run warm-up and N=30 timed `Stopwatch` samples
/// per pair, the same protocol `bgra00_stage_breakdown_pixel3_test.dart` uses
/// for its own `full_call` rows. Every timed run's output is checked against
/// the same independent pure-Dart BT.601 round-trip oracle via SHA-256
/// (`helpers/bgra_round_trip_oracle.dart` -- RGBA->YUV 4:2:0 encode, then
/// YUV->BGRA decode, replicating `yuv_convert_from_packed`/
/// `yuv_convert_to_bgra` exactly; see that file's doc comment for why a naive
/// RGBA<->BGRA byte permutation is not a valid oracle here), so a byte-exact
/// regression in either accelerated path would fail the test rather than
/// silently reporting a bogus timing.
///
/// Results are printed as one JSON object per line via `debugPrint()`
/// (`bgra00_stage_breakdown_pixel3_test.dart`'s convention), which
/// `flutter drive --driver=test_driver/integration_test.dart` surfaces on the
/// host console.
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

      final samplesUs = <double>[];

      Uint8List runToBgraBytes() {
        final image = _buildSourceImage(source, width, height)..applyRgbaBytes(rgba);
        return image.toBgraBytes();
      }

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
            'Confirms the already-accepted native fast paths (yuv_convert_nv12_to_bgra / '
            'yuv_convert_i420_to_bgra in src/yuv/abi/yuv_convert_v1.c) on real hardware via the public '
            'toBgraBytes() call; this is not an isolated C-kernel benchmark and not a baseline-vs-candidate '
            'comparison on this device -- see file-level doc comment for why both are out of scope here.',
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
      'checksum_sha256': checksum,
    }),
  );
}
