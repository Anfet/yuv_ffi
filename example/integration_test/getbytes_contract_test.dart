import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Web acceptance for YUV-14: `getBytes()` must return exactly the
/// concatenation of `plane.bytes`, with no alignment tail, on the real WASM
/// backend served by a browser.
///
/// This mirrors `test/web/wasm_parity_edge_cases_test.dart`'s `getBytes
/// contract` group, but runs through this package's integration harness
/// (see `wasm_bootstrap_test.dart`) instead of `flutter test --platform
/// chrome`, which serves no asset bundle and cannot load the WASM module.
///
/// The expected bytes are built here by direct manual concatenation of
/// `plane.bytes`, never by calling `getBytes()` on another backend: a defect
/// shared between `getBytes()` and its "expected" value would otherwise hide
/// on both sides of the comparison.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('getBytes returns exactly the concatenated plane bytes for 1x1, 3x3, 127x255 and 512x512', (
    tester,
  ) async {
    expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');

    await YuvFfi.ensureInitialized();

    const sizes = <({int w, int h})>[
      (w: 1, h: 1),
      (w: 3, h: 3),
      (w: 127, h: 255),
      (w: 512, h: 512),
    ];

    for (final size in sizes) {
      for (final image in _imagesForEachFormat(size.w, size.h)) {
        _fillPlanesWithPattern(image);

        final expectedBytes = _concatPlanesDirectly(image);
        final expectedLength = image.planes.fold<int>(0, (sum, plane) => sum + plane.bytes.length);

        final actual = image.getBytes();

        expect(
          actual,
          hasLength(expectedLength),
          reason: '${image.format.name} ${size.w}x${size.h} must not carry an alignment tail',
        );
        expect(
          actual,
          orderedEquals(expectedBytes),
          reason: '${image.format.name} ${size.w}x${size.h} must concatenate planes in format order',
        );
      }
    }
  });

  testWidgets('getBytes matches a padded BGRA plane exactly', (tester) async {
    expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');

    await YuvFfi.ensureInitialized();

    final plane = YuvPlane(2, 16, 4, Uint8List(32));
    final image = YuvImage.bgra(2, 2, planes: [plane]);
    _fillPlanesWithPattern(image);

    final expectedBytes = _concatPlanesDirectly(image);

    expect(expectedBytes, hasLength(32));
    expect(image.getBytes(), hasLength(32));
    expect(image.getBytes(), orderedEquals(expectedBytes));
  });

  testWidgets('F-003 diagnostic case: i420 3x3 yields exactly 25 bytes, not 32', (tester) async {
    expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');

    await YuvFfi.ensureInitialized();

    final image = YuvImage.i420(3, 3);
    final expectedLength = image.planes.fold<int>(0, (sum, plane) => sum + plane.bytes.length);

    expect(expectedLength, 25);
    expect(image.getBytes(), hasLength(25));
  });

  testWidgets('getBytes returns an independent copy, decoupled from the plane bytes in both directions', (
    tester,
  ) async {
    expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');

    await YuvFfi.ensureInitialized();

    final image = YuvImage.i420(4, 4);
    _fillPlanesWithPattern(image);

    final firstPlaneOriginalByte = image.planes[0].bytes[0];
    final returned = image.getBytes();
    final returnedOriginalByte = returned[0];

    // Mutating the returned buffer must not affect the image's plane bytes.
    returned[0] = (returnedOriginalByte + 1) & 0xFF;
    expect(
      image.planes[0].bytes[0],
      firstPlaneOriginalByte,
      reason: 'mutating the buffer returned by getBytes() must not affect the image plane bytes',
    );

    // Mutating a plane byte after the call must not affect the already-returned buffer.
    final returnedByteBeforePlaneMutation = returned[0];
    image.planes[0].bytes[0] = (firstPlaneOriginalByte + 2) & 0xFF;
    expect(
      returned[0],
      returnedByteBeforePlaneMutation,
      reason: 'mutating a plane byte after getBytes() must not affect the previously returned buffer',
    );
  });
}

/// Builds one image per public format, so a contract case covers BGRA, I420
/// and the legacy `nv21` name without repeating itself.
List<YuvImage> _imagesForEachFormat(int w, int h) => <YuvImage>[
      YuvImage.bgra(w, h),
      YuvImage.i420(w, h),
      YuvImage.nv21(w, h),
    ];

/// Writes a per-plane pattern so a misordered or truncated concatenation
/// cannot coincidentally match an all-zero buffer.
void _fillPlanesWithPattern(YuvImage image) {
  for (int i = 0; i < image.planes.length; i++) {
    final bytes = image.planes[i].bytes;
    for (int j = 0; j < bytes.length; j++) {
      bytes[j] = ((i + 1) * 37 + j) & 0xFF;
    }
  }
}

/// Expected value built by direct concatenation rather than by calling
/// `getBytes()` on another backend, so a shared defect cannot hide on both
/// sides of the comparison.
Uint8List _concatPlanesDirectly(YuvImage image) {
  final out = <int>[];
  for (final plane in image.planes) {
    out.addAll(plane.bytes);
  }
  return Uint8List.fromList(out);
}
