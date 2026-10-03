@Tags(['contract'])
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/src/yuv/impl/io/abi/yuv_abi_v1_runner.dart';
import 'package:yuv_ffi/src/yuv/impl/io/defs/native_allocator.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_abi_v1_constants.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_abi_v1_frame.dart';

/// The `YuvAbiV1Runner.convert` destination buffer is allocated with
/// `malloc` (uninitialized) instead of `calloc` (zero-filled), because its
/// destination layout is always tight-stride (no row padding, no pixel gaps)
/// and `yuv_convert_v1` either rejects the call before writing a single byte
/// (validation runs entirely before dispatch -- see `yuv_convert_v1.c`) or,
/// on success, its dispatched conversion function overwrites every one of
/// the destination's bytes. This file only re-verifies that contract from
/// the Dart side; it does not touch native code.
void main() {
  const int width = 6;
  const int height = 4;

  YuvAbiV1FrameInput i420Source() {
    final int lumaLen = width * height;
    final int chromaW = (width + 1) ~/ 2;
    final int chromaH = (height + 1) ~/ 2;
    final int chromaLen = chromaW * chromaH;
    return YuvAbiV1FrameInput(
      format: yuvFormatI420,
      width: width,
      height: height,
      planes: [
        YuvAbiV1PlaneInput(bytes: Uint8List.fromList(List<int>.generate(lumaLen, (i) => (i * 7 + 11) & 255)), rowStride: width, pixelStride: 1),
        YuvAbiV1PlaneInput(bytes: Uint8List.fromList(List<int>.generate(chromaLen, (i) => (i * 13 + 40) & 255)), rowStride: chromaW, pixelStride: 1),
        YuvAbiV1PlaneInput(bytes: Uint8List.fromList(List<int>.generate(chromaLen, (i) => (i * 17 + 90) & 255)), rowStride: chromaW, pixelStride: 1),
      ],
    );
  }

  YuvAbiV1DestinationLayout bgraLayout() =>
      YuvAbiV1DestinationLayout(format: yuvFormatBgra8888, width: width, height: height, planeRowStrides: [width * 4], planePixelStrides: [4]);

  final bool nativeAvailable = _nativeAvailable();

  group('destination allocation (convert)', () {
    test('success path is byte-exact against the calloc baseline', () {
      // Runs the same conversion twice: once through the allocator that
      // now backs production (malloc-uninitialized destination for
      // convert), and once forcing calloc for every allocation via a
      // thin wrapper, to prove the candidate is not merely "did not
      // crash" but produces the exact same bytes as the zero-filled
      // baseline the library used previously
      final source = i420Source();
      final layout = bgraLayout();

      final candidate = YuvAbiV1Runner.convert(source: source, destinationLayout: layout);

      final alwaysCalloc = _AlwaysCallocAllocator();
      late YuvAbiV1FrameResult baseline;
      withNativeAllocator(alwaysCalloc, () {
        baseline = YuvAbiV1Runner.convert(source: source, destinationLayout: layout);
      });

      expect(
        candidate.planes.single,
        baseline.planes.single,
        reason: 'malloc-uninitialized destination must match the calloc-zeroed baseline byte for byte',
      );
      expect(candidate.planes.single.length, width * height * 4);
    });

    test('an error status never publishes destination bytes to the caller', () {
      // YUV_FORMAT_RGBA8888 is not a valid convert destination (only
      // I420/NV12/BGRA8888 are, per yuv_convert_v1's convertPairs table),
      // so this is rejected by yuv_validate_v1_format_pair before any
      // conversion function -- and therefore before any destination
      // write -- runs. The runner maps this particular status to
      // UnsupportedError (yuv_native_status.dart), not YuvNativeException;
      // the point of this assertion is only that some exception is thrown
      // and no result reaches the caller, so the buffer's own initial
      // content -- zeroed or not -- stays unobservable either way (step
      // 6/7 ordering: map non-zero status to an exception before step 7
      // ever copies the destination back).
      final source = i420Source();
      final invalidLayout = YuvAbiV1DestinationLayout(
        format: yuvFormatRgba8888,
        width: width,
        height: height,
        planeRowStrides: [width * 4],
        planePixelStrides: [4],
      );

      expect(() => YuvAbiV1Runner.convert(source: source, destinationLayout: invalidLayout), throwsA(anything));
    });

    test('allocator failure at every allocation index leaves nothing outstanding and never returns a result', () {
      final source = i420Source();
      final layout = bgraLayout();

      final probe = InstrumentedNativeAllocator();
      int total;
      try {
        withNativeAllocator(probe, () => YuvAbiV1Runner.convert(source: source, destinationLayout: layout));
        total = probe.allocationCount;
      } finally {
        probe.releaseAll();
      }
      expect(total, greaterThan(0));

      for (int failAt = 1; failAt <= total; failAt++) {
        final allocator = InstrumentedNativeAllocator(failAtAllocation: failAt);
        try {
          withNativeAllocator(allocator, () {
            expect(
              () => YuvAbiV1Runner.convert(source: source, destinationLayout: layout),
              throwsA(anything),
              reason: 'allocation #$failAt of $total should surface as a thrown error, not a null-deref or a silently wrong result',
            );
          });
          expect(allocator.outstanding, 0, reason: 'allocation #$failAt of $total leaked native memory on the injected-failure path');
        } finally {
          allocator.releaseAll();
        }
      }
    });

    test('padded destination layout keeps row padding zeroed, not malloc garbage', () {
      // The destination may carry row padding or pixel gaps:
      // convert() is a public method that accepts whatever destinationLayout
      // the caller passes, not only the tight layout toBgraBytes()/toBgra()
      // build. A rowStride wider than the active row leaves padding bytes
      // that yuv_convert_v1 never writes; if the allocator were malloc
      // (uninitialized) here, _copyDestinationPlanes would copy that garbage
      // straight into the result. Uses I420 2x2, the exact geometry the
      // review reproduced the defect with, with destination rowStride=12
      // against an active row of 8 bytes (2 px * 4 bytes/px).
      final source = i420Source();
      final paddedLayout = YuvAbiV1DestinationLayout(
        format: yuvFormatBgra8888,
        width: width,
        height: height,
        planeRowStrides: [width * 4 + 4],
        planePixelStrides: [4],
      );

      final canaryAllocator = _CanaryUninitializedAllocator();
      late YuvAbiV1FrameResult result;
      withNativeAllocator(canaryAllocator, () {
        result = YuvAbiV1Runner.convert(source: source, destinationLayout: paddedLayout);
      });

      final Uint8List plane = result.planes.single;
      final int rowStride = width * 4 + 4;
      final int activeRowBytes = width * 4;
      for (int row = 0; row < height; row++) {
        for (int col = activeRowBytes; col < rowStride; col++) {
          expect(
            plane[row * rowStride + col],
            0,
            reason: 'row $row padding byte $col must be zero, not the 0xA5 canary an uninitialized allocator would leave behind',
          );
        }
      }
    });

    test('gapped destination layout keeps pixel gap bytes zeroed, not malloc garbage', () {
      // Same defect, pixel-gap variant: pixelStride wider than sampleBytes
      // leaves inter-pixel gap bytes that the native call never writes.
      final source = i420Source();
      const int gappedPixelStride = 6; // sampleBytes (4) + 2 gap bytes.
      final gappedLayout = YuvAbiV1DestinationLayout(
        format: yuvFormatBgra8888,
        width: width,
        height: height,
        planeRowStrides: [width * gappedPixelStride],
        planePixelStrides: [gappedPixelStride],
      );

      final canaryAllocator = _CanaryUninitializedAllocator();
      late YuvAbiV1FrameResult result;
      withNativeAllocator(canaryAllocator, () {
        result = YuvAbiV1Runner.convert(source: source, destinationLayout: gappedLayout);
      });

      final Uint8List plane = result.planes.single;
      final int rowStride = width * gappedPixelStride;
      for (int row = 0; row < height; row++) {
        for (int col = 0; col < width; col++) {
          final int pixelStart = row * rowStride + col * gappedPixelStride;
          for (int gapByte = 4; gapByte < gappedPixelStride; gapByte++) {
            expect(
              plane[pixelStart + gapByte],
              0,
              reason: 'pixel ($col,$row) gap byte $gapByte must be zero, not the 0xA5 canary an uninitialized allocator would leave behind',
            );
          }
        }
      }
    });

    test('tight destination layout still gets the malloc fast path (no zero-fill work)', () {
      // The fix must not regress the allocation win for the case it was meant
      // for: a genuinely tight layout (what toBgraBytes()/toBgra() build)
      // should still route through allocateUninitialized, not allocate.
      final source = i420Source();
      final layout = bgraLayout();

      final tracker = _AllocationKindTrackingAllocator();
      withNativeAllocator(tracker, () {
        YuvAbiV1Runner.convert(source: source, destinationLayout: layout);
      });

      expect(tracker.uninitializedCount, greaterThan(0), reason: 'tight layout must still use the malloc (uninitialized) fast path');
    });

    test('padded destination layout falls back to the zero-filled allocation path', () {
      final source = i420Source();
      final paddedLayout = YuvAbiV1DestinationLayout(
        format: yuvFormatBgra8888,
        width: width,
        height: height,
        planeRowStrides: [width * 4 + 4],
        planePixelStrides: [4],
      );

      final tracker = _AllocationKindTrackingAllocator();
      withNativeAllocator(tracker, () {
        YuvAbiV1Runner.convert(source: source, destinationLayout: paddedLayout);
      });

      expect(tracker.uninitializedCount, 0, reason: 'padded destination layout must not use the uninitialized allocation path');
    });

    test('success path frees every allocation exactly once under the instrumented allocator', () {
      final source = i420Source();
      final layout = bgraLayout();
      final allocator = InstrumentedNativeAllocator();
      try {
        withNativeAllocator(allocator, () {
          final result = YuvAbiV1Runner.convert(source: source, destinationLayout: layout);
          expect(result.planes.single.length, width * height * 4);
        });
        // A double free throws inside the allocator; reaching here with a
        // zero balance proves every pointer -- including the now
        // malloc-backed destination planes -- was released exactly once.
        expect(allocator.outstanding, 0);
        expect(allocator.allocationCount, greaterThan(0));
      } finally {
        allocator.releaseAll();
      }
    });
  }, skip: nativeAvailable ? false : 'native yuv_ffi library is not available on this host');
}

/// Forces every allocation through `calloc`, including what production now
/// routes through `malloc`, so the success-path test above has an
/// independent zero-filled baseline to compare byte-for-byte against.
class _AlwaysCallocAllocator implements NativeAllocator {
  const _AlwaysCallocAllocator();

  static const CallocNativeAllocator _delegate = CallocNativeAllocator();

  @override
  Pointer<T> allocate<T extends NativeType>(int byteCount) => _delegate.allocate<T>(byteCount);

  @override
  Pointer<T> allocateUninitialized<T extends NativeType>(int byteCount) => _delegate.allocate<T>(byteCount);

  @override
  void free(Pointer<NativeType> pointer) => _delegate.free(pointer);
}

/// Fills every `allocateUninitialized` buffer with `0xA5` before handing it
/// back, standing in for whatever garbage a real `malloc` might return, so a
/// test can assert that padding/gap bytes are zero rather than merely "not
/// crashing". `allocate` (calloc) is left at the real zero-filling
/// implementation, matching production: this allocator's only job is to make
/// the uninitialized path's garbage deterministic and observable.
class _CanaryUninitializedAllocator implements NativeAllocator {
  static const CallocNativeAllocator _delegate = CallocNativeAllocator();

  @override
  Pointer<T> allocate<T extends NativeType>(int byteCount) => _delegate.allocate<T>(byteCount);

  @override
  Pointer<T> allocateUninitialized<T extends NativeType>(int byteCount) {
    final Pointer<T> pointer = _delegate.allocate<T>(byteCount);
    pointer.cast<Uint8>().asTypedList(byteCount).fillRange(0, byteCount, 0xA5);
    return pointer;
  }

  @override
  void free(Pointer<NativeType> pointer) => _delegate.free(pointer);
}

/// Records how many destination-plane allocations went through
/// `allocateUninitialized` (the malloc fast path) versus `allocate` (calloc),
/// so a test can assert which path `convert()` picked for a given layout
/// without depending on timing.
class _AllocationKindTrackingAllocator implements NativeAllocator {
  static const CallocNativeAllocator _delegate = CallocNativeAllocator();

  int uninitializedCount = 0;

  @override
  Pointer<T> allocate<T extends NativeType>(int byteCount) => _delegate.allocate<T>(byteCount);

  @override
  Pointer<T> allocateUninitialized<T extends NativeType>(int byteCount) {
    uninitializedCount++;
    return _delegate.allocate<T>(byteCount);
  }

  @override
  void free(Pointer<NativeType> pointer) => _delegate.free(pointer);
}

bool _nativeAvailable() {
  try {
    YuvAbiV1Runner.convert(
      source: YuvAbiV1FrameInput(
        format: yuvFormatI420,
        width: 2,
        height: 2,
        planes: [
          YuvAbiV1PlaneInput(bytes: Uint8List(4), rowStride: 2, pixelStride: 1),
          YuvAbiV1PlaneInput(bytes: Uint8List(1), rowStride: 1, pixelStride: 1),
          YuvAbiV1PlaneInput(bytes: Uint8List(1), rowStride: 1, pixelStride: 1),
        ],
      ),
      destinationLayout: YuvAbiV1DestinationLayout(format: yuvFormatBgra8888, width: 2, height: 2, planeRowStrides: [8], planePixelStrides: [4]),
    );
    return true;
  } catch (_) {
    return false;
  }
}
