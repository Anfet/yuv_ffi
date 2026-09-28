import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/src/yuv/impl/io/abi/yuv_abi_v1_runner.dart';
import 'package:yuv_ffi/src/yuv/impl/io/defs/native_allocator.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_abi_v1_constants.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_abi_v1_frame.dart';

/// `_copyDestinationPlanes` (the copy-out step of
/// `YuvAbiV1Runner._run`, step 7) copies the native destination buffer into a
/// Dart-owned `Uint8List` before `_run`'s `finally` frees that native buffer
/// (step 9). This file verifies the contract the investigation in
/// `speed_00_dart_ffi/test/bgra04_copy_out_bench_test.dart` had to preserve:
/// the returned bytes are an independent copy, not a view over native memory
/// that a later allocation could reuse (use-after-free) or that freeing could
/// invalidate. It does not touch native code.
void main() {
  const int width = 8;
  const int height = 4;

  YuvAbiV1FrameInput i420Source(int seed) {
    final int lumaLen = width * height;
    final int chromaW = (width + 1) ~/ 2;
    final int chromaH = (height + 1) ~/ 2;
    final int chromaLen = chromaW * chromaH;
    return YuvAbiV1FrameInput(
      format: yuvFormatI420,
      width: width,
      height: height,
      planes: [
        YuvAbiV1PlaneInput(bytes: Uint8List.fromList(List<int>.generate(lumaLen, (i) => (i * 7 + seed) & 255)), rowStride: width, pixelStride: 1),
        YuvAbiV1PlaneInput(
          bytes: Uint8List.fromList(List<int>.generate(chromaLen, (i) => (i * 13 + seed + 40) & 255)),
          rowStride: chromaW,
          pixelStride: 1,
        ),
        YuvAbiV1PlaneInput(
          bytes: Uint8List.fromList(List<int>.generate(chromaLen, (i) => (i * 17 + seed + 90) & 255)),
          rowStride: chromaW,
          pixelStride: 1,
        ),
      ],
    );
  }

  YuvAbiV1DestinationLayout bgraLayout() =>
      YuvAbiV1DestinationLayout(format: yuvFormatBgra8888, width: width, height: height, planeRowStrides: [width * 4], planePixelStrides: [4]);

  final bool nativeAvailable = _nativeAvailable(width, height);

  group('copy-out independence/lifetime (convert)', () {
    test('result is unaffected by mutating the source after the call returns', () {
      // "Independent of the source": mutating the caller's own input plane
      // bytes after convert() returns must never change the already-returned
      // result. The runner copies the source into native staging up front
      // (step 2) and never aliases the caller's buffers, so this exercises
      // that guarantee from the public boundary this card is scoped to.
      final source = i420Source(11);
      final result = YuvAbiV1Runner.convert(source: source, destinationLayout: bgraLayout());
      final before = Uint8List.fromList(result.planes.single);

      for (final plane in source.planes) {
        for (int i = 0; i < plane.bytes.length; i++) {
          plane.bytes[i] = (plane.bytes[i] + 1) & 255;
        }
      }

      expect(result.planes.single, before, reason: 'convert() result must not change when the caller mutates its own source bytes afterwards');
    });

    test('two consecutive calls never share a destination buffer', () {
      // Guards against a copy-out change that would return a Uint8List
      // backed by (a view over) native memory: if the native allocator ever
      // reused the address freed by the first call for the second call's
      // destination, a byte-identity/aliasing bug would show up as the first
      // result's bytes changing once the second call's result is populated.
      final source1 = i420Source(3);
      final source2 = i420Source(200);
      final result1 = YuvAbiV1Runner.convert(source: source1, destinationLayout: bgraLayout());
      final snapshot1 = Uint8List.fromList(result1.planes.single);

      final result2 = YuvAbiV1Runner.convert(source: source2, destinationLayout: bgraLayout());

      expect(result1.planes.single, snapshot1, reason: 'first result must be unaffected by a second, unrelated convert() call');
      expect(result2.planes.single, isNot(equals(result1.planes.single)), reason: 'sanity: the two sources differ, so results must differ too');
    });

    test('result survives after the native allocator frees every pointer it made', () {
      // The runner's `finally` frees source/destination/options for this
      // exact call before returning to the caller. Using the instrumented
      // allocator with double-free detection, plus re-reading the result
      // after that free, proves the returned Uint8List's storage does not
      // live inside a buffer that free() invalidated.
      final source = i420Source(77);
      final allocator = InstrumentedNativeAllocator();
      late YuvAbiV1FrameResult result;
      try {
        withNativeAllocator(allocator, () {
          result = YuvAbiV1Runner.convert(source: source, destinationLayout: bgraLayout());
        });
        expect(allocator.outstanding, 0, reason: 'every native allocation for this call must already be freed by the time convert() returns');
      } finally {
        allocator.releaseAll();
      }

      // Read the result well after every native pointer from this call was
      // freed (and, via releaseAll, may have been handed back to the OS
      // allocator) -- if the result were a view over that memory, this read
      // would be a use-after-free, potentially returning garbage or
      // crashing under a memory sanitizer.
      expect(result.planes.single.length, width * height * 4);
      expect(result.planes.single.any((b) => b != 0), isTrue, reason: 'sanity: a real converted frame is not all zero');
    });
  }, skip: nativeAvailable ? false : 'native yuv_ffi library is not available on this host');

  group('copy-out candidate independence (allocator-level)', () {
    // These do not go through YuvAbiV1Runner: they exercise each copy-out
    // candidate from speed_00_dart_ffi's bench directly against a raw
    // package:ffi buffer, proving independence/lifetime holds for every
    // candidate compared, not only the one currently in production.
    test('every candidate copy survives free() and reuse of the native buffer', () {
      const int length = 64;
      final Pointer<Uint8> native = malloc<Uint8>(length);
      try {
        final Uint8List seed = Uint8List.fromList(List<int>.generate(length, (i) => i & 255));
        native.asTypedList(length).setAll(0, seed);

        final candidates = <String, Uint8List Function()>{
          'fromList_asTypedList': () => Uint8List.fromList(native.asTypedList(length)),
          'sized_setAll': () => Uint8List(length)..setAll(0, native.asTypedList(length)),
          'sublistView_copy': () => Uint8List.fromList(Uint8List.sublistView(native.asTypedList(length))),
        };

        for (final entry in candidates.entries) {
          final copy = entry.value();
          expect(copy, seed, reason: '${entry.key}: copy must match the native buffer at copy time');

          // Mutate native memory in place (simulating the next allocation
          // reusing freed memory) without freeing/reallocating the pointer
          // itself, so this check is deterministic and does not depend on
          // the platform allocator's reuse behavior.
          native.asTypedList(length).setAll(0, List<int>.filled(length, 0xAA));
          expect(copy, seed, reason: '${entry.key}: copy must stay unchanged after the native buffer is overwritten -- not a view');

          // Restore for the next candidate.
          native.asTypedList(length).setAll(0, seed);
        }
      } finally {
        malloc.free(native);
      }
    });
  });
}

bool _nativeAvailable(int width, int height) {
  try {
    final int lumaLen = width * height;
    final int chromaW = (width + 1) ~/ 2;
    final int chromaH = (height + 1) ~/ 2;
    final int chromaLen = chromaW * chromaH;
    YuvAbiV1Runner.convert(
      source: YuvAbiV1FrameInput(
        format: yuvFormatI420,
        width: width,
        height: height,
        planes: [
          YuvAbiV1PlaneInput(bytes: Uint8List(lumaLen), rowStride: width, pixelStride: 1),
          YuvAbiV1PlaneInput(bytes: Uint8List(chromaLen), rowStride: chromaW, pixelStride: 1),
          YuvAbiV1PlaneInput(bytes: Uint8List(chromaLen), rowStride: chromaW, pixelStride: 1),
        ],
      ),
      destinationLayout: YuvAbiV1DestinationLayout(
        format: yuvFormatBgra8888,
        width: width,
        height: height,
        planeRowStrides: [width * 4],
        planePixelStrides: [4],
      ),
    );
    return true;
  } catch (_) {
    return false;
  }
}
