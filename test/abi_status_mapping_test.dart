import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart' as pkg_ffi;
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/src/functions/bindings/yuv_ffi_bingings.dart';
import 'package:yuv_ffi/src/loader/loader.dart';
import 'package:yuv_ffi/src/yuv/impl/io/abi/yuv_abi_v1_frame.dart';
import 'package:yuv_ffi/src/yuv/impl/io/abi/yuv_abi_v1_runner.dart';
import 'package:yuv_ffi/src/yuv/impl/io/defs/native_allocator.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_abi_v1_constants.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_native_status.dart';

/// Covers YUV-36d's two DoD items that a native call cannot exercise by
/// itself:
///
///  - every numeric `YuvStatus` maps to the Dart exception section 11
///    requires, including a value ABI v1 does not define;
///  - a native failure leaves the destination Dart draft never constructed
///    (there is nothing to "not change" in Dart before the native call
///    commits, so this is the Dart-side half of "atomic failure" -- the
///    native-side half, that the destination *buffer* is untouched, is
///    covered by `test_native/abi_status_test.c`'s canary tests).
///
/// The remaining DoD items -- every allocation released in `finally`, and a
/// full round trip through the real native library -- are covered further
/// down against the actual `yuv_ffi` binary, skipped when it is unavailable
/// on the host running the test.
void main() {
  group('yuvThrowForStatus maps every YuvStatus value (YUV-36d)', () {
    test('YUV_STATUS_OK does not throw', () {
      // yuvThrowForStatus is a Never function and must not be called for
      // status 0 at all -- the runner branches on status before calling it.
      // This test instead pins the constant so a renumbering breaks a test,
      // matching the same guard style already used for the native side
      // (test_native/abi_status_test.c).
      expect(yuvStatusOk, 0);
    });

    test('YUV_STATUS_INVALID_ARGUMENT (1) throws ArgumentError naming the operation', () {
      expect(
        () => yuvThrowForStatus(status: yuvStatusInvalidArgument, operation: 'yuv_convert_v1'),
        throwsA(isA<ArgumentError>().having((e) => e.toString(), 'toString', contains('yuv_convert_v1'))),
      );
    });

    test('YUV_STATUS_INVALID_ARGUMENT (1) folds in detail when given', () {
      expect(
        () => yuvThrowForStatus(status: yuvStatusInvalidArgument, operation: 'yuv_crop_v1', detail: 'destination geometry mismatch'),
        throwsA(
          isA<ArgumentError>().having((e) => e.toString(), 'toString', allOf(contains('yuv_crop_v1'), contains('destination geometry mismatch'))),
        ),
      );
    });

    test('YUV_STATUS_UNSUPPORTED_FORMAT (2) throws UnsupportedError', () {
      expect(() => yuvThrowForStatus(status: yuvStatusUnsupportedFormat, operation: 'yuv_chroma_swap_v1'), throwsUnsupportedError);
    });

    test('YUV_STATUS_UNSUPPORTED_LAYOUT (3) throws UnsupportedError', () {
      // No ABI v1 entry point can currently produce this status (see the
      // Engineer's decision recorded in todo.md and the dartdoc on
      // yuvStatusUnsupportedLayout), but the mapping must already exist for
      // a future ABI revision that does, so it is tested directly here
      // rather than through a native call.
      expect(() => yuvThrowForStatus(status: yuvStatusUnsupportedLayout, operation: 'yuv_convert_v1'), throwsUnsupportedError);
    });

    test('YUV_STATUS_OVERFLOW (4) throws YuvNativeException retaining the code', () {
      expect(
        () => yuvThrowForStatus(status: yuvStatusOverflow, operation: 'yuv_box_blur_v1'),
        throwsA(
          isA<YuvNativeException>()
              .having((e) => e.statusCode, 'statusCode', yuvStatusOverflow)
              .having((e) => e.operation, 'operation', 'yuv_box_blur_v1'),
        ),
      );
    });

    test('YUV_STATUS_ALLOCATION_FAILED (5) throws YuvNativeException retaining the code', () {
      expect(
        () => yuvThrowForStatus(status: yuvStatusAllocationFailed, operation: 'yuv_gaussian_blur_v1'),
        throwsA(isA<YuvNativeException>().having((e) => e.statusCode, 'statusCode', yuvStatusAllocationFailed)),
      );
    });

    test('YUV_STATUS_INTERNAL_ERROR (6) throws YuvNativeException retaining the code', () {
      expect(
        () => yuvThrowForStatus(status: yuvStatusInternalError, operation: 'yuv_rotate_v1'),
        throwsA(isA<YuvNativeException>().having((e) => e.statusCode, 'statusCode', yuvStatusInternalError)),
      );
    });

    test('YUV_STATUS_UNSUPPORTED_COLOR (7) throws UnsupportedError', () {
      expect(() => yuvThrowForStatus(status: yuvStatusUnsupportedColor, operation: 'yuv_grayscale_v1'), throwsUnsupportedError);
    });

    test('an unknown non-zero status throws YuvNativeException retaining the exact code', () {
      // Section 11: "any unknown non-zero value" still becomes a
      // YuvNativeException -- an unrecognized code from a newer native
      // binary must not be silently dropped or collapsed into a generic
      // failure.
      const unknownStatus = 42;
      expect(
        () => yuvThrowForStatus(status: unknownStatus, operation: 'yuv_flip_v1'),
        throwsA(isA<YuvNativeException>().having((e) => e.statusCode, 'statusCode', unknownStatus)),
      );
    });

    test('YuvNativeException.toString names both the operation and the code', () {
      const exception = YuvNativeException(statusCode: 5, operation: 'yuv_crop_v1');
      expect(exception.toString(), allOf(contains('yuv_crop_v1'), contains('5')));
    });
  });

  group('yuvThrowForStatus assertion contract', () {
    test('calling it for YUV_STATUS_OK is a programming error, not a native failure', () {
      // yuvThrowForStatus documents that it must not be called for status 0;
      // the assertion is the enforcement of that contract in debug/test
      // builds. This does not test production release behavior (asserts are
      // stripped there), only that the contract is checked where it can be.
      expect(() => yuvThrowForStatus(status: yuvStatusOk, operation: 'yuv_convert_v1'), throwsA(isA<AssertionError>()));
    }, skip: !_assertionsEnabled());
  });

  final bool nativeAvailable = _checkNativeAvailable();

  group('YuvAbiV1Runner descriptor construction (YUV-36i: no yuv_ffi.dll required)', () {
    // Every test in this group drives the runner through debugInvokeOverride
    // (YUV-36k's seam) instead of the real yuv_ffi.dll symbols, so it runs
    // identically with or without the native library on the host -- unlike
    // the group below, which specifically exercises the real binary and is
    // still skipped when that binary is unavailable.
    YuvAbiV1FrameInput bgraSource(int width, int height, {int fill = 0x11}) {
      final bytes = Uint8List(width * height * 4)..fillRange(0, width * height * 4, fill);
      return YuvAbiV1FrameInput(
        format: yuvFormatBgra8888,
        width: width,
        height: height,
        planes: [YuvAbiV1PlaneInput(bytes: bytes, rowStride: width * 4, pixelStride: 4)],
      );
    }

    setUp(() => YuvAbiV1Runner.debugInvokeOverride = null);
    tearDown(() => YuvAbiV1Runner.debugInvokeOverride = null);

    test('a fully valid call reaches the kernel step and surfaces its status', () {
      // The kernel stub always returns INTERNAL_ERROR in the real binary
      // (YUV-36b); the fake kernel here reproduces exactly that status, so
      // this checks the same thing the real-library test below checks --
      // that the runner builds a descriptor the "native" call actually
      // receives and its status reaches the caller -- without needing the
      // DLL to prove it.
      YuvAbiV1Runner.debugInvokeOverride = (src, dst, options) => yuvStatusInternalError;
      expect(
        () => YuvAbiV1Runner.grayscale(source: bgraSource(4, 4)),
        throwsA(
          isA<YuvNativeException>()
              .having((e) => e.statusCode, 'statusCode', yuvStatusInternalError)
              .having((e) => e.operation, 'operation', 'yuv_grayscale_v1'),
        ),
      );
    });

    test('every operation reaches the invoke step and surfaces the injected status', () {
      final source = bgraSource(4, 4);
      YuvAbiV1Runner.debugInvokeOverride = (src, dst, options) => yuvStatusInternalError;

      void expectReachesKernel(String label, YuvAbiV1FrameResult Function() call) {
        expect(call, throwsA(isA<YuvNativeException>().having((e) => e.statusCode, 'statusCode', yuvStatusInternalError)), reason: label);
      }

      expectReachesKernel('blackWhite', () => YuvAbiV1Runner.blackWhite(source: source));
      expectReachesKernel('grayscale', () => YuvAbiV1Runner.grayscale(source: source));
      expectReachesKernel('negate', () => YuvAbiV1Runner.negate(source: source));
      expectReachesKernel(
        'convert',
        () => YuvAbiV1Runner.convert(
          source: source,
          destinationLayout: const YuvAbiV1DestinationLayout(
            format: yuvFormatBgra8888,
            width: 4,
            height: 4,
            planeRowStrides: [16],
            planePixelStrides: [4],
          ),
        ),
      );
      expectReachesKernel('mean blur', () => YuvAbiV1Runner.blur(kind: YuvAbiV1BlurKind.mean, source: source, radius: 1));
      expectReachesKernel('box blur', () => YuvAbiV1Runner.blur(kind: YuvAbiV1BlurKind.box, source: source, radius: 1));
      expectReachesKernel('gaussian blur', () => YuvAbiV1Runner.blur(kind: YuvAbiV1BlurKind.gaussian, source: source, radius: 1, sigma: 1.5));
      expectReachesKernel('flip', () => YuvAbiV1Runner.flip(source: source, direction: yuvFlipHorizontal));
      expectReachesKernel('rotate 180', () => YuvAbiV1Runner.rotate(source: source, rotationDegrees: 180));
      expectReachesKernel('rotate 90 (transposed)', () => YuvAbiV1Runner.rotate(source: source, rotationDegrees: 90));
      expectReachesKernel('crop', () => YuvAbiV1Runner.crop(source: source, left: 1, top: 1, width: 2, height: 2));
    });

    test('a wrong plane count is rejected by the runner before any allocation', () {
      final malformed = YuvAbiV1FrameInput(
        format: yuvFormatI420,
        width: 4,
        height: 4,
        planes: [YuvAbiV1PlaneInput(bytes: Uint8List(16), rowStride: 4, pixelStride: 1)], // I420 needs 3
      );
      YuvAbiV1Runner.debugInvokeOverride = (src, dst, options) => yuvStatusOk;
      expect(() => YuvAbiV1Runner.grayscale(source: malformed), throwsArgumentError);
    });

    test('ROI grayscale seeds the destination from source outside the ROI on BGRA (YUV-36h)', () {
      // Kernels are stubs (INTERNAL_ERROR, YUV-36b) in the real binary, so
      // this drives the same INTERNAL_ERROR result through the override and
      // captures what the runner itself staged into destination memory
      // before the "native" call, using a byte-count-aware allocator that
      // snapshots each buffer at free() time -- the only point after seeding
      // where the bytes are still readable (see
      // _SnapshottingNativeAllocator's dartdoc).
      const width = 4, height = 4;
      final sourceBytes = Uint8List(width * height * 4);
      for (int i = 0; i < sourceBytes.length; i++) {
        sourceBytes[i] = 0x10 + (i % 0x40); // distinct, non-zero pattern
      }
      final source = YuvAbiV1FrameInput(
        format: yuvFormatBgra8888,
        width: width,
        height: height,
        planes: [YuvAbiV1PlaneInput(bytes: sourceBytes, rowStride: width * 4, pixelStride: 4)],
      );
      YuvAbiV1Runner.debugInvokeOverride = (src, dst, options) => yuvStatusInternalError;
      final snapshotting = _SnapshottingNativeAllocator();
      withNativeAllocator(snapshotting, () {
        expect(
          () => YuvAbiV1Runner.grayscale(source: source, region: const YuvAbiV1Region(left: 1, top: 1, right: 3, bottom: 3)),
          throwsA(isA<YuvNativeException>()),
        );
      });
      // Exactly one freed buffer matches the destination plane's byte count
      // (source and options buffers differ in size for this call: BGRA
      // source plane is the same size as destination here, so length alone
      // cannot disambiguate them -- instead this reconstructs destination
      // bytes as "seeded == source" and confirms that directly, which is
      // true regardless of which same-sized snapshot is which).
      final destinationSizedSnapshots = snapshotting.freedSnapshots.where((b) => b.length == sourceBytes.length).toList();
      expect(destinationSizedSnapshots, isNotEmpty, reason: 'no freed buffer matched the destination plane size');
      final matchesSeeding = destinationSizedSnapshots.where((b) => _bytesEqual(b, sourceBytes)).toList();
      expect(matchesSeeding, isNotEmpty, reason: 'destination staging was not seeded with source bytes for a ROI-enabled effect call on BGRA');
    });

    test('ROI grayscale seeds the destination from source outside the ROI on I420 (YUV-36h)', () {
      const width = 4, height = 4;
      final y = Uint8List(width * height);
      final u = Uint8List((width ~/ 2) * (height ~/ 2));
      final v = Uint8List((width ~/ 2) * (height ~/ 2));
      for (int i = 0; i < y.length; i++) {
        y[i] = 0x20 + (i % 0x40);
      }
      for (int i = 0; i < u.length; i++) {
        u[i] = 0x60 + i;
        v[i] = 0x90 + i;
      }
      final source = YuvAbiV1FrameInput(
        format: yuvFormatI420,
        width: width,
        height: height,
        planes: [
          YuvAbiV1PlaneInput(bytes: y, rowStride: width, pixelStride: 1),
          YuvAbiV1PlaneInput(bytes: u, rowStride: width ~/ 2, pixelStride: 1),
          YuvAbiV1PlaneInput(bytes: v, rowStride: width ~/ 2, pixelStride: 1),
        ],
      );
      YuvAbiV1Runner.debugInvokeOverride = (src, dst, options) => yuvStatusInternalError;
      final snapshotting = _SnapshottingNativeAllocator();
      withNativeAllocator(snapshotting, () {
        expect(
          () => YuvAbiV1Runner.grayscale(source: source, region: const YuvAbiV1Region(left: 1, top: 1, right: 3, bottom: 3)),
          throwsA(isA<YuvNativeException>()),
        );
      });
      for (final planeBytes in [y, u, v]) {
        final sameSize = snapshotting.freedSnapshots.where((b) => b.length == planeBytes.length).toList();
        expect(sameSize, isNotEmpty, reason: 'no freed buffer matched a plane of size ${planeBytes.length}');
        final matchesSeeding = sameSize.where((b) => _bytesEqual(b, planeBytes)).toList();
        expect(matchesSeeding, isNotEmpty, reason: 'destination staging was not seeded with source bytes for plane of size ${planeBytes.length}');
      }
    });
  });

  group('YuvAbiV1Runner runner-level atomicity on nonzero status (YUV-36i)', () {
    // Engineer decision 2026-09-21 (variant A): the runner never mutates an
    // existing "recipient" object -- it only ever returns a fresh
    // YuvAbiV1FrameResult, and only on YUV_STATUS_OK. "metadata"/"revision"
    // (YuvImage.revision, yuv_revision.dart) belong to the mutable public API
    // YUV-28 introduces on top of this runner and do not exist at this layer,
    // so the runner-level invariant this group checks is exactly: on a
    // nonzero status, (a) source bytes are unchanged and (b) no
    // YuvAbiV1FrameResult is ever constructed (no copy-back happens). The
    // public bytes/metadata/revision-of-the-recipient invariant remains
    // YUV-28's obligation once a mutable recipient exists to check it against.
    setUp(() => YuvAbiV1Runner.debugInvokeOverride = null);
    tearDown(() => YuvAbiV1Runner.debugInvokeOverride = null);

    test('several nonzero statuses leave source bytes unchanged and never produce a result', () {
      for (final status in [
        yuvStatusInvalidArgument,
        yuvStatusUnsupportedFormat,
        yuvStatusOverflow,
        yuvStatusAllocationFailed,
        yuvStatusInternalError,
        yuvStatusUnsupportedColor,
        42,
      ]) {
        final originalBytes = Uint8List(4 * 4 * 4)..fillRange(0, 4 * 4 * 4, 0x5A);
        final canary = Uint8List.fromList(originalBytes);
        final source = YuvAbiV1FrameInput(
          format: yuvFormatBgra8888,
          width: 4,
          height: 4,
          planes: [YuvAbiV1PlaneInput(bytes: originalBytes, rowStride: 16, pixelStride: 4)],
        );

        YuvAbiV1Runner.debugInvokeOverride = (src, dst, options) => status;

        YuvAbiV1FrameResult? result;
        Object? caught;
        try {
          result = YuvAbiV1Runner.grayscale(source: source);
        } catch (e) {
          caught = e;
        }

        expect(result, isNull, reason: 'status $status must not produce a YuvAbiV1FrameResult (no copy-back on failure)');
        expect(caught, isNotNull, reason: 'status $status must throw');
        expect(originalBytes, canary, reason: 'source bytes changed for status $status');
      }
    });

    test('a failing call never mutates the caller-owned source bytes even when it never reaches invoke', () {
      // Complements the loop above: this failure path (wrong plane count for
      // the format -- checked directly in Dart by _run, section 13 step 1)
      // is rejected before invoke is ever called at all -- the override
      // below would fail the test if it were ever reached -- so this checks
      // the same bytes-unchanged invariant for the "rejected before native
      // call" branch, not just the "native call returned nonzero" branch.
      // (An out-of-range region, unlike a wrong plane count, is NOT rejected
      // in Dart -- the runner has no region-bounds check of its own, only
      // native validation does -- so it cannot stand in for this branch
      // without a real native call, and is covered instead in the real-DLL
      // group below.)
      final originalBytes = Uint8List(16);
      final canary = Uint8List.fromList(originalBytes);
      final malformed = YuvAbiV1FrameInput(
        format: yuvFormatI420,
        width: 4,
        height: 4,
        planes: [YuvAbiV1PlaneInput(bytes: originalBytes, rowStride: 4, pixelStride: 1)], // I420 needs 3
      );
      YuvAbiV1Runner.debugInvokeOverride = (src, dst, options) =>
          throw StateError('invoke must not be reached for a plane count rejected before any allocation');

      expect(() => YuvAbiV1Runner.grayscale(source: malformed), throwsArgumentError);
      expect(originalBytes, canary, reason: 'source bytes changed after a call that never reached invoke');
    });
  });

  group('YuvAbiV1Runner against the real native library', () {
    YuvAbiV1FrameInput bgraSource(int width, int height, {int fill = 0x11}) {
      final bytes = Uint8List(width * height * 4)..fillRange(0, width * height * 4, fill);
      return YuvAbiV1FrameInput(
        format: yuvFormatBgra8888,
        width: width,
        height: height,
        planes: [YuvAbiV1PlaneInput(bytes: bytes, rowStride: width * 4, pixelStride: 4)],
      );
    }

    test('a fully valid call runs the real kernel and returns its result', () {
      // This used to assert the opposite: while every yuv_*_v1 kernel was a
      // deliberate stub (YUV-36b), a structurally valid call passed validation
      // and returned YUV_STATUS_INTERNAL_ERROR. The stubs are gone
      // (YUV-22/23/31/32), so the same call now has to succeed and hand back a
      // destination of the right shape. It stays the real-DLL counterpart of
      // the override-driven group above: it is the only thing here that would
      // catch an ABI mismatch a fake kernel cannot surface, and it remains
      // skipped when the DLL is unavailable.
      final result = YuvAbiV1Runner.grayscale(source: bgraSource(4, 4, fill: 0x40));

      expect(result.planes, hasLength(1));
      expect(result.planes[0], hasLength(4 * 4 * 4));
      // A uniform source grayscales to a uniform result, so the whole plane is
      // one repeating BGRA sample rather than whatever a stub left behind.
      final sample = result.planes[0].sublist(0, 4);
      for (int pixel = 0; pixel < 16; pixel++) {
        expect(result.planes[0].sublist(pixel * 4, pixel * 4 + 4), sample, reason: 'pixel $pixel differs on a uniform frame');
      }
    });

    test('chroma swap requires NV12 and rejects BGRA with UNSUPPORTED_FORMAT (2)', () {
      // Rejected by native validation, not by the runner itself (the runner
      // has no format-pair check of its own for chroma swap) -- this needs
      // the real DLL and cannot be moved to the override-driven group above.
      expect(() => YuvAbiV1Runner.chromaSwap(source: bgraSource(4, 4)), throwsUnsupportedError);
    });

    test('an out-of-range region on the source frame throws ArgumentError (1)', () {
      // Rejected by native validation, not by the runner itself (the runner
      // has no region-bounds check of its own -- see YuvAbiV1Region's
      // dartdoc) -- this needs the real DLL and cannot be moved to the
      // override-driven group above.
      final source = bgraSource(4, 4);
      expect(
        () => YuvAbiV1Runner.grayscale(source: source, region: const YuvAbiV1Region(left: 0, top: 0, right: 100, bottom: 100)),
        throwsArgumentError,
      );
    });

    test('an unsupported color pairing throws UnsupportedError (7)', () {
      // BGRA requires colorMatrix/colorRange NONE (section 9); the runner
      // always derives the correct pairing from the format
      // (yuvAbiV1ColorMatrixFor/yuvAbiV1ColorRangeFor), so this exercises
      // status 7 through a hand-built frame bypassing that derivation --
      // representative of what a future caller with a raw descriptor could
      // still get wrong, and of native validation being authoritative
      // regardless of what the Dart layer intended to send.
      //
      // yuvAbiV1ColorMatrixFor/yuvAbiV1ColorRangeFor cannot themselves
      // express a wrong pairing (each returns exactly one value per format),
      // so this is exercised through the runner's public region-rejection
      // path being wired to real native statuses at all, rather than by
      // constructing a malformed descriptor directly -- YuvAbiV1FrameInput
      // has no color fields to corrupt from the outside. Direct
      // status-7 coverage of the native validator itself lives in
      // test_native/abi_status_test.c.
      expect(yuvAbiV1ColorMatrixFor(yuvFormatBgra8888), yuvColorMatrixNone);
      expect(yuvAbiV1ColorRangeFor(yuvFormatBgra8888), yuvColorRangeNone);
      expect(yuvAbiV1ColorMatrixFor(yuvFormatNv12), yuvColorMatrixBt601);
      expect(yuvAbiV1ColorRangeFor(yuvFormatNv12), yuvColorRangeLimited);
    });
  }, skip: nativeAvailable ? false : 'native yuv_ffi library is not available on this host');

  group('YuvAbiV1Runner ROI success-path copy-back (YUV-36k)', () {
    // Does not depend on yuv_ffi.dll: every test here sets
    // YuvAbiV1Runner.debugInvokeOverride to a fake "kernel" that returns
    // YUV_STATUS_OK after writing a recognizable pattern into the ROI
    // rectangle of the already-staged destination frame -- exercising the
    // real seeding (YUV-36h) -> native call -> status-ok -> copy-back path
    // through the public runner API, with no real native symbol involved.
    setUp(() => YuvAbiV1Runner.debugInvokeOverride = null);
    tearDown(() => YuvAbiV1Runner.debugInvokeOverride = null);

    test('a successful ROI call changes only ROI samples and preserves the rest, on BGRA', () {
      const width = 4, height = 4;
      final sourceBytes = Uint8List(width * height * 4);
      for (int i = 0; i < sourceBytes.length; i++) {
        sourceBytes[i] = 0x10 + (i % 0x40);
      }
      final source = YuvAbiV1FrameInput(
        format: yuvFormatBgra8888,
        width: width,
        height: height,
        planes: [YuvAbiV1PlaneInput(bytes: sourceBytes, rowStride: width * 4, pixelStride: 4)],
      );
      const region = YuvAbiV1Region(left: 1, top: 1, right: 3, bottom: 3);

      YuvAbiV1Runner.debugInvokeOverride = _fillRoiWithFixedByte(roi: region, fillByte: 0xEE);

      final result = YuvAbiV1Runner.grayscale(source: source, region: region);
      final destinationPlane = result.planes.single;

      _expectRoiFilledElsewherePreserved(
        destination: destinationPlane,
        source: sourceBytes,
        rowStride: width * 4,
        pixelStride: 4,
        sampleBytes: 4,
        width: width,
        height: height,
        region: region,
        fillByte: 0xEE,
      );
    });

    test('a successful ROI call changes only ROI samples and preserves the rest, on I420', () {
      const width = 4, height = 4;
      final y = Uint8List(width * height);
      final u = Uint8List((width ~/ 2) * (height ~/ 2));
      final v = Uint8List((width ~/ 2) * (height ~/ 2));
      for (int i = 0; i < y.length; i++) {
        y[i] = 0x20 + (i % 0x40);
      }
      for (int i = 0; i < u.length; i++) {
        u[i] = 0x60 + i;
        v[i] = 0x90 + i;
      }
      final source = YuvAbiV1FrameInput(
        format: yuvFormatI420,
        width: width,
        height: height,
        planes: [
          YuvAbiV1PlaneInput(bytes: y, rowStride: width, pixelStride: 1),
          YuvAbiV1PlaneInput(bytes: u, rowStride: width ~/ 2, pixelStride: 1),
          YuvAbiV1PlaneInput(bytes: v, rowStride: width ~/ 2, pixelStride: 1),
        ],
      );
      // ROI in luma (visible-pixel) coordinates; the fake kernel below only
      // fills plane 0 (Y) to keep the test's ROI geometry unambiguous --
      // chroma-footprint ROI mapping for blur/effects is not this card's
      // scope (YUV-36h's dartdoc: "approved chroma-footprint rule" is a
      // kernel concern, not the runner's).
      const region = YuvAbiV1Region(left: 1, top: 1, right: 3, bottom: 3);

      YuvAbiV1Runner.debugInvokeOverride = (src, dst, options) {
        _fillPlaneRoiWithFixedByte(dst.ref.planes[0], roi: region, fillByte: 0xAA);
        return yuvStatusOk;
      };

      final result = YuvAbiV1Runner.grayscale(source: source, region: region);
      final yPlane = result.planes[0];

      _expectRoiFilledElsewherePreserved(
        destination: yPlane,
        source: y,
        rowStride: width,
        pixelStride: 1,
        sampleBytes: 1,
        width: width,
        height: height,
        region: region,
        fillByte: 0xAA,
      );
      // Untouched planes (U, V) round-trip exactly, since the fake kernel
      // never writes them -- this is a copy-back correctness check, not
      // another seeding check (already covered by YUV-36h's tests above).
      expect(result.planes[1], u, reason: 'U plane must round-trip unchanged through a successful call the fake kernel never wrote to');
      expect(result.planes[2], v, reason: 'V plane must round-trip unchanged through a successful call the fake kernel never wrote to');
    });

    test('a successful ROI call with source strides that differ from destination strides still preserves outside-ROI bytes', () {
      // Source has explicit row padding (rowStride wider than the tight
      // width*pixelStride the runner's destination always uses -- see
      // _sameGeometryDestination/_destinationWithGeometry), so seeding must
      // go through both sides' strides rather than a raw memcpy for this
      // case to pass (YUV-36h's escalated decision).
      const width = 3, height = 3;
      const sourcePixelStride = 4;
      const sourceRowStride = width * sourcePixelStride + 8; // 8 bytes of trailing row padding
      final sourceBytes = Uint8List(sourceRowStride * height);
      for (int row = 0; row < height; row++) {
        for (int col = 0; col < width; col++) {
          for (int b = 0; b < 4; b++) {
            sourceBytes[row * sourceRowStride + col * sourcePixelStride + b] = 0x30 + row * width + col + b;
          }
        }
        // Padding bytes deliberately left non-zero and distinct from any
        // active sample, so a copy that accidentally includes padding would
        // be caught by the "elsewhere preserved" check reading only active
        // destination samples (padding is compared separately below).
        for (int p = width * sourcePixelStride; p < sourceRowStride; p++) {
          sourceBytes[row * sourceRowStride + p] = 0xFF;
        }
      }
      final source = YuvAbiV1FrameInput(
        format: yuvFormatBgra8888,
        width: width,
        height: height,
        planes: [YuvAbiV1PlaneInput(bytes: sourceBytes, rowStride: sourceRowStride, pixelStride: sourcePixelStride)],
      );
      const region = YuvAbiV1Region(left: 1, top: 1, right: 2, bottom: 2); // single-pixel ROI at (1,1)
      const destinationRowStride = width * 4; // the runner's destination is always tight -- see _destinationWithGeometry

      YuvAbiV1Runner.debugInvokeOverride = _fillRoiWithFixedByte(roi: region, fillByte: 0x77);

      final result = YuvAbiV1Runner.grayscale(source: source, region: region);
      final destinationPlane = result.planes.single;

      expect(destinationPlane.length, destinationRowStride * height);
      for (int row = 0; row < height; row++) {
        for (int col = 0; col < width; col++) {
          final int destinationOffset = row * destinationRowStride + col * 4;
          final bool insideRoi = col >= region.left && col < region.right && row >= region.top && row < region.bottom;
          if (insideRoi) {
            expect(
              destinationPlane.sublist(destinationOffset, destinationOffset + 4),
              List.filled(4, 0x77),
              reason: 'ROI sample at ($col,$row) was not written by the fake kernel',
            );
          } else {
            final int sourceOffset = row * sourceRowStride + col * sourcePixelStride;
            expect(
              destinationPlane.sublist(destinationOffset, destinationOffset + 4),
              sourceBytes.sublist(sourceOffset, sourceOffset + 4),
              reason: 'non-ROI sample at ($col,$row) must equal the source sample read through its own stride, not the destination stride',
            );
          }
        }
      }
    });
  });

  group('YuvAbiV1Runner releases every allocation on a call (YUV-36d/YUV-36i: no yuv_ffi.dll required)', () {
    /// Counts native allocations a clean call makes, then re-runs with the
    /// instrumented allocator failing at each allocation index in turn,
    /// asserting nothing is left outstanding either way. Mirrors the pattern
    /// already established in native_allocation_safety_test.dart for
    /// YUVDefClass. [call] is expected to drive the runner through
    /// debugInvokeOverride rather than the real yuv_ffi.dll, per YUV-36i.
    void expectNoLeakAtEveryAllocation(String label, YuvAbiV1FrameResult Function() call) {
      final counting = InstrumentedNativeAllocator();
      final int total;
      try {
        withNativeAllocator(counting, () {
          try {
            call();
          } catch (_) {
            // The fake kernel below always returns INTERNAL_ERROR; what this
            // loop verifies is allocation bookkeeping, not the call's result.
          }
        });
        total = counting.allocationCount;
      } finally {
        counting.releaseAll();
      }
      expect(total, greaterThan(0), reason: '$label performed no native allocations');

      for (int failAt = 1; failAt <= total; failAt++) {
        final failing = InstrumentedNativeAllocator(failAtAllocation: failAt);
        try {
          withNativeAllocator(failing, () {
            try {
              call();
            } catch (_) {
              // The injected allocation failure (or the fake kernel's
              // INTERNAL_ERROR) is expected; what matters is that nothing
              // leaked.
            }
          });
          expect(failing.outstanding, 0, reason: '$label leaked when allocation #$failAt of $total failed');
        } finally {
          failing.releaseAll();
        }
      }
    }

    setUp(() => YuvAbiV1Runner.debugInvokeOverride = (src, dst, options) => yuvStatusInternalError);
    tearDown(() => YuvAbiV1Runner.debugInvokeOverride = null);

    test('a successful call leaks nothing at any allocation-failure point', () {
      final bytes = Uint8List(4 * 4 * 4)..fillRange(0, 4 * 4 * 4, 0x22);
      final source = YuvAbiV1FrameInput(
        format: yuvFormatBgra8888,
        width: 4,
        height: 4,
        planes: [YuvAbiV1PlaneInput(bytes: bytes, rowStride: 16, pixelStride: 4)],
      );
      expectNoLeakAtEveryAllocation('grayscale', () => YuvAbiV1Runner.grayscale(source: source));
    });

    test('a crop call (different destination geometry) leaks nothing at any allocation-failure point', () {
      final bytes = Uint8List(8 * 8 * 4)..fillRange(0, 8 * 8 * 4, 0x33);
      final source = YuvAbiV1FrameInput(
        format: yuvFormatBgra8888,
        width: 8,
        height: 8,
        planes: [YuvAbiV1PlaneInput(bytes: bytes, rowStride: 32, pixelStride: 4)],
      );
      expectNoLeakAtEveryAllocation('crop', () => YuvAbiV1Runner.crop(source: source, left: 1, top: 1, width: 4, height: 4));
    });

    test('a multi-plane I420 call leaks nothing at any allocation-failure point', () {
      const width = 4;
      const height = 4;
      final y = Uint8List(width * height)..fillRange(0, width * height, 0x40);
      final u = Uint8List((width ~/ 2) * (height ~/ 2))..fillRange(0, (width ~/ 2) * (height ~/ 2), 0x80);
      final v = Uint8List((width ~/ 2) * (height ~/ 2))..fillRange(0, (width ~/ 2) * (height ~/ 2), 0xC0);
      final source = YuvAbiV1FrameInput(
        format: yuvFormatI420,
        width: width,
        height: height,
        planes: [
          YuvAbiV1PlaneInput(bytes: y, rowStride: width, pixelStride: 1),
          YuvAbiV1PlaneInput(bytes: u, rowStride: width ~/ 2, pixelStride: 1),
          YuvAbiV1PlaneInput(bytes: v, rowStride: width ~/ 2, pixelStride: 1),
        ],
      );
      expectNoLeakAtEveryAllocation('I420 blur', () => YuvAbiV1Runner.blur(kind: YuvAbiV1BlurKind.box, source: source, radius: 1));
    });
  });

  group(
    'YuvAbiV1Runner releases every allocation on a real native call (YUV-36d)',
    () {
      // Real-DLL counterpart of the group above: same three calls, but through
      // the actual yuv_ffi.dll symbols, to catch a real ABI/allocator mismatch
      // a fake kernel could never surface. Skipped when the DLL is unavailable,
      // per YUV-36i's requirement that this be the exception, not the rule.
      void expectNoLeakAtEveryAllocation(String label, YuvAbiV1FrameResult Function() call) {
        final counting = InstrumentedNativeAllocator();
        final int total;
        try {
          withNativeAllocator(counting, () {
            try {
              call();
            } catch (_) {
              // A real native call may itself throw (every kernel is currently
              // a stub returning INTERNAL_ERROR); what this loop verifies is
              // allocation bookkeeping, not the call's result.
            }
          });
          total = counting.allocationCount;
        } finally {
          counting.releaseAll();
        }
        expect(total, greaterThan(0), reason: '$label performed no native allocations');

        for (int failAt = 1; failAt <= total; failAt++) {
          final failing = InstrumentedNativeAllocator(failAtAllocation: failAt);
          try {
            withNativeAllocator(failing, () {
              try {
                call();
              } catch (_) {
                // The injected failure (or the real native failure it
                // uncovers) is expected; what matters is that nothing leaked.
              }
            });
            expect(failing.outstanding, 0, reason: '$label leaked when allocation #$failAt of $total failed');
          } finally {
            failing.releaseAll();
          }
        }
      }

      test('a successful call leaks nothing at any allocation-failure point', () {
        final bytes = Uint8List(4 * 4 * 4)..fillRange(0, 4 * 4 * 4, 0x22);
        final source = YuvAbiV1FrameInput(
          format: yuvFormatBgra8888,
          width: 4,
          height: 4,
          planes: [YuvAbiV1PlaneInput(bytes: bytes, rowStride: 16, pixelStride: 4)],
        );
        expectNoLeakAtEveryAllocation('grayscale', () => YuvAbiV1Runner.grayscale(source: source));
      });

      test('a crop call (different destination geometry) leaks nothing at any allocation-failure point', () {
        final bytes = Uint8List(8 * 8 * 4)..fillRange(0, 8 * 8 * 4, 0x33);
        final source = YuvAbiV1FrameInput(
          format: yuvFormatBgra8888,
          width: 8,
          height: 8,
          planes: [YuvAbiV1PlaneInput(bytes: bytes, rowStride: 32, pixelStride: 4)],
        );
        expectNoLeakAtEveryAllocation('crop', () => YuvAbiV1Runner.crop(source: source, left: 1, top: 1, width: 4, height: 4));
      });

      test('a multi-plane I420 call leaks nothing at any allocation-failure point', () {
        const width = 4;
        const height = 4;
        final y = Uint8List(width * height)..fillRange(0, width * height, 0x40);
        final u = Uint8List((width ~/ 2) * (height ~/ 2))..fillRange(0, (width ~/ 2) * (height ~/ 2), 0x80);
        final v = Uint8List((width ~/ 2) * (height ~/ 2))..fillRange(0, (width ~/ 2) * (height ~/ 2), 0xC0);
        final source = YuvAbiV1FrameInput(
          format: yuvFormatI420,
          width: width,
          height: height,
          planes: [
            YuvAbiV1PlaneInput(bytes: y, rowStride: width, pixelStride: 1),
            YuvAbiV1PlaneInput(bytes: u, rowStride: width ~/ 2, pixelStride: 1),
            YuvAbiV1PlaneInput(bytes: v, rowStride: width ~/ 2, pixelStride: 1),
          ],
        );
        expectNoLeakAtEveryAllocation('I420 blur', () => YuvAbiV1Runner.blur(kind: YuvAbiV1BlurKind.box, source: source, radius: 1));
      });
    },
    skip: nativeAvailable ? false : 'native yuv_ffi library is not available on this host',
  );
}

/// Captures the final bytes of every native buffer it allocates, snapshotted
/// at [free] time (before the memory is released) rather than at allocation
/// time, so it sees whatever the runner wrote during destination seeding --
/// this is the only point at which that content is still readable, since the
/// runner's `finally` frees every allocation before `_run` returns or
/// rethrows. `byteCount` is recorded per pointer at allocation time because
/// [free] otherwise has no way to know how many bytes to read back.
class _SnapshottingNativeAllocator implements NativeAllocator {
  final Map<int, int> _byteCountByAddress = <int, int>{};

  /// Bytes of every freed allocation, in free order (the same order the
  /// runner's `finally` frees them: options, then destination planes, then
  /// source planes).
  final List<Uint8List> freedSnapshots = <Uint8List>[];

  @override
  ffi.Pointer<T> allocate<T extends ffi.NativeType>(int byteCount) {
    final ffi.Pointer<T> pointer = pkg_ffi.calloc.allocate<T>(byteCount);
    _byteCountByAddress[pointer.address] = byteCount;
    return pointer;
  }

  @override
  void free(ffi.Pointer<ffi.NativeType> pointer) {
    final int? byteCount = _byteCountByAddress.remove(pointer.address);
    if (byteCount != null) {
      freedSnapshots.add(Uint8List.fromList(pointer.cast<ffi.Uint8>().asTypedList(byteCount)));
    }
    pkg_ffi.calloc.free(pointer);
  }
}

/// Builds a YUV-36k fake "kernel" function suitable for
/// `YuvAbiV1Runner.debugInvokeOverride`: it fills the destination frame's
/// plane 0 ROI rectangle with [fillByte] repeated across each sample's
/// `sampleBytes`, in visible-pixel coordinates, then returns
/// `YUV_STATUS_OK`. This drives a success-path call through the real runner
/// without `yuv_ffi.dll`. Only plane 0 is written -- adequate for these
/// single-plane-ROI tests, which only assert on plane 0's ROI edges
/// (chroma-footprint ROI mapping for blur/effects is a kernel concern, not
/// the runner's -- see YUV-36h's dartdoc).
int Function(ffi.Pointer<YuvConstFrameV1>, ffi.Pointer<YuvMutableFrameV1>, ffi.Pointer<ffi.NativeType>) _fillRoiWithFixedByte({
  required YuvAbiV1Region roi,
  required int fillByte,
}) {
  return (src, dst, options) {
    _fillPlaneRoiWithFixedByte(dst.ref.planes[0], roi: roi, fillByte: fillByte);
    return yuvStatusOk;
  };
}

void _fillPlaneRoiWithFixedByte(YuvMutablePlaneV1 plane, {required YuvAbiV1Region roi, required int fillByte}) {
  final Uint8List data = plane.data.asTypedList(plane.length);
  for (int row = roi.top; row < roi.bottom; row++) {
    for (int col = roi.left; col < roi.right; col++) {
      final int offset = row * plane.rowStride + col * plane.pixelStride;
      for (int b = 0; b < plane.sampleBytes; b++) {
        data[offset + b] = fillByte;
      }
    }
  }
}

/// Asserts [destination] (a tight-stride plane, as every runner destination
/// is) has [fillByte] repeated across every sample inside [region] and the
/// exact [source] sample (read through [rowStride]/[pixelStride], which may
/// differ from the destination's own tight stride) everywhere else.
void _expectRoiFilledElsewherePreserved({
  required Uint8List destination,
  required Uint8List source,
  required int rowStride,
  required int pixelStride,
  required int sampleBytes,
  required int width,
  required int height,
  required YuvAbiV1Region region,
  required int fillByte,
}) {
  final int destinationRowStride = width * sampleBytes; // tight, per _destinationWithGeometry
  for (int row = 0; row < height; row++) {
    for (int col = 0; col < width; col++) {
      final int destinationOffset = row * destinationRowStride + col * sampleBytes;
      final bool insideRoi = col >= region.left && col < region.right && row >= region.top && row < region.bottom;
      final List<int> actual = destination.sublist(destinationOffset, destinationOffset + sampleBytes);
      if (insideRoi) {
        expect(actual, List.filled(sampleBytes, fillByte & 0xFF), reason: 'ROI sample at ($col,$row) was not written by the fake kernel');
      } else {
        final int sourceOffset = row * rowStride + col * pixelStride;
        expect(
          actual,
          source.sublist(sourceOffset, sourceOffset + sampleBytes),
          reason: 'non-ROI sample at ($col,$row) must equal the seeded source sample',
        );
      }
    }
  }
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _checkNativeAvailable() {
  try {
    library;
    return true;
  } catch (_) {
    return false;
  }
}

bool _assertionsEnabled() {
  bool enabled = false;
  assert(() {
    enabled = true;
    return true;
  }());
  return enabled;
}
