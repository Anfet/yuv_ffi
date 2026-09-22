@TestOn('vm')
library;

import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// YUV-06 packaging smoke: the library must be loadable by its *installed*
/// name and must actually compute.
///
/// This suite deliberately does NOT skip when the library cannot be opened.
/// Every other native suite here guards itself with a `_checkNativeAvailable()`
/// helper that swallows the open failure and skips, which is correct for tests
/// about something else — but it is exactly what let broken Linux/macOS
/// packaging stay green: a run where every native case skipped looks identical
/// to a run where everything passed. The whole point of this suite is to be red
/// when the library is not where a real consumer would find it, so a failure to
/// open is a failure, not a skip.
///
/// Before the YUV-06 fix the loader opened `native/src/build/libyuv_ffi.{so,
/// dylib}` — a CMake build-tree path that exists in no published package and no
/// application bundle — so on Linux and macOS this suite is reproducibly red
/// until the loader uses the installed name (Linux) or process symbols (macOS).
void main() {
  test('the native library opens by its installed name and performs a real conversion', () async {
    // Fails loudly rather than skipping: see the library doc above.
    await YuvFfi.ensureInitialized();

    const width = 4;
    const height = 4;

    // A deterministic, non-uniform RGBA source, so a backend that returned
    // zeroes or echoed its input could not pass by coincidence.
    final rgba = Uint8List(width * height * 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = (y * width + x) * 4;
        rgba[i] = (x * 60 + 10) & 0xFF; // R
        rgba[i + 1] = (y * 60 + 20) & 0xFF; // G
        rgba[i + 2] = (x * 20 + y * 20 + 30) & 0xFF; // B
        rgba[i + 3] = 255; // A
      }
    }

    // Exercises a real native code path end to end: RGBA in, planar YUV
    // conversion in C, BGRA back out.
    final image = YuvImage.i420(width, height)..fromRgba8888(rgba);
    final bgra = image.toBgra8888();

    expect(bgra.length, width * height * 4, reason: 'toBgra8888 must return a tightly packed buffer');
    expect(bgra.any((byte) => byte != 0), isTrue, reason: 'a conversion that produced only zeroes means the native symbols did not run');
    expect(image.width, width, reason: 'the converted image must keep its declared geometry');

    // An in-place native effect must also resolve and mutate the image, which
    // proves the operation symbols are present — not just the conversion ones.
    final before = Uint8List.fromList(image.getBytes());
    image.negate();
    expect(image.getBytes(), isNot(orderedEquals(before)), reason: 'negate() must change the planes, or the native effect symbol did not run');

    // Printed so a CI log records which platform actually produced this
    // evidence; a green run with no line here would be a run that never
    // executed.
    // ignore: avoid_print
    print('YUV-06 packaging smoke passed on ${Platform.operatingSystem} (${Platform.version.split(' ').first})');
  });
}
