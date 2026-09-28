import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

import 'helpers/bgra_round_trip_oracle.dart';

/// BGRA-04: Pixel 3 720x360 approximation of the copy-out investigation in
/// `test/bgra04_copy_out_test.dart` and
/// `speed_00_dart_ffi/test/bgra04_copy_out_bench_test.dart`.
///
/// ## Why this cannot repeat the copy-out candidate comparison
///
/// The Windows/Dart-VM copy-out investigation compares four candidate ways
/// to copy a native destination `Pointer<Uint8>` buffer into a Dart-owned
/// `Uint8List` (`A_fromList_asTypedList`, `B_sized_setAll`,
/// `C_sublistView_copy`, `D_bytebuffer_sublist` in
/// `bgra04_copy_out_bench_test.dart`) by allocating a raw `package:ffi`
/// buffer directly and timing each candidate's copy of it in isolation. That
/// requires:
///
/// - a raw native pointer to copy from, which only exists inside
///   `YuvAbiV1Runner._run` (`_copyDestinationPlanes`,
///   `lib/src/yuv/impl/io/abi/yuv_abi_v1_runner.dart`) or a standalone
///   `dart:ffi` harness that opens the library directly, and
/// - the ability to swap in a different copy implementation for the same
///   call, which only exists in that internal runner's source.
///
/// Neither is reachable from `import 'package:yuv_ffi/yuv_ffi.dart'`:
/// `YuvAbiV1Runner` is not exported (see the longer explanation in
/// `bgra00_stage_breakdown_pixel3_test.dart`'s file doc, which applies
/// identically here), and the copy-out step it performs is not a separate
/// public call -- `toBgraBytes()`/`toBgra()` run staging, destination
/// alloc, the native kernel call, and copy-out as one indivisible sequence.
/// There is exactly one copy-out implementation reachable from here (the one
/// production actually uses), so there is nothing to compare it against
/// through this API: this file cannot become a 4-way candidate comparison
/// without either exporting an internal class or duplicating
/// `_copyDestinationPlanes`'s four candidates as new example-app code that
/// would call raw FFI itself -- both out of scope for a measurement-only
/// task that is not supposed to touch `lib/`.
///
/// ## What this file does measure
///
/// The same `toBgraBytes()` full public call already measured in
/// `bgra00_stage_breakdown_pixel3_test.dart`, at the same 720x360 geometry,
/// reported here under the BGRA-04 card as an explicit **approximation**:
/// copy-out was measured on Windows at ~7% of the full call
/// (`doc/perf/results/bgra00_stage_breakdown_windows_1080p_2026-09-26.md`),
/// so full_call is a very loose upper bound on copy-out's own Pixel 3 cost,
/// not a stand-in for it. Treat this file's numbers as "no regression in the
/// call that contains copy-out", not as "copy-out's Pixel 3 share is now
/// known" -- the latter still requires the internal-access harness described
/// above.
///
/// Results are printed as one JSON object per line via `debugPrint()`,
/// following `native_app_runtime_smoke_test.dart`'s convention, surfaced on
/// the host console through
/// `flutter drive --driver=test_driver/integration_test.dart` (this
/// project's established Android run pattern).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const width = 720;
  const height = 360;
  const warmup = 5;
  const runs = 30;

  testWidgets('BGRA-04 Pixel 3 720x360: toBgraBytes() full_call approximation for NV12/I420 -> BGRA', (tester) async {
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

      final sorted = samplesUs.toList()..sort();
      final medianUs = sorted[sorted.length ~/ 2];
      debugPrint(
        jsonEncode({
          'card': 'BGRA-04',
          'device': 'pixel3',
          'pair': '${source.label}->BGRA',
          'stage': 'full_call_toBgraBytes_approximation',
          'width': width,
          'height': height,
          'n': samplesUs.length,
          'median_ms': medianUs / 1000,
          'min_ms': sorted.first / 1000,
          'max_ms': sorted.last / 1000,
          'checksum_sha256': expectedHash,
        }),
      );
    }

    debugPrint(
      jsonEncode({
        'card': 'BGRA-04',
        'device': 'pixel3',
        'note':
            'copy-out is not separately measurable through the public YuvFfi/YuvImage API -- '
            'see file-level doc comment for why. full_call is reported as a loose upper-bound '
            'approximation only, not a copy-out measurement.',
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

/// Same deterministic RGBA generator as
/// `bgra00_stage_breakdown_pixel3_test.dart`, kept identical so both files'
/// numbers describe the same input if compared side by side.
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
