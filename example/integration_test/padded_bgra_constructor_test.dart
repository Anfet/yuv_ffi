import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Web acceptance for YUV-15: the padded BGRA constructor contract.
///
/// F-004 was a `RangeError (end): Invalid value: Not in inclusive range 0..16: 32`
/// thrown by the specialized `YuvImage.bgra` constructor when given a padded
/// plane (rowStride 16 with a logical width of 2 pixels at 4 bytes each, i.e.
/// 8 logical bytes per row but 16 allocated). The fix made the specialized
/// constructor share the generic constructor's validation and deep-copy path.
/// This must be proven on the Web backend too, since the VM and Web
/// implementations diverge (`lib/src/yuv/impl/io` vs `lib/src/yuv/impl/web`).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  YuvPlane plane(int height, int rowStride, [int pixelStride = 4]) => YuvPlane(height, rowStride, pixelStride, Uint8List(height * rowStride));

  setUpAll(() async {
    await YuvFfi.initialize();
  });

  testWidgets('specialized and generic constructors agree on a padded plane', (tester) async {
    expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');

    final specialized = YuvImage.bgra(2, 2, planes: <YuvPlane>[plane(2, 16)]);
    // ignore: deprecated_member_use
    final generic = YuvImage(YuvFileFormat.bgra8888, 2, 2, yPixelStride: 4, planes: <YuvPlane>[plane(2, 16)]);

    for (final image in <YuvImage>[specialized, generic]) {
      expect(image.yPlane.rowStride, 16);
      expect(image.yPlane.pixelStride, 4);
      expect(image.yPlane.bytes.length, 32);
    }
  });

  testWidgets('an invalid padded layout throws ArgumentError, not a RangeError', (tester) async {
    expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');

    expect(() => YuvImage.bgra(2, 2, planes: <YuvPlane>[plane(2, 4)]), throwsArgumentError);
    // ignore: deprecated_member_use
    expect(() => YuvImage(YuvFileFormat.bgra8888, 2, 2, yPixelStride: 4, planes: <YuvPlane>[plane(2, 4)]), throwsArgumentError);
  });

  testWidgets('constructing from a plane deep-copies bytes in both directions', (tester) async {
    expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');

    final source = plane(2, 16);
    for (int i = 0; i < source.bytes.length; i++) {
      source.bytes[i] = i + 1;
    }
    final image = YuvImage.bgra(2, 2, planes: <YuvPlane>[source]);
    final snapshot = Uint8List.fromList(image.yPlane.bytes);

    // Mutating the source after construction must not leak into the image.
    source.bytes[0] = source.bytes[0] ^ 0xFF;
    expect(image.yPlane.bytes, orderedEquals(snapshot));

    // Mutating the image after construction must not leak back into the source.
    final sourceSnapshot = Uint8List.fromList(source.bytes);
    image.yPlane.bytes[1] = image.yPlane.bytes[1] ^ 0xFF;
    expect(source.bytes, orderedEquals(sourceSnapshot));
  });

  testWidgets('copy keeps padded metadata and byte content, blank copy zeros the whole allocation', (tester) async {
    expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');

    final source = plane(2, 16);
    for (int i = 0; i < source.bytes.length; i++) {
      source.bytes[i] = i + 1;
    }
    final image = YuvImage.bgra(2, 2, planes: <YuvPlane>[source]);

    final copied = image.copy();
    expect(copied.yPlane.rowStride, 16);
    expect(copied.yPlane.bytes.length, 32);
    expect(copied.yPlane.bytes, orderedEquals(image.yPlane.bytes));

    // The deprecated option specifically preserves the source padding.
    // ignore: deprecated_member_use
    final blank = image.copy(blank: true);
    expect(blank.yPlane.rowStride, 16);
    expect(blank.yPlane.bytes.length, 32);
    expect(blank.yPlane.bytes.every((b) => b == 0), isTrue);
  });

  testWidgets('specialized and generic constructors agree on a tight plane', (tester) async {
    expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');

    final specialized = YuvImage.bgra(2, 2, planes: <YuvPlane>[plane(2, 8)]);
    // ignore: deprecated_member_use
    final generic = YuvImage(YuvFileFormat.bgra8888, 2, 2, yPixelStride: 4, planes: <YuvPlane>[plane(2, 8)]);

    for (final image in <YuvImage>[specialized, generic]) {
      expect(image.yPlane.rowStride, 8);
      expect(image.yPlane.pixelStride, 4);
      expect(image.yPlane.bytes.length, 16);
    }
  });

  testWidgets('copy keeps tight metadata and byte content, blank copy zeros the whole allocation', (tester) async {
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

    // The deprecated option specifically preserves the source padding.
    // ignore: deprecated_member_use
    final blank = image.copy(blank: true);
    expect(blank.yPlane.rowStride, 8);
    expect(blank.yPlane.bytes.length, 16);
    expect(blank.yPlane.bytes.every((b) => b == 0), isTrue);
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
