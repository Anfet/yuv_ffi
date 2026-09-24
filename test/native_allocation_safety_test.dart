import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/src/loader/loader.dart';
import 'package:yuv_ffi/src/yuv/impl/io/defs/native_allocator.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Verifies YUV-16: every already-acquired native resource is released when a
/// later allocation in the same method throws.
///
/// The instrumented allocator fails deterministically at the Nth allocation and
/// tracks outstanding pointers, so a leak shows up as a non-zero count rather
/// than as unreliable process memory growth.
void main() {
  final bool nativeAvailable = _checkNativeAvailable();

  const int w = 8;
  const int h = 8;

  /// Runs [body] with an allocator that throws at [failAt] and returns the
  /// number of allocations that were never freed.
  int outstandingAfterFailure(int failAt, void Function() body) {
    final allocator = InstrumentedNativeAllocator(failAtAllocation: failAt);
    try {
      withNativeAllocator(allocator, () {
        try {
          body();
        } catch (_) {
          // The injected failure is expected; what matters is the cleanup.
        }
      });
      return allocator.outstanding;
    } finally {
      allocator.releaseAll();
    }
  }

  /// Counts how many allocations [body] performs on a clean run.
  int allocationsOf(void Function() body) {
    final allocator = InstrumentedNativeAllocator();
    try {
      withNativeAllocator(allocator, body);
      return allocator.allocationCount;
    } finally {
      allocator.releaseAll();
    }
  }

  /// Asserts that failing at each allocation index leaves nothing outstanding.
  void expectNoLeakAtEveryAllocation(String label, void Function() body) {
    final total = allocationsOf(body);
    expect(total, greaterThan(0), reason: '$label performed no native allocations');
    for (int failAt = 1; failAt <= total; failAt++) {
      expect(outstandingAfterFailure(failAt, body), 0, reason: '$label leaked native memory when allocation #$failAt of $total failed');
    }
  }

  YuvImage i420() => YuvImage.i420(w, h);

  // ignore: deprecated_member_use_from_same_package
  YuvImage nv21() => YuvImage.nv21(w, h);

  YuvImage bgra() => YuvImage.bgra(w, h);

  group('native allocation safety', () {
    test('blackwhite releases partial state when an inner allocation fails', () {
      // ignore: deprecated_member_use_from_same_package
      expectNoLeakAtEveryAllocation('blackwhite(i420)', () => i420().blackwhite());
      // ignore: deprecated_member_use_from_same_package
      expectNoLeakAtEveryAllocation('blackwhite(nv21)', () => nv21().blackwhite());
      // ignore: deprecated_member_use_from_same_package
      expectNoLeakAtEveryAllocation('blackwhite(bgra)', () => bgra().blackwhite());
    });

    test('crop releases srcDef when destination allocation fails', () {
      // ignore: deprecated_member_use_from_same_package
      expectNoLeakAtEveryAllocation('crop', () => i420().crop(const ui.Rect.fromLTWH(0, 0, 4, 4)));
    });

    test('rotate releases srcDef when destination allocation fails', () {
      // ignore: deprecated_member_use_from_same_package
      expectNoLeakAtEveryAllocation('rotate', () => i420().rotate(YuvImageRotation.rotation90));
    });

    test('swapNv releases the source def when destination allocation fails', () {
      // ignore: deprecated_member_use_from_same_package
      expectNoLeakAtEveryAllocation('swapNv', () => nv21().swapNv());
    });

    test('toBgra8888 releases def when the output buffer allocation fails', () {
      // ignore: deprecated_member_use_from_same_package
      expectNoLeakAtEveryAllocation('toBgra8888', () => nv21().toBgra8888());
    });

    test('toYuvI420 releases def when destination allocation fails', () {
      // ignore: deprecated_member_use_from_same_package
      expectNoLeakAtEveryAllocation('toYuvI420', () => nv21().toYuvI420());
    });

    test('toYuvNv21 releases def when destination allocation fails', () {
      // ignore: deprecated_member_use_from_same_package
      expectNoLeakAtEveryAllocation('toYuvNv21', () => i420().toYuvNv21());
    });

    test('fromRgba8888 releases the rgba buffer when the def allocation fails', () {
      final rgba = Uint8List(w * h * 4);
      // ignore: deprecated_member_use_from_same_package
      expectNoLeakAtEveryAllocation('fromRgba8888', () => i420().fromRgba8888(rgba));
    });

    test('boxBlur and meanBlur release def when the rect allocation fails', () {
      const rect = ui.Rect.fromLTWH(0, 0, 4, 4);
      // ignore: deprecated_member_use_from_same_package
      expectNoLeakAtEveryAllocation('boxBlur', () => i420().boxBlur(radius: 1, rect: rect));
      // ignore: deprecated_member_use_from_same_package
      expectNoLeakAtEveryAllocation('meanBlur', () => i420().meanBlur(radius: 1, rect: rect));
    });

    test('success paths free every allocation exactly once', () {
      final allocator = InstrumentedNativeAllocator();
      try {
        withNativeAllocator(allocator, () {
          // ignore: deprecated_member_use_from_same_package
          i420().blackwhite();
          // ignore: deprecated_member_use_from_same_package
          nv21().swapNv();
          // ignore: deprecated_member_use_from_same_package
          i420().crop(const ui.Rect.fromLTWH(0, 0, 4, 4));
          // ignore: deprecated_member_use_from_same_package
          i420().rotate(YuvImageRotation.rotation90);
          // ignore: deprecated_member_use_from_same_package
          nv21().toBgra8888();
          // ignore: deprecated_member_use_from_same_package
          nv21().toYuvI420();
          // ignore: deprecated_member_use_from_same_package
          i420().toYuvNv21();
          // ignore: deprecated_member_use_from_same_package
          i420().fromRgba8888(Uint8List(w * h * 4));
          // ignore: deprecated_member_use_from_same_package
          i420().boxBlur(radius: 1, rect: const ui.Rect.fromLTWH(0, 0, 4, 4));
        });
        // A double free throws inside the allocator, so reaching here with a
        // zero balance proves each pointer was released exactly once.
        expect(allocator.outstanding, 0);
        expect(allocator.allocationCount, greaterThan(0));
      } finally {
        allocator.releaseAll();
      }
    });

    test('the original exception is not replaced by cleanup', () {
      final allocator = InstrumentedNativeAllocator(failAtAllocation: 2);
      try {
        withNativeAllocator(allocator, () {
          expect(
            // ignore: deprecated_member_use_from_same_package
            () => i420().crop(const ui.Rect.fromLTWH(0, 0, 4, 4)),
            throwsA(predicate((e) => e.toString().contains('Injected allocation failure'))),
          );
        });
        expect(allocator.outstanding, 0);
      } finally {
        allocator.releaseAll();
      }
    });
  }, skip: nativeAvailable ? false : 'native yuv_ffi library is not available on this host');
}

bool _checkNativeAvailable() {
  try {
    library;
    return true;
  } catch (_) {
    return false;
  }
}
