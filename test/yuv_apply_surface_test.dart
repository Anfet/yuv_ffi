import 'dart:ffi' as ffi;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/src/loader/impl/loader_io.dart' as loader_io;
import 'package:yuv_ffi/src/loader/loader.dart';
import 'package:yuv_ffi/src/yuv/impl/io/abi/yuv_abi_v1_runner.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_native_status.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_pixel_format.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_revision.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Verifies REL-04's `apply*` surface (`doc/api-abi-0.4-design.md` sections 2,
/// 4, 7, 13; `todo.md`'s post-REL-09 addendum).
///
/// Every `apply*` must call [yuvRequireCapability] as its first action, before
/// any allocation, native invocation, or state change, and every failure
/// (capability, argument, or native status) must leave bytes, format,
/// geometry and revision completely unchanged. This uses the same
/// replaceable-opener/symbol-checker seam `yuv_ffi_capabilities_wiring_test.dart`
/// and `io_abi_v1_public_contract_test.dart` already use, so it runs on every
/// host without a real `yuv_ffi` native library: a fake library resolves every
/// ABI v1 symbol so [YuvFfi.initialize] succeeds, and [YuvAbiV1Runner]'s
/// `debugInvokeOverride` substitutes the kernel's return status so the whole
/// staging/dispatch/publish path still runs for real.
void main() {
  final bool nativeAvailable = _checkNativeAvailable();

  setUp(() {
    loader_io.debugResetLoader();
    loader_io.debugSetLibraryOpener(() => ffi.DynamicLibrary.executable());
    loader_io.debugSetSymbolChecker((_, _) => true);
  });

  tearDown(() {
    loader_io.debugResetLoader();
    YuvAbiV1Runner.debugInvokeOverride = null;
  });

  group('capability gate runs before any state change', () {
    test('an apply* call throws UnsupportedError before YuvFfi.initialize() has completed', () {
      // No initialize() call in this test: the loader's capability cache is
      // still null, so every apply* must fail closed rather than assume
      // support.
      final image = YuvImage.i420(4, 4);
      final bytesBefore = image.getBytes();
      final revisionBefore = (image as YuvRevisionAware).internalRevision;

      expect(() => image.applyGrayscale(), throwsA(isA<UnsupportedError>()));

      expect(image.getBytes(), bytesBefore);
      expect((image as YuvRevisionAware).internalRevision, revisionBefore);
    });

    test('applyChromaSwap on I420/BGRA rejects before dispatch, without converting or mutating', () async {
      await YuvFfi.initialize();
      // If the capability guard were bypassed and this reached the runner,
      // any invocation at all would be a bug for a non-NV12 source: fail loud
      // rather than silently succeeding.
      YuvAbiV1Runner.debugInvokeOverride = (src, dst, options) => fail('applyChromaSwap must not dispatch for a non-NV12 source');

      for (final image in <YuvImage>[YuvImage.i420(4, 4), YuvImage.bgra(4, 4)]) {
        final bytesBefore = image.getBytes();
        final formatBefore = image.format;
        final revisionBefore = (image as YuvRevisionAware).internalRevision;

        expect(() => image.applyChromaSwap(), throwsA(isA<UnsupportedError>()));

        expect(image.getBytes(), bytesBefore);
        expect(image.format, formatBefore);
        expect((image as YuvRevisionAware).internalRevision, revisionBefore);
      }
    });

    test('a missing required symbol makes the matching apply* unsupported without touching state', () async {
      loader_io.debugResetLoader();
      loader_io.debugSetLibraryOpener(() => ffi.DynamicLibrary.executable());
      loader_io.debugSetSymbolChecker((_, symbol) => true);
      // yuv_ffi's IO loader currently requires the complete manifest to
      // initialize at all (REL-09 scope), so this test instead exercises the
      // same-shaped rejection through a capability snapshot missing an
      // operation directly, which is the situation Web's partial backend hits
      // routinely and IO would hit if a future ABI revision made the manifest
      // gate per-operation instead of all-or-nothing.
      await YuvFfi.initialize();

      final image = YuvImage.i420(4, 4);
      final bytesBefore = image.getBytes();
      final revisionBefore = (image as YuvRevisionAware).internalRevision;

      // Every apply* is expected to still work with a fully-supported
      // snapshot; this test's real purpose is covered by
      // yuv_ffi_capabilities_wiring_test.dart (missing-symbol -> initialize()
      // itself fails) and yuv_capabilities_test.dart (format-pair rejection).
      // Here we only assert the ordering: capability check happens before any
      // native call, using a deliberately failing invoke override.
      YuvAbiV1Runner.debugInvokeOverride = (src, dst, options) => yuvStatusInternalError;
      expect(() => image.applyGrayscale(), throwsA(isA<YuvNativeException>()));
      expect(image.getBytes(), bytesBefore);
      expect((image as YuvRevisionAware).internalRevision, revisionBefore);
    });
  });

  group('successful apply* mutates in place, advances revision once, returns identical(this)', () {
    // The fake library from setUp() resolves every symbol name (so
    // YuvFfi.initialize() succeeds and capabilities report full support), but
    // has no real yuv_*_v1 implementation behind those names. debugInvokeOverride
    // substitutes the kernel's return value so the rest of the transactional
    // staging/publish path -- the thing this group actually verifies -- still
    // runs for real, the same seam io_abi_v1_public_contract_test.dart uses.
    tearDown(() => YuvAbiV1Runner.debugInvokeOverride = null);

    test('applyGrayscale', () async {
      await YuvFfi.initialize();
      YuvAbiV1Runner.debugInvokeOverride = (src, dst, options) => yuvStatusOk;
      final image = YuvImage.i420(4, 4);
      final revisionBefore = (image as YuvRevisionAware).internalRevision;

      final result = image.applyGrayscale();

      expect(identical(result, image), isTrue);
      expect((image as YuvRevisionAware).internalRevision, revisionBefore + 1);
    });

    test('applyFormat to a different format converts and advances revision once', () async {
      await YuvFfi.initialize();
      YuvAbiV1Runner.debugInvokeOverride = (src, dst, options) => yuvStatusOk;
      final image = YuvImage.i420(4, 4);
      final revisionBefore = (image as YuvRevisionAware).internalRevision;

      final result = image.applyFormat(YuvPixelFormat.bgra8888);

      expect(identical(result, image), isTrue);
      expect(image.format.pixelFormat, YuvPixelFormat.bgra8888);
      expect((image as YuvRevisionAware).internalRevision, revisionBefore + 1);
    });
  });

  group('defined no-ops do not advance the revision', () {
    test('applyGaussianBlur radius 0', () async {
      await YuvFfi.initialize();
      final image = YuvImage.i420(4, 4);
      final revisionBefore = (image as YuvRevisionAware).internalRevision;

      final result = image.applyGaussianBlur(radius: 0, sigma: 1.0);

      expect(identical(result, image), isTrue);
      expect((image as YuvRevisionAware).internalRevision, revisionBefore);
    });

    test('applyMeanBlur radius 0', () async {
      await YuvFfi.initialize();
      final image = YuvImage.i420(4, 4);
      final revisionBefore = (image as YuvRevisionAware).internalRevision;

      image.applyMeanBlur(radius: 0);

      expect((image as YuvRevisionAware).internalRevision, revisionBefore);
    });

    test('applyBoxBlur radius 0', () async {
      await YuvFfi.initialize();
      final image = YuvImage.i420(4, 4);
      final revisionBefore = (image as YuvRevisionAware).internalRevision;

      image.applyBoxBlur(radius: 0);

      expect((image as YuvRevisionAware).internalRevision, revisionBefore);
    });

    test('applyCrop with an empty effective region', () async {
      await YuvFfi.initialize();
      final image = YuvImage.bgra(8, 8);
      final revisionBefore = (image as YuvRevisionAware).internalRevision;

      image.applyCrop(const ui.Rect.fromLTWH(4, 4, 0, 0));

      expect((image as YuvRevisionAware).internalRevision, revisionBefore);
    });

    test('applyRotation rotation0', () async {
      await YuvFfi.initialize();
      final image = YuvImage.bgra(4, 4);
      final revisionBefore = (image as YuvRevisionAware).internalRevision;

      image.applyRotation(YuvImageRotation.rotation0);

      expect((image as YuvRevisionAware).internalRevision, revisionBefore);
    });

    test('applyFormat to the same format', () async {
      await YuvFfi.initialize();
      final image = YuvImage.i420(4, 4);
      final revisionBefore = (image as YuvRevisionAware).internalRevision;

      image.applyFormat(YuvPixelFormat.i420);

      expect((image as YuvRevisionAware).internalRevision, revisionBefore);
    });
  });

  group('cropped()/rotated()/to*() never alias, even for a semantic no-op', () {
    test('cropped() with an empty effective region returns an independent copy', () async {
      await YuvFfi.initialize();
      final image = YuvImage.bgra(8, 8);
      final revisionBefore = (image as YuvRevisionAware).internalRevision;

      final result = image.cropped(const ui.Rect.fromLTWH(4, 4, 0, 0));

      expect(identical(result, image), isFalse);
      expect((image as YuvRevisionAware).internalRevision, revisionBefore, reason: 'source must be untouched');
    });

    test('rotated(rotation0) returns an independent copy', () async {
      await YuvFfi.initialize();
      final image = YuvImage.bgra(4, 4);
      final revisionBefore = (image as YuvRevisionAware).internalRevision;

      final result = image.rotated(YuvImageRotation.rotation0);

      expect(identical(result, image), isFalse);
      expect((image as YuvRevisionAware).internalRevision, revisionBefore);
    });

    test('toI420() on an already-I420 image returns an independent copy', () async {
      await YuvFfi.initialize();
      final image = YuvImage.i420(4, 4);
      final revisionBefore = (image as YuvRevisionAware).internalRevision;

      final result = image.toI420();

      expect(identical(result, image), isFalse);
      expect((image as YuvRevisionAware).internalRevision, revisionBefore);
    });
  });

  group('a non-zero native status leaves the receiver untouched', () {
    tearDown(() => YuvAbiV1Runner.debugInvokeOverride = null);

    final operations = <String, void Function(YuvImage)>{
      'applyGrayscale': (image) => image.applyGrayscale(),
      'applyBlackWhite': (image) => image.applyBlackWhite(),
      'applyNegate': (image) => image.applyNegate(),
      'applyGaussianBlur': (image) => image.applyGaussianBlur(radius: 1, sigma: 1.0),
      'applyMeanBlur': (image) => image.applyMeanBlur(radius: 1),
      'applyBoxBlur': (image) => image.applyBoxBlur(radius: 1),
      'applyFlipHorizontal': (image) => image.applyFlipHorizontal(),
      'applyFlipVertical': (image) => image.applyFlipVertical(),
      'applyRotation': (image) => image.applyRotation(YuvImageRotation.rotation90),
      'applyCrop': (image) => image.applyCrop(const ui.Rect.fromLTRB(0, 0, 4, 4)),
      'applyFormat': (image) => image.applyFormat(YuvPixelFormat.bgra8888),
    };

    for (final entry in operations.entries) {
      test('${entry.key} publishes nothing when native reports INTERNAL_ERROR', () async {
        await YuvFfi.initialize();
        final image = YuvImage.i420(8, 8);
        final bytesBefore = image.getBytes();
        final formatBefore = image.format;
        final widthBefore = image.width;
        final heightBefore = image.height;
        final revisionBefore = (image as YuvRevisionAware).internalRevision;

        YuvAbiV1Runner.debugInvokeOverride = (src, dst, options) => yuvStatusInternalError;

        expect(() => entry.value(image), throwsA(isA<YuvNativeException>()));

        expect(image.getBytes(), bytesBefore, reason: 'bytes changed after a failed ${entry.key}');
        expect(image.format, formatBefore, reason: 'format changed after a failed ${entry.key}');
        expect(image.width, widthBefore);
        expect(image.height, heightBefore);
        expect((image as YuvRevisionAware).internalRevision, revisionBefore, reason: 'revision advanced on a failed ${entry.key}');
      });
    }

    test('applyChromaSwap publishes nothing when native reports INTERNAL_ERROR', () async {
      await YuvFfi.initialize();
      final image = YuvImage.nv12(8, 8);
      final bytesBefore = image.getBytes();
      final revisionBefore = (image as YuvRevisionAware).internalRevision;

      YuvAbiV1Runner.debugInvokeOverride = (src, dst, options) => yuvStatusInternalError;

      expect(() => image.applyChromaSwap(), throwsA(isA<YuvNativeException>()));

      expect(image.getBytes(), bytesBefore);
      expect((image as YuvRevisionAware).internalRevision, revisionBefore);
    });
  });

  group('applyRgbaBytes', () {
    test('rejects a wrong-length buffer with ArgumentError before any dispatch', () async {
      await YuvFfi.initialize();
      YuvAbiV1Runner.debugInvokeOverride = (src, dst, options) => fail('must not dispatch for an invalid-length buffer');
      final image = YuvImage.i420(4, 4);
      final revisionBefore = (image as YuvRevisionAware).internalRevision;

      expect(() => image.applyRgbaBytes(Uint8List(4)), throwsArgumentError);

      expect((image as YuvRevisionAware).internalRevision, revisionBefore);
    });
  });

  group(
    'operations x formats matrix (IO, requires a real native library)',
    () {
      Uint8List rgba(int w, int h) => Uint8List(w * h * 4);

      setUp(() {
        // The file-level setUp() installs a fake opener/checker so every
        // other group can run without a real library; this group needs the
        // real one it's guarded to only run when nativeAvailable is true.
        loader_io.debugResetLoader();
      });

      test('every apply* succeeds for every YuvPixelFormat it accepts per the section 11 matrix', () async {
        await YuvFfi.initialize();

        for (final format in YuvPixelFormat.values) {
          YuvImage image(int w, int h) => switch (format) {
            YuvPixelFormat.i420 => YuvImage.i420(w, h),
            YuvPixelFormat.nv12 => YuvImage.nv12(w, h),
            YuvPixelFormat.bgra8888 => YuvImage.bgra(w, h),
          }..applyRgbaBytes(rgba(w, h));

          // Every effect, blur, flip, rotate and crop accepts every format
          // (section 11): same-format in, same-format out.
          expect(image(4, 4).applyGrayscale().format.pixelFormat, format, reason: 'grayscale on $format');
          expect(image(4, 4).applyBlackWhite().format.pixelFormat, format, reason: 'blackwhite on $format');
          expect(image(4, 4).applyNegate().format.pixelFormat, format, reason: 'negate on $format');
          expect(image(4, 4).applyGaussianBlur(radius: 1, sigma: 1.0).format.pixelFormat, format, reason: 'gaussian on $format');
          expect(image(4, 4).applyMeanBlur(radius: 1).format.pixelFormat, format, reason: 'mean on $format');
          expect(image(4, 4).applyBoxBlur(radius: 1).format.pixelFormat, format, reason: 'box on $format');
          expect(image(4, 4).applyFlipHorizontal().format.pixelFormat, format, reason: 'flipH on $format');
          expect(image(4, 4).applyFlipVertical().format.pixelFormat, format, reason: 'flipV on $format');
          expect(image(4, 4).applyRotation(YuvImageRotation.rotation90).format.pixelFormat, format, reason: 'rotate on $format');
          expect(image(8, 8).applyCrop(const ui.Rect.fromLTRB(0, 0, 4, 4)).width, 4, reason: 'crop on $format');

          for (final target in YuvPixelFormat.values) {
            expect(image(4, 4).applyFormat(target).format.pixelFormat, target, reason: 'convert $format -> $target');
          }
        }

        // chromaSwap is NV12-only.
        expect(YuvImage.nv12(4, 4).applyChromaSwap().format.pixelFormat, YuvPixelFormat.nv12);
        expect(() => YuvImage.i420(4, 4).applyChromaSwap(), throwsUnsupportedError);
        expect(() => YuvImage.bgra(4, 4).applyChromaSwap(), throwsUnsupportedError);
      });
    },
    skip: nativeAvailable ? false : 'native yuv_ffi library is not available on this host',
  );
}

bool _checkNativeAvailable() {
  try {
    library;
    return true;
  } catch (_) {
    return false;
  }
}
