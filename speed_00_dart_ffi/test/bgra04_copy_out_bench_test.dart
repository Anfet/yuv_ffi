import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

// BGRA-04: isolates the copy-out stage BGRA-00 measured as ~7% of the full
// toBgraBytes()/toBgra() call on a tight/unpadded 1080p input (after OPT-14's
// row-copy fast path was already applied to _seedPlaneFromSource/applyTo --
// this stage is `_copyDestinationPlanes`, which OPT-14 did NOT touch). This
// runner compares candidate ways to copy a native destination buffer into a
// Dart-owned Uint8List, on three scenarios BGRA-00 recommended checking
// before closing the card with a negative result:
//   1. tight 1920x1080 BGRA (same as BGRA-00/03's input),
//   2. row-padded 1920x1080 BGRA (rowStride > width*4, as convert() never
//      produces, but other operations' destinations legitimately can),
//   3. ROI/crop-sized small destination (crop output is itself tight, but
//      much smaller than the full frame -- the plausible "ROI copy-out"
//      analogue for this stage, since yuv_convert_v1 has no ROI option).
//
// Candidates, all producing an independent Dart-owned Uint8List (never a
// view over native memory -- see "why zero-copy is out of scope" below):
//   A. baseline:      Uint8List.fromList(ptr.asTypedList(len))       (current production code)
//   B. sized-copy:    Uint8List(len)..setAll(0, ptr.asTypedList(len))
//   C. sublistView:   Uint8List.sublistView(ptr.asTypedList(len))    (still a *view* over the
//                      typed-data-over-native-memory instance -- copied immediately below to
//                      keep the same independence contract; measured to see whether the
//                      intermediate view construction itself costs anything)
//   D. buffer-copy:   (ptr.asTypedList(len).buffer.asUint8List()).sublist(0) style copy through
//                      a raw ByteBuffer view
//
// Zero-copy/view-sharing candidates that would let the returned Uint8List
// alias the native buffer are deliberately NOT included: the native buffer
// is freed in `YuvAbiV1Runner._run`'s `finally` immediately after this copy,
// so any returned view would be a use-after-free the moment the caller reads
// it after the next `convert()`/`toBgraBytes()` call reuses that address.
// That would break the "result is independent of the source/native buffer"
// contract BGRA-04 explicitly must preserve -- see independence test in
// test/bgra04_copy_out_test.dart.
const _tightWidth = 1920;
const _tightHeight = 1080;
const _paddedWidth = 1920;
const _paddedHeight = 1080;
const _paddedRowStrideBytes = _paddedWidth * 4 + 256; // extra row padding, as a padded BGRA destination would have
const _roiWidth = 256;
const _roiHeight = 256;
const _warmup = 5;
const _runs = 30;
const _fnvBasis = 0xcbf29ce484222325;
const _fnvPrime = 0x100000001b3;
const _mask64 = 0xffffffffffffffff;

void main() {
  group('BGRA-04 copy-out candidates', () {
    test('tight 1920x1080 BGRA', () {
      _runScenario('tight-1080p', _tightWidth, _tightHeight, _tightWidth * 4);
    });

    test('row-padded 1920x1080 BGRA (rowStride > width*4)', () {
      _runScenario('padded-1080p', _paddedWidth, _paddedHeight, _paddedRowStrideBytes);
    });

    test('ROI/crop-sized 256x256 BGRA', () {
      _runScenario('roi-256', _roiWidth, _roiHeight, _roiWidth * 4);
    });
  });
}

void _runScenario(String label, int width, int height, int rowStrideBytes) {
  final int length = rowStrideBytes * height;
  final Pointer<Uint8> native = malloc<Uint8>(length);
  try {
    final Uint8List seed = Uint8List.fromList(List<int>.generate(length, (i) => (i * 41 + 7) & 255));
    native.asTypedList(length).setAll(0, seed);
    final int expectedHash = _checksum(seed);

    final candidates = <String, Uint8List Function()>{
      'A_fromList_asTypedList': () => Uint8List.fromList(native.asTypedList(length)),
      'B_sized_setAll': () => Uint8List(length)..setAll(0, native.asTypedList(length)),
      'C_sublistView_copy': () => Uint8List.fromList(Uint8List.sublistView(native.asTypedList(length))),
      'D_bytebuffer_sublist': () => (native.asTypedList(length).buffer.asUint8List(native.asTypedList(length).offsetInBytes, length)).sublist(0),
    };

    for (final entry in candidates.entries) {
      final samples = <double>[];
      late Uint8List last;

      for (var i = 0; i < _warmup; i++) {
        entry.value();
      }
      for (var i = 0; i < _runs; i++) {
        final sw = Stopwatch()..start();
        last = entry.value();
        sw.stop();
        samples.add(sw.elapsedTicks * 1000000 / sw.frequency);
        final hash = _checksum(last);
        if (hash != expectedHash) fail('$label ${entry.key} byte mismatch at run $i');
      }

      final sorted = samples.toList()..sort();
      final median = sorted[sorted.length ~/ 2];
      print(
        'BGRA-04 $label ${entry.key} len=$length: median=${(median / 1000).toStringAsFixed(4)} ms '
        'min=${(sorted.first / 1000).toStringAsFixed(4)} ms max=${(sorted.last / 1000).toStringAsFixed(4)} ms '
        'n=${samples.length}',
      );

      // Independence check: mutate the native buffer after copy, candidate result must be unaffected.
      final int before = last[0];
      native.asTypedList(length)[0] = (native.asTypedList(length)[0] + 1) & 255;
      expect(last[0], before, reason: '$label ${entry.key}: result changed after native buffer mutation -- not independent');
      native.asTypedList(length)[0] = seed[0]; // restore for next candidate
    }
    print('BGRA-04 $label checksum=0x${_hex64(expectedHash)}');
  } finally {
    malloc.free(native);
  }
}

int _checksum(Uint8List plane) {
  var hash = _fnvBasis;
  for (final value in plane) {
    hash = ((hash ^ value) * _fnvPrime) & _mask64;
  }
  return hash;
}

String _hex64(int value) {
  final high = (value >> 32) & 0xffffffff;
  final low = value & 0xffffffff;
  return '${high.toRadixString(16).padLeft(8, '0')}${low.toRadixString(16).padLeft(8, '0')}';
}
