import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// The padded BGRA constructor preserves valid row-strided input.
///
/// The input uses 16 bytes per row for two BGRA pixels, whose logical row size
/// is eight bytes. The check runs against the Web backend because its
/// implementation is separate from the VM backend.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  YuvPlane plane(int height, int rowStride, [int pixelStride = 4]) => YuvPlane(height, rowStride, pixelStride, Uint8List(height * rowStride));

  setUpAll(() async {
    await YuvFfi.initialize();
  });

  testWidgets('specialized and generic constructors agree on a padded plane', (tester) async {
    expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');

    final specialized = YuvImage.bgra(2, 2, planes: <YuvPlane>[plane(2, 16)], layout: YuvPlaneLayout.preserve);
    // ignore: deprecated_member_use
    final generic = YuvImage(
      // ignore: deprecated_member_use
      YuvPixelFormat.bgra8888,
      2,
      2,
      yPixelStride: 4,
      planes: <YuvPlane>[plane(2, 16)],
      layout: YuvPlaneLayout.preserve,
    );

    for (final image in <YuvImage>[specialized, generic]) {
      expect(image.yPlane.rowStride, 16);
      expect(image.yPlane.pixelStride, 4);
      expect(image.yPlane.bytes.length, 32);
    }
  });

  testWidgets('an invalid padded layout throws ArgumentError, not a RangeError', (tester) async {
    expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');

    expect(() => YuvImage.bgra(2, 2, planes: <YuvPlane>[plane(2, 4)], layout: YuvPlaneLayout.preserve), throwsArgumentError);
    expect(
      // ignore: deprecated_member_use
      () => YuvImage(YuvPixelFormat.bgra8888, 2, 2, yPixelStride: 4, planes: <YuvPlane>[plane(2, 4)], layout: YuvPlaneLayout.preserve),
      throwsArgumentError,
    );
  });

  testWidgets('constructing from a plane deep-copies bytes in both directions', (tester) async {
    expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');

    final source = plane(2, 16);
    for (int i = 0; i < source.bytes.length; i++) {
      source.bytes[i] = i + 1;
    }
    final image = YuvImage.bgra(2, 2, planes: <YuvPlane>[source], layout: YuvPlaneLayout.preserve);
    final snapshot = Uint8List.fromList(image.yPlane.bytes);

    // Mutating the source after construction must not leak into the image.
    source.bytes[0] = source.bytes[0] ^ 0xFF;
    expect(image.yPlane.bytes, orderedEquals(snapshot));

    // Mutating the image after construction must not leak back into the source.
    final sourceSnapshot = Uint8List.fromList(source.bytes);
    image.yPlane.bytes[1] = image.yPlane.bytes[1] ^ 0xFF;
    expect(source.bytes, orderedEquals(sourceSnapshot));
  });

  testWidgets('copy keeps padded metadata and byte content', (tester) async {
    expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');

    final source = plane(2, 16);
    for (int i = 0; i < source.bytes.length; i++) {
      source.bytes[i] = i + 1;
    }
    final image = YuvImage.bgra(2, 2, planes: <YuvPlane>[source], layout: YuvPlaneLayout.preserve);

    final copied = image.copy();
    expect(copied.yPlane.rowStride, 16);
    expect(copied.yPlane.bytes.length, 32);
    expect(copied.yPlane.bytes, orderedEquals(image.yPlane.bytes));

  });

  testWidgets('specialized and generic constructors agree on a tight plane', (tester) async {
    expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');

    final specialized = YuvImage.bgra(2, 2, planes: <YuvPlane>[plane(2, 8)]);
    // ignore: deprecated_member_use
    final generic = YuvImage(YuvPixelFormat.bgra8888, 2, 2, yPixelStride: 4, planes: <YuvPlane>[plane(2, 8)]);

    for (final image in <YuvImage>[specialized, generic]) {
      expect(image.yPlane.rowStride, 8);
      expect(image.yPlane.pixelStride, 4);
      expect(image.yPlane.bytes.length, 16);
    }
  });

  testWidgets('copy keeps tight metadata and byte content', (tester) async {
    expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');

    final source = plane(2, 8);
    for (int i = 0; i < source.bytes.length; i++) {
      source.bytes[i] = i + 1;
    }
    final image = YuvImage.bgra(2, 2, planes: <YuvPlane>[source]);

    final copied = image.copy();
    expect(copied.yPlane.rowStride, 8);
    expect(copied.yPlane.bytes.length, 16);
    expect(copied.yPlane.bytes, orderedEquals(image.yPlane.bytes));

  });

  testWidgets('toBgraBytes on a tight image returns exactly the plane content', (tester) async {
    expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');

    final source = plane(2, 8);
    for (int i = 0; i < source.bytes.length; i++) {
      source.bytes[i] = i + 1;
    }
    final image = YuvImage.bgra(2, 2, planes: <YuvPlane>[source]);

    final bytes = image.toBgraBytes();
    expect(bytes.length, 16);
    expect(bytes, orderedEquals(source.bytes));
  });
}
