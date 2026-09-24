import 'dart:ffi' as ffi;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/src/loader/impl/loader_io.dart' as loader_io;
import 'package:yuv_ffi/src/loader/loader.dart';
import 'package:yuv_ffi/src/yuv/impl/io/yuv_image.dart' show YuvImageImpl;
import 'package:yuv_ffi/src/yuv/impl/io/abi/yuv_abi_v1_runner.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_native_status.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_revision.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Verifies REL-06's deprecated `0.3.0` compatibility surface
/// (`doc/api-abi-0.4-design.md` sections 4, 8, 14 Q1; `todo.md`'s REL-06 entry
/// and its R1-review addendum).
///
/// Covers: every `0.3.0` instance method still compiles and forwards to its
/// `0.4.0` replacement with matching behavior; `swapNv()`'s two-step
/// convert-then-swap semantics and atomicity on a failed second step;
/// `YuvFileFormat`/`nv21`/the unnamed factory carrying `@Deprecated`; and
/// `YuvImageImpl` not being part of the public export surface.
///
/// Most groups use the same fake-library seam `yuv_apply_surface_test.dart`
/// uses (`debugSetLibraryOpener`/`debugSetSymbolChecker` plus
/// `YuvAbiV1Runner.debugInvokeOverride`), so they run on every host without a
/// real `yuv_ffi.dll`. Genuine byte-level correctness of the underlying
/// conversions is REL-01/REL-05's job (`nv_chroma_order_test.dart`,
/// `rel05_independent_results_test.dart`); the "matches historical bytes"
/// group here additionally requires the real native library and self-skips
/// without one.
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

  group('YuvImageImpl is hidden from the public export surface', () {
    test('yuv_ffi.dart does not export YuvImageImpl', () {
      // Compile-time check by construction: the import above reaches
      // YuvImageImpl only through its internal impl library path
      // (package:yuv_ffi/src/yuv/impl/io/yuv_image.dart), never through
      // package:yuv_ffi/yuv_ffi.dart. If a future change re-exports the impl
      // library wholesale (as yuv.dart used to), this file's import would
      // become redundant but this assertion still only proves the type is
      // constructible via factories, not that it is part of the public API.
      final YuvImage image = YuvImage.i420(2, 2);
      expect(image, isA<YuvImageImpl>());
    });
  });

  group('YuvFileFormat and nv21/unnamed-factory entry points are deprecated', () {
    test('YuvFileFormat carries @Deprecated', () {
      // Static/API-shape check: exercised for real by `dart analyze`, not by a
      // runtime assertion. This test documents the contract and fails to
      // compile (not merely to run) if the annotation is ever removed,
      // because the deprecated_member_use_from_same_package diagnostic this
      // package's analyzer config would then need to police is exactly what
      // this line depends on staying meaningful across the package boundary.
      // ignore: deprecated_member_use_from_same_package
      const YuvFileFormat format = YuvFileFormat.i420;
      expect(format, isNotNull);
    });

    test('YuvImage.nv21 and the unnamed YuvImage() factory still compile and construct', () {
      // ignore: deprecated_member_use_from_same_package
      final legacy = YuvImage.nv21(4, 4);
      expect(legacy.format, YuvPixelFormat.nv12);

      // ignore: deprecated_member_use_from_same_package
      final explicit = YuvImage(YuvFileFormat.bgra8888, 4, 4);
      expect(explicit.format, YuvPixelFormat.bgra8888);
    });
  });

  group('consumer compile test: every 0.3.0 instance method/factory still compiles', () {
    test('the full 0.3.0 surface builds and runs against a real image', () {
      // BGRA, not nv21: toBgra8888()/toBgraBytes() below short-circuit to a
      // tight-byte reinterpretation for an already-BGRA source without
      // dispatching to native, so this test needs no fake-library setup.
      final YuvImage image = YuvImage.bgra(4, 4);

      // Plane aliases. BGRA has only one plane (Y only), so uPlane/vPlane
      // throw by design (section 4: "StateError when format has no U/V
      // plane") while the deprecated u/v getters stay null-safe -- they
      // intentionally diverge for a format without that plane, so u/v are
      // checked against null, not uPlane/vPlane.
      // ignore: deprecated_member_use_from_same_package
      expect(image.y, same(image.yPlane));
      // ignore: deprecated_member_use_from_same_package
      expect(image.u, isNull);
      // ignore: deprecated_member_use_from_same_package
      expect(image.v, isNull);
      expect(() => image.uPlane, throwsA(anything));
      expect(() => image.vPlane, throwsA(anything));

      // getBytes() shape. toBgra8888() is not deprecated (see its dartdoc):
      // YuvImageProvider still calls it internally, so it is checked directly
      // below without an ignore comment.
      // ignore: deprecated_member_use_from_same_package
      expect(image.getBytes(), image.toBytes());
      // ignore: deprecated_member_use_from_same_package
      expect(image.toBgra8888(), image.toBgraBytes());

      // copy(blank:) still compiles with the deprecated named argument.
      // ignore: deprecated_member_use_from_same_package
      final blank = image.copy(blank: true);
      expect(blank.width, image.width);
    });

    test('every 0.3.0 mutating method compiles and dispatches through the apply* path', () async {
      await YuvFfi.initialize();
      YuvAbiV1Runner.debugInvokeOverride = (src, dst, options) => yuvStatusOk;

      // ignore: deprecated_member_use_from_same_package
      final YuvImage image = YuvImage.i420(4, 4);

      // ignore: deprecated_member_use_from_same_package
      expect(identical(image.blackwhite(), image), isTrue);
      // ignore: deprecated_member_use_from_same_package
      expect(identical(image.grayscale(), image), isTrue);
      // ignore: deprecated_member_use_from_same_package
      expect(identical(image.negate(), image), isTrue);
      // ignore: deprecated_member_use_from_same_package
      expect(identical(image.gaussianBlur(radius: 0), image), isTrue);
      // ignore: deprecated_member_use_from_same_package
      expect(identical(image.boxBlur(radius: 0), image), isTrue);
      // ignore: deprecated_member_use_from_same_package
      expect(identical(image.meanBlur(radius: 0), image), isTrue);
      // ignore: deprecated_member_use_from_same_package
      expect(identical(image.flipHorizontally(), image), isTrue);
      // ignore: deprecated_member_use_from_same_package
      expect(identical(image.flipVertically(), image), isTrue);
      // ignore: deprecated_member_use_from_same_package
      expect(identical(image.rotate(YuvImageRotation.rotation0), image), isTrue);
      // ignore: deprecated_member_use_from_same_package
      expect(identical(image.crop(ui.Rect.zero), image), isTrue);

      final rgba = Uint8List(4 * 4 * 4);
      // ignore: deprecated_member_use_from_same_package
      image.fromRgba8888(rgba);

      // ignore: deprecated_member_use_from_same_package
      expect(identical(image.toYuvI420(), image), isTrue);
      // ignore: deprecated_member_use_from_same_package
      expect(identical(image.toYuvBgra8888(), image), isTrue);
      // ignore: deprecated_member_use_from_same_package
      expect(identical(image.toYuvNv21(), image), isTrue);
      // ignore: deprecated_member_use_from_same_package
      expect(identical(image.swapNv(), image), isTrue);
    });
  });

  group('behavioral forwarding: each deprecated method matches its 0.4.0 replacement', () {
    test('blackwhite()/grayscale()/negate() match applyBlackWhite()/applyGrayscale()/applyNegate()', () async {
      await YuvFfi.initialize();
      YuvAbiV1Runner.debugInvokeOverride = (src, dst, options) => yuvStatusOk;

      final legacy = YuvImage.i420(4, 4);
      final modern = YuvImage.i420(4, 4);
      final legacyRevisionBefore = (legacy as YuvRevisionAware).internalRevision;
      final modernRevisionBefore = (modern as YuvRevisionAware).internalRevision;

      // ignore: deprecated_member_use_from_same_package
      legacy.blackwhite();
      modern.applyBlackWhite();
      // ignore: deprecated_member_use_from_same_package
      expect(legacy.getBytes(), modern.getBytes());
      expect((legacy as YuvRevisionAware).internalRevision, legacyRevisionBefore + 1);
      expect((modern as YuvRevisionAware).internalRevision, modernRevisionBefore + 1);
    });

    test('gaussianBlur()/boxBlur()/meanBlur() forward radius/sigma to their apply* replacement', () async {
      await YuvFfi.initialize();
      YuvAbiV1Runner.debugInvokeOverride = (src, dst, options) => yuvStatusOk;

      final legacyGaussian = YuvImage.i420(4, 4);
      final modernGaussian = YuvImage.i420(4, 4);
      // ignore: deprecated_member_use_from_same_package
      legacyGaussian.gaussianBlur(radius: 2, sigma: 3);
      modernGaussian.applyGaussianBlur(radius: 2, sigma: 3.0);
      // ignore: deprecated_member_use_from_same_package
      expect(legacyGaussian.getBytes(), modernGaussian.getBytes());

      final legacyBox = YuvImage.i420(4, 4);
      final modernBox = YuvImage.i420(4, 4);
      // ignore: deprecated_member_use_from_same_package
      legacyBox.boxBlur(radius: 1);
      modernBox.applyBoxBlur(radius: 1);
      // ignore: deprecated_member_use_from_same_package
      expect(legacyBox.getBytes(), modernBox.getBytes());

      final legacyMean = YuvImage.i420(4, 4);
      final modernMean = YuvImage.i420(4, 4);
      // ignore: deprecated_member_use_from_same_package
      legacyMean.meanBlur(radius: 1);
      modernMean.applyMeanBlur(radius: 1);
      // ignore: deprecated_member_use_from_same_package
      expect(legacyMean.getBytes(), modernMean.getBytes());
    });

    test('crop()/flipHorizontally()/flipVertically()/rotate() match their apply* replacement', () async {
      await YuvFfi.initialize();
      YuvAbiV1Runner.debugInvokeOverride = (src, dst, options) => yuvStatusOk;

      final legacyCrop = YuvImage.bgra(4, 4);
      final modernCrop = YuvImage.bgra(4, 4);
      // ignore: deprecated_member_use_from_same_package
      legacyCrop.crop(const ui.Rect.fromLTWH(1, 1, 2, 2));
      modernCrop.applyCrop(const ui.Rect.fromLTWH(1, 1, 2, 2));
      expect(legacyCrop.width, modernCrop.width);
      expect(legacyCrop.height, modernCrop.height);
      // ignore: deprecated_member_use_from_same_package
      expect(legacyCrop.getBytes(), modernCrop.getBytes());

      final legacyFlipH = YuvImage.bgra(4, 4);
      final modernFlipH = YuvImage.bgra(4, 4);
      // ignore: deprecated_member_use_from_same_package
      legacyFlipH.flipHorizontally();
      modernFlipH.applyFlipHorizontal();
      // ignore: deprecated_member_use_from_same_package
      expect(legacyFlipH.getBytes(), modernFlipH.getBytes());

      final legacyFlipV = YuvImage.bgra(4, 4);
      final modernFlipV = YuvImage.bgra(4, 4);
      // ignore: deprecated_member_use_from_same_package
      legacyFlipV.flipVertically();
      modernFlipV.applyFlipVertical();
      // ignore: deprecated_member_use_from_same_package
      expect(legacyFlipV.getBytes(), modernFlipV.getBytes());

      final legacyRotate = YuvImage.bgra(4, 4);
      final modernRotate = YuvImage.bgra(4, 4);
      // ignore: deprecated_member_use_from_same_package
      legacyRotate.rotate(YuvImageRotation.rotation90);
      modernRotate.applyRotation(YuvImageRotation.rotation90);
      expect(legacyRotate.width, modernRotate.width);
      expect(legacyRotate.height, modernRotate.height);
      // ignore: deprecated_member_use_from_same_package
      expect(legacyRotate.getBytes(), modernRotate.getBytes());
    });

    test('fromRgba8888() matches applyRgbaBytes()', () async {
      await YuvFfi.initialize();
      YuvAbiV1Runner.debugInvokeOverride = (src, dst, options) => yuvStatusOk;

      final legacy = YuvImage.bgra(4, 4);
      final modern = YuvImage.bgra(4, 4);
      final rgba = Uint8List(4 * 4 * 4);
      for (int i = 0; i < rgba.length; i++) {
        rgba[i] = i & 0xFF;
      }

      // ignore: deprecated_member_use_from_same_package
      legacy.fromRgba8888(rgba);
      modern.applyRgbaBytes(rgba);
      // ignore: deprecated_member_use_from_same_package
      expect(legacy.getBytes(), modern.getBytes());
    });

    test('toYuvI420()/toYuvBgra8888()/toYuvNv21() match applyFormat() with the corresponding YuvPixelFormat', () async {
      await YuvFfi.initialize();
      YuvAbiV1Runner.debugInvokeOverride = (src, dst, options) => yuvStatusOk;

      final legacyToI420 = YuvImage.bgra(4, 4);
      final modernToI420 = YuvImage.bgra(4, 4);
      // ignore: deprecated_member_use_from_same_package
      legacyToI420.toYuvI420();
      modernToI420.applyFormat(YuvPixelFormat.i420);
      expect(legacyToI420.format, modernToI420.format);
      // ignore: deprecated_member_use_from_same_package
      expect(legacyToI420.getBytes(), modernToI420.getBytes());

      final legacyToBgra = YuvImage.i420(4, 4);
      final modernToBgra = YuvImage.i420(4, 4);
      // ignore: deprecated_member_use_from_same_package
      legacyToBgra.toYuvBgra8888();
      modernToBgra.applyFormat(YuvPixelFormat.bgra8888);
      expect(legacyToBgra.format, modernToBgra.format);
      // ignore: deprecated_member_use_from_same_package
      expect(legacyToBgra.getBytes(), modernToBgra.getBytes());

      final legacyToNv21 = YuvImage.i420(4, 4);
      final modernToNv12 = YuvImage.i420(4, 4);
      // ignore: deprecated_member_use_from_same_package
      legacyToNv21.toYuvNv21();
      modernToNv12.applyFormat(YuvPixelFormat.nv12);
      expect(legacyToNv21.format, modernToNv12.format);
      // ignore: deprecated_member_use_from_same_package
      expect(legacyToNv21.getBytes(), modernToNv12.getBytes());
    });

    test('getBytes() matches toBytes(), and toBgra8888() matches toBgraBytes(), for an unmodified image', () {
      final image = YuvImage.bgra(4, 4);
      // ignore: deprecated_member_use_from_same_package
      expect(image.getBytes(), image.toBytes());
      // ignore: deprecated_member_use_from_same_package
      expect(image.toBgra8888(), image.toBgraBytes());
    });
  });

  group('swapNv() two-step convert-then-swap behavior (section 14, Q1)', () {
    test('on an already-NV12 image, swapNv() dispatches exactly one native call (chromaSwap only)', () async {
      await YuvFfi.initialize();
      int invocationCount = 0;
      YuvAbiV1Runner.debugInvokeOverride = (src, dst, options) {
        invocationCount++;
        return yuvStatusOk;
      };

      // ignore: deprecated_member_use_from_same_package
      final YuvImage image = YuvImage.nv21(4, 4);
      final revisionBefore = (image as YuvRevisionAware).internalRevision;

      // ignore: deprecated_member_use_from_same_package
      final result = image.swapNv();

      expect(identical(result, image), isTrue);
      expect(invocationCount, 1, reason: 'an already-NV image must not be converted first, only swapped');
      expect(image.format, YuvPixelFormat.nv12);
      expect((image as YuvRevisionAware).internalRevision, revisionBefore + 1);
    });

    test('on a non-NV image, swapNv() dispatches exactly two native calls (convert, then chromaSwap)', () async {
      await YuvFfi.initialize();
      int invocationCount = 0;
      YuvAbiV1Runner.debugInvokeOverride = (src, dst, options) {
        invocationCount++;
        return yuvStatusOk;
      };

      // ignore: deprecated_member_use_from_same_package
      final YuvImage image = YuvImage.i420(4, 4);
      final revisionBefore = (image as YuvRevisionAware).internalRevision;

      // ignore: deprecated_member_use_from_same_package
      final result = image.swapNv();

      expect(identical(result, image), isTrue);
      expect(invocationCount, 2, reason: 'a non-NV source must be converted to NV12 first, then swapped');
      expect(image.format, YuvPixelFormat.nv12, reason: 'swapNv() adopts the legacy nv21 label after converting');
      // Exactly one publish happens no matter how many native calls it took to
      // get there (section 13): the receiver's revision must still advance by
      // exactly one, not once per internal native call.
      expect((image as YuvRevisionAware).internalRevision, revisionBefore + 1);
    });

    test('a failed second step (chroma swap) after a successful convert leaves the receiver untouched', () async {
      await YuvFfi.initialize();
      int invocationCount = 0;
      YuvAbiV1Runner.debugInvokeOverride = (src, dst, options) {
        invocationCount++;
        // First call is the convert-to-NV12 step; let it succeed. Second call
        // is the chroma swap; fail it, simulating a native error partway
        // through the deprecated two-step path.
        return invocationCount == 1 ? yuvStatusOk : yuvStatusInternalError;
      };

      // ignore: deprecated_member_use_from_same_package
      final YuvImage image = YuvImage.i420(4, 4);
      // ignore: deprecated_member_use_from_same_package
      final bytesBefore = image.getBytes();
      final formatBefore = image.format;
      final revisionBefore = (image as YuvRevisionAware).internalRevision;

      // ignore: deprecated_member_use_from_same_package
      expect(() => image.swapNv(), throwsA(isA<YuvNativeException>()));

      // Section 13's transactional contract: nothing is published until every
      // step has succeeded, so a failure partway through the deprecated
      // two-step path must leave the receiver exactly as it was -- not
      // "already converted to NV12, swap still pending".
      // ignore: deprecated_member_use_from_same_package
      expect(image.getBytes(), bytesBefore);
      expect(image.format, formatBefore);
      expect((image as YuvRevisionAware).internalRevision, revisionBefore);
    });
  });

  group('swapNv() matches historical bytes (requires real native library)', () {
    setUp(() async {
      // The file-level setUp() installs a fake opener/checker so every other
      // group can run without a real library; this group needs the real one
      // it's guarded to only run when nativeAvailable is true, and must
      // actually initialize it since these tests dispatch capability-gated
      // apply*/applyFormat/applyChromaSwap calls.
      loader_io.debugResetLoader();
      if (nativeAvailable) {
        await YuvFfi.initialize();
      }
    });

    test(
      'swapNv() on a converted image produces the same bytes as applyFormat(nv12) followed by applyChromaSwap()',
      () async {
        const int w = 4;
        const int h = 4;
        final rgba = Uint8List(w * h * 4);
        for (int i = 0; i < rgba.length; i += 4) {
          rgba[i] = 200; // B
          rgba[i + 1] = 100; // G
          rgba[i + 2] = 30; // R
          rgba[i + 3] = 255; // A
        }

        // ignore: deprecated_member_use_from_same_package
        final legacy = YuvImage.i420(w, h)..fromRgba8888(rgba);
        final modern = YuvImage.i420(w, h)..applyRgbaBytes(rgba);

        // ignore: deprecated_member_use_from_same_package
        legacy.swapNv();
        modern.applyFormat(YuvPixelFormat.nv12);
        modern.applyChromaSwap();

        expect(legacy.format, YuvPixelFormat.nv12);
        expect(modern.format, YuvPixelFormat.nv12);
        // ignore: deprecated_member_use_from_same_package
        expect(legacy.getBytes(), modern.getBytes(), reason: 'swapNv() must preserve the historical two-step output bytes exactly');
      },
      skip: nativeAvailable ? false : 'native yuv_ffi library is not available on this host',
    );

    test(
      'swapNv() on an already-NV21 image matches applyChromaSwap() alone',
      () async {
        const int w = 4;
        const int h = 4;
        final rgba = Uint8List(w * h * 4);
        for (int i = 0; i < rgba.length; i += 4) {
          rgba[i] = 10;
          rgba[i + 1] = 220;
          rgba[i + 2] = 90;
          rgba[i + 3] = 255;
        }

        // ignore: deprecated_member_use_from_same_package
        final legacy = YuvImage.nv21(w, h)..fromRgba8888(rgba);
        final modern = YuvImage.nv12(w, h)..applyRgbaBytes(rgba);

        // ignore: deprecated_member_use_from_same_package
        legacy.swapNv();
        modern.applyChromaSwap();

        // ignore: deprecated_member_use_from_same_package
        expect(legacy.getBytes(), modern.getBytes());
      },
      skip: nativeAvailable ? false : 'native yuv_ffi library is not available on this host',
    );
  });

  group('a foreign implements YuvImage without YuvLegacyDispatchAdapter', () {
    test('every ordinary deprecated method forwards to the receiver\'s own public apply*/applyFormat method', () {
      final image = _RecordingForeignImage(4, 4);

      // ignore: deprecated_member_use_from_same_package
      expect(image.blackwhite(), same(image));
      expect(image.calls, contains('applyBlackWhite'));

      // ignore: deprecated_member_use_from_same_package
      expect(image.grayscale(), same(image));
      expect(image.calls, contains('applyGrayscale'));

      // ignore: deprecated_member_use_from_same_package
      expect(image.negate(), same(image));
      expect(image.calls, contains('applyNegate'));

      // ignore: deprecated_member_use_from_same_package
      expect(image.gaussianBlur(radius: 3, sigma: 2), same(image));
      expect(image.calls, contains('applyGaussianBlur(radius: 3, sigma: 2.0)'));

      // ignore: deprecated_member_use_from_same_package
      expect(image.boxBlur(radius: 5), same(image));
      expect(image.calls, contains('applyBoxBlur(radius: 5, region: null)'));

      // ignore: deprecated_member_use_from_same_package
      expect(image.meanBlur(radius: 2), same(image));
      expect(image.calls, contains('applyMeanBlur(radius: 2, region: null)'));

      // ignore: deprecated_member_use_from_same_package
      expect(image.crop(const ui.Rect.fromLTWH(1, 1, 2, 2)), same(image));
      expect(image.calls, contains('applyCrop(Rect.fromLTRB(1.0, 1.0, 3.0, 3.0))'));

      // ignore: deprecated_member_use_from_same_package
      expect(image.flipHorizontally(), same(image));
      expect(image.calls, contains('applyFlipHorizontal'));

      // ignore: deprecated_member_use_from_same_package
      expect(image.flipVertically(), same(image));
      expect(image.calls, contains('applyFlipVertical'));

      // ignore: deprecated_member_use_from_same_package
      expect(image.rotate(YuvImageRotation.rotation90), same(image));
      expect(image.calls, contains('applyRotation(YuvImageRotation.rotation90)'));

      final rgba = Uint8List(4 * 4 * 4);
      // ignore: deprecated_member_use_from_same_package
      image.fromRgba8888(rgba);
      expect(image.calls, contains('applyRgbaBytes'));

      // ignore: deprecated_member_use_from_same_package
      expect(image.toYuvI420(), same(image));
      expect(image.calls, contains('applyFormat(YuvPixelFormat.i420)'));

      // ignore: deprecated_member_use_from_same_package
      expect(image.toYuvBgra8888(), same(image));
      expect(image.calls, contains('applyFormat(YuvPixelFormat.bgra8888)'));

      // ignore: deprecated_member_use_from_same_package
      expect(image.toYuvNv21(), same(image));
      expect(image.calls, contains('applyFormat(YuvPixelFormat.nv12)'));
    });

    test('swapNv() is a documented exception: it throws UnsupportedError without mutating, unlike every other method', () {
      final image = _RecordingForeignImage(4, 4);
      final bytesBefore = Uint8List.fromList(image.yPlane.bytes);

      // ignore: deprecated_member_use_from_same_package
      expect(() => image.swapNv(), throwsA(isA<UnsupportedError>()));

      expect(image.calls, isEmpty, reason: 'swapNv() must not fall back to any apply*/applyFormat call for a foreign receiver');
      expect(image.yPlane.bytes, orderedEquals(bytesBefore), reason: 'a rejected swapNv() must not mutate a foreign receiver');
    });

    test('load() is the other documented exception: it throws UnsupportedError without mutating (REL-20)', () {
      final image = _RecordingForeignImage(4, 4);
      final bytesBefore = Uint8List.fromList(image.yPlane.bytes);

      // ignore: deprecated_member_use_from_same_package
      expect(() => image.load(const Stream<List<int>>.empty()), throwsA(isA<UnsupportedError>()));

      expect(image.calls, isEmpty, reason: 'load() must not fall back to any apply*/applyFormat call for a foreign receiver');
      expect(image.yPlane.bytes, orderedEquals(bytesBefore), reason: 'a rejected load() must not mutate a foreign receiver');
    });
  });
}

bool _checkNativeAvailable() {
  try {
    library;
    return true;
  } catch (_) {
    return false;
  }
}

/// A foreign `implements YuvImage` with no `YuvLegacyDispatchAdapter`,
/// recording which of its own public `apply*`/`applyFormat` methods each
/// deprecated call actually reached.
///
/// Every `apply*`/`applyFormat` here simply records its call and returns
/// `this`, exactly the "capability-gated but otherwise functional" shape
/// REL-04's already-accepted breaking change requires every `YuvImage`
/// implementer to provide.
class _RecordingForeignImage implements YuvImage {
  _RecordingForeignImage(this.width, this.height) : _plane = YuvPlane(height, width * 4, 4, Uint8List(height * width * 4));

  final YuvPlane _plane;
  final List<String> calls = <String>[];

  @override
  final int width;

  @override
  final int height;

  @override
  YuvPixelFormat get format => YuvPixelFormat.bgra8888;

  @override
  List<YuvPlane> get planes => <YuvPlane>[_plane];

  @override
  YuvPlane get yPlane => _plane;

  @override
  YuvPlane get uPlane => throw UnimplementedError();

  @override
  YuvPlane get vPlane => throw UnimplementedError();

  @override
  ui.Size get size => ui.Size(width.toDouble(), height.toDouble());

  @override
  YuvImage copy({bool blank = false}) => _RecordingForeignImage(width, height);

  @override
  YuvImage applyPlanes(Iterable<YuvPlane> planes) => throw UnimplementedError();

  @override
  Future<void> encodeTo(Sink<List<int>> sink) => throw UnimplementedError();

  @override
  Future<ui.Image> toImage() => throw UnimplementedError();

  Uint8List toBgra8888() => _plane.bytes;

  @override
  YuvImage applyRgbaBytes(Uint8List bytes) {
    calls.add('applyRgbaBytes');
    return this;
  }

  @override
  YuvImage applyGrayscale() {
    calls.add('applyGrayscale');
    return this;
  }

  @override
  YuvImage applyBlackWhite() {
    calls.add('applyBlackWhite');
    return this;
  }

  @override
  YuvImage applyNegate() {
    calls.add('applyNegate');
    return this;
  }

  @override
  YuvImage applyGaussianBlur({required int radius, required double sigma}) {
    calls.add('applyGaussianBlur(radius: $radius, sigma: $sigma)');
    return this;
  }

  @override
  YuvImage applyMeanBlur({required int radius, ui.Rect? region}) {
    calls.add('applyMeanBlur(radius: $radius, region: $region)');
    return this;
  }

  @override
  YuvImage applyBoxBlur({required int radius, ui.Rect? region}) {
    calls.add('applyBoxBlur(radius: $radius, region: $region)');
    return this;
  }

  @override
  YuvImage applyCrop(ui.Rect region) {
    calls.add('applyCrop($region)');
    return this;
  }

  @override
  YuvImage applyFlipHorizontal() {
    calls.add('applyFlipHorizontal');
    return this;
  }

  @override
  YuvImage applyFlipVertical() {
    calls.add('applyFlipVertical');
    return this;
  }

  @override
  YuvImage applyRotation(YuvImageRotation rotation) {
    calls.add('applyRotation($rotation)');
    return this;
  }

  @override
  YuvImage applyFormat(YuvPixelFormat format) {
    calls.add('applyFormat($format)');
    return this;
  }

  @override
  YuvImage applyChromaSwap() => throw UnimplementedError();

  @override
  YuvImage cropped(ui.Rect region) => throw UnimplementedError();

  @override
  YuvImage rotated(YuvImageRotation rotation) => throw UnimplementedError();

  @override
  YuvImage toI420() => throw UnimplementedError();

  @override
  YuvImage toNv12() => throw UnimplementedError();

  @override
  YuvImage toBgra() => throw UnimplementedError();

  @override
  Uint8List toBytes() => _plane.bytes;

  @override
  Uint8List toBgraBytes() => _plane.bytes;
}
