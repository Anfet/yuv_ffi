import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

import 'helpers/bgra_round_trip_oracle.dart';

/// BGRA-00: Pixel 3 720x360 counterpart of the Windows Dart-VM/JIT stage
/// breakdown in
/// doc/perf/results/bgra00_stage_breakdown_windows_1080p_2026-09-26.md and
/// speed_00_dart_ffi/test/yuv_convert_v1_bgra_stages_test.dart.
///
/// ## Why this is not a 4-stage breakdown
///
/// The Windows methodology times four internal steps of
/// `YuvAbiV1Runner._run` separately: input staging (`_allocateConstFrame`),
/// destination allocation/zero-fill (`_allocateMutableFrame`), the
/// `yuv_convert_v1` native call alone, and copy-out
/// (`_copyDestinationPlanes`). It can do that because
/// `speed_00_dart_ffi/test/yuv_convert_v1_bgra_stages_test.dart` is a
/// standalone Dart VM test that opens `yuv_ffi.dll` directly via `dart:ffi`
/// and drives the ABI v1 struct layout itself -- it never goes through
/// `package:yuv_ffi`, so it is free to allocate/call/copy each stage in
/// isolation.
///
/// That is not available here. This file is an `integration_test` running
/// inside the built example app on-device, restricted to
/// `import 'package:yuv_ffi/yuv_ffi.dart'` (the task's own constraint, and
/// the only way to exercise the real Android packaging/loading path -- see
/// `native_app_runtime_smoke_test.dart`'s rationale for why an app-runtime
/// integration test exists at all). Every internal type the Windows stages
/// test reaches directly is unexported from the public library:
///
/// - `YuvAbiV1Runner` (`lib/src/yuv/impl/io/abi/yuv_abi_v1_runner.dart`),
///   whose `convert()` is the only place that runs staging (step 2),
///   destination alloc/zero-fill (step 3), the native call (step 5), and
///   copy-out (step 7) as separately identifiable steps. `lib/yuv_ffi.dart`
///   exports none of `src/yuv/impl/io/**`.
/// - The raw ABI v1 struct layout (`YuvConstFrameV1`, `YuvMutableFrameV1`,
///   `YuvConvertOptionsV1`) and the generated `yuv_convert_v1` binding
///   (`lib/src/functions/bindings/yuv_ffi_bingings.dart`), which AGENTS.md
///   marks generated/protected and which this package does not export
///   either.
///
/// `YuvImage.toBgraBytes()`/`toBgra()` are the only entry points the public
/// surface exposes, and they run all four internal steps as one call with no
/// hook to time a step in isolation. So this file measures exactly one
/// stage: **full_call**, i.e. the whole `toBgraBytes()`/`toBgra()` public
/// call, which is the sum of the four Windows-report stages plus whatever
/// Dart-side overhead sits above `YuvAbiV1Runner._run` (argument validation,
/// capability gating). It cannot attribute time to staging, dest_alloc,
/// kernel, or copy_out individually on this device without either exporting
/// an internal class (out of scope: this is a measurement task, not an API
/// change) or adding a new internal benchmarking hook to the package (also
/// out of scope for the same reason). Whoever picks up a native-kernel-only
/// Pixel 3 number should instead look at
/// `speed_00_dart_ffi/test/yuv_convert_v1_bgra_stages_test.dart` and ask
/// whether an Android cross-compiled `dart:ffi` runner (not this
/// `integration_test`) can reach the on-device `.so` the way the Windows
/// version reaches `yuv_ffi.dll` -- that is a different harness, not a
/// variant of this file.
///
/// ## What this file does measure
///
/// `toBgraBytes()` and `toBgra()` for both NV12->BGRA and I420->BGRA, at
/// 720x360 -- the todo.md-specified Pixel 3 geometry -- on a deterministic
/// synthetic input, with a warm-up phase and N=30 timed samples per
/// pair/call, exactly as the Windows stages test does for its own
/// `full_call`/`toBgra_full_call` rows. Every timed run's output is checked
/// against an independent pure-Dart BT.601 round-trip oracle via SHA-256
/// (`helpers/bgra_round_trip_oracle.dart` -- RGBA->YUV 4:2:0 encode, then
/// YUV->BGRA decode, replicating `yuv_convert_from_packed`/
/// `yuv_convert_to_bgra` exactly; a naive RGBA<->BGRA byte permutation is
/// **not** a valid oracle here, see that file's doc comment for why), so a
/// byte-exact regression would fail the test rather than silently reporting
/// a bogus timing.
///
/// Results are printed as one JSON object per line via `debugPrint()`
/// (`native_app_runtime_smoke_test.dart`'s convention), which
/// `flutter drive --driver=test_driver/integration_test.dart` (this
/// project's established Android run pattern -- see `.github/workflows/ci.yml`
/// and `example/test_driver/integration_test.dart`) surfaces on the host
/// console.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const width = 720;
  const height = 360;
  const warmup = 5;
  const runs = 30;

  testWidgets('BGRA-00 Pixel 3 720x360: toBgraBytes()/toBgra() full_call for NV12/I420 -> BGRA', (tester) async {
    await YuvFfi.initialize();

    for (final source in _SourceFormat.values) {
      final rgba = _deterministicRgba(width, height);
      final expectedBgra = oracleRgbaThroughYuv420ToBgra(rgba, width, height);
      final expectedHash = sha256.convert(expectedBgra).toString();

      // toBgraBytes(): the raw bytes call, directly comparable to the
      // Windows report's full_call row.
      final bytesSamples = <double>[];
      // toBgra(): the same conversion plus wrapping the result into a public
      // YuvImage, directly comparable to the Windows report's
      // toBgra_full_call row.
      final imageSamples = <double>[];

      Uint8List runToBgraBytes() {
        final image = _buildSourceImage(source, width, height)..applyRgbaBytes(rgba);
        return image.toBgraBytes();
      }

      YuvImage runToBgra() {
        final image = _buildSourceImage(source, width, height)..applyRgbaBytes(rgba);
        return image.toBgra();
      }

      for (var i = 0; i < warmup; i++) {
        runToBgraBytes();
        runToBgra();
      }

      for (var i = 0; i < runs; i++) {
        final sw = Stopwatch()..start();
        final bytes = runToBgraBytes();
        sw.stop();
        bytesSamples.add(sw.elapsedTicks * 1000000 / sw.frequency);

        final actualHash = sha256.convert(bytes).toString();
        expect(actualHash, expectedHash, reason: '${source.label}->BGRA toBgraBytes() byte mismatch at run $i');
      }

      for (var i = 0; i < runs; i++) {
        final sw = Stopwatch()..start();
        final image = runToBgra();
        sw.stop();
        imageSamples.add(sw.elapsedTicks * 1000000 / sw.frequency);

        final actualHash = sha256.convert(image.toBgraBytes()).toString();
        expect(actualHash, expectedHash, reason: '${source.label}->BGRA toBgra() byte mismatch at run $i');
      }

      _report(
        pair: '${source.label}->BGRA',
        stage: 'full_call_toBgraBytes',
        width: width,
        height: height,
        samplesUs: bytesSamples,
        checksum: expectedHash,
      );
      _report(
        pair: '${source.label}->BGRA',
        stage: 'full_call_toBgra',
        width: width,
        height: height,
        samplesUs: imageSamples,
        checksum: expectedHash,
      );
    }

    debugPrint(
      jsonEncode({
        'card': 'BGRA-00',
        'device': 'pixel3',
        'note':
            'staging/dest_alloc/kernel/copy_out are not separately measurable through the public '
            'YuvFfi/YuvImage API -- see file-level doc comment for why. Only full_call '
            '(toBgraBytes()/toBgra()) is reported.',
      }),
    );
  });
}

enum _SourceFormat {
  nv12('NV12'),
  i420('I420');

  const _SourceFormat(this.label);
  final String label;
}

YuvImage _buildSourceImage(_SourceFormat format, int width, int height) => switch (format) {
  _SourceFormat.nv12 => YuvImage.nv12(width, height),
  _SourceFormat.i420 => YuvImage.i420(width, height),
};

/// A fixed, non-uniform RGBA source: the same per-pixel formula style as
/// `native_app_runtime_smoke_test.dart`, extended to arbitrary width/height
/// so a backend that returned zeroes, or a wrong-format echo, cannot pass by
/// coincidence.
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
  required String pair,
  required String stage,
  required int width,
  required int height,
  required List<double> samplesUs,
  required String checksum,
}) {
  final sorted = samplesUs.toList()..sort();
  final medianUs = sorted[sorted.length ~/ 2];
  debugPrint(
    jsonEncode({
      'card': 'BGRA-00',
      'device': 'pixel3',
      'pair': pair,
      'stage': stage,
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
