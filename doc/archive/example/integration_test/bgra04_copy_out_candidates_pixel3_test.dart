import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// BGRA-04: Pixel 3 counterpart of the copy-out candidate comparison in
/// `speed_00_dart_ffi/test/bgra04_copy_out_bench_test.dart`.
///
/// ## Why this file exists, and why it differs from
/// `bgra04_copy_out_pixel3_test.dart`
///
/// `bgra04_copy_out_pixel3_test.dart`'s file doc explains why it could not
/// reach `YuvAbiV1Runner._copyDestinationPlanes` directly: that internal type
/// is not exported from `package:yuv_ffi`, and swapping in each candidate
/// requires access to its source, not just its result. That reasoning is
/// still correct for a same-call-site A/B (comparing candidates *inside* a
/// live `convert()` call).
///
/// It does not, however, block reproducing what the Windows bench file
/// actually measures: none of `bgra04_copy_out_bench_test.dart`'s four
/// candidates call `YuvAbiV1Runner` at all. Every candidate there allocates
/// its own raw `Pointer<Uint8>` via `package:ffi`'s `malloc` and times a copy
/// out of it -- it is a `dart:ffi`/`package:ffi` micro-benchmark that never
/// touches `package:yuv_ffi`'s internals. `dart:ffi` and `package:ffi` are
/// ordinary Dart packages, reachable from any Dart code (including this
/// example app) without exporting anything from `yuv_ffi`'s `src/`. This
/// file ports that exact micro-benchmark to run on-device, so it measures
/// real ARM64/AOT (via `flutter drive --profile`) copy-out candidate costs,
/// not a Windows-only approximation.
///
/// What this file does **not** claim: it does not prove which candidate
/// `YuvAbiV1Runner._copyDestinationPlanes` uses in production is fastest
/// *inside that call* on this device -- only that, for a raw native buffer of
/// the same sizes/scenarios, candidate A (production's choice) is or is not
/// measurably slower than B/C/D on this hardware. That is the same scope the
/// Windows bench file has: an isolated copy-out comparison, not a full-call
/// breakdown.
///
/// ## Screen-state requirement
///
/// The independent review found `Awake` vs `Dozing` produces a 4x difference
/// on this device. This test asserts `mWakefulness`/`mScreenOn` are not
/// checked from Dart (not reachable without a platform channel this task is
/// not scoped to add), so the *runner* is responsible for recording
/// `adb shell dumpsys power | grep -E "mWakefulness|mScreenOn"` immediately
/// before and during the `flutter drive` invocation, and keeping the screen
/// on and the keyguard dismissed throughout. The JSON emitted below carries a
/// `device_state_note` field as a standing reminder for whoever reads the
/// output without the surrounding runner log.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const warmup = 5;
  const runs = 30;
  const fnvBasis = 0xcbf29ce484222325;
  const fnvPrime = 0x100000001b3;
  const mask64 = 0xffffffffffffffff;

  int checksum(Uint8List plane) {
    var hash = fnvBasis;
    for (final value in plane) {
      hash = ((hash ^ value) * fnvPrime) & mask64;
    }
    return hash;
  }

  void runScenario(String label, int width, int height, int rowStrideBytes) {
    final int length = rowStrideBytes * height;
    final Pointer<Uint8> native = malloc<Uint8>(length);
    try {
      final Uint8List seed = Uint8List.fromList(List<int>.generate(length, (i) => (i * 41 + 7) & 255));
      native.asTypedList(length).setAll(0, seed);
      final int expectedHash = checksum(seed);

      final candidates = <String, Uint8List Function()>{
        'A_fromList_asTypedList': () => Uint8List.fromList(native.asTypedList(length)),
        'B_sized_setAll': () => Uint8List(length)..setAll(0, native.asTypedList(length)),
        'C_sublistView_copy': () => Uint8List.fromList(Uint8List.sublistView(native.asTypedList(length))),
        'D_bytebuffer_sublist': () => (native.asTypedList(length).buffer.asUint8List(native.asTypedList(length).offsetInBytes, length)).sublist(0),
      };

      for (final entry in candidates.entries) {
        final samplesUs = <double>[];
        late Uint8List last;

        for (var i = 0; i < warmup; i++) {
          entry.value();
        }
        for (var i = 0; i < runs; i++) {
          final sw = Stopwatch()..start();
          last = entry.value();
          sw.stop();
          samplesUs.add(sw.elapsedTicks * 1000000 / sw.frequency);
          expect(checksum(last), expectedHash, reason: '$label ${entry.key}: byte mismatch at run $i');
        }

        // Independence check, same as the Windows bench: mutating the native
        // buffer after copy must never change the already-returned result.
        final int before = last[0];
        native.asTypedList(length)[0] = (native.asTypedList(length)[0] + 1) & 255;
        expect(last[0], before, reason: '$label ${entry.key}: result changed after native buffer mutation -- not independent');
        native.asTypedList(length)[0] = seed[0];

        final sorted = samplesUs.toList()..sort();
        final medianUs = sorted[sorted.length ~/ 2];
        debugPrint(
          jsonEncode({
            'card': 'BGRA-04',
            'device': 'pixel3',
            'scenario': label,
            'candidate': entry.key,
            'length_bytes': length,
            'n': samplesUs.length,
            'median_ms': medianUs / 1000,
            'min_ms': sorted.first / 1000,
            'max_ms': sorted.last / 1000,
            'checksum_fnv1a64': expectedHash,
            'device_state_note': 'Valid only if the device was Awake/screen-on/keyguard-dismissed for the whole run; see BGRA-00 review addendum.',
          }),
        );
      }
    } finally {
      malloc.free(native);
    }
  }

  testWidgets('BGRA-04 Pixel 3 copy-out candidates A/B/C/D: tight/padded/ROI', (tester) async {
    // Same three scenarios as speed_00_dart_ffi/test/bgra04_copy_out_bench_test.dart.
    runScenario('tight-1080p', 1920, 1080, 1920 * 4);
    runScenario('padded-1080p', 1920, 1080, 1920 * 4 + 256);
    runScenario('roi-256', 256, 256, 256 * 4);
  });
}
