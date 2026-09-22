import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// YUV-06: the plugin must load and compute inside a real built application.
///
/// `test/native_packaging_smoke_test.dart` runs under `flutter test`, a plain
/// Dart VM process that links nothing and resolves the library through
/// `LD_LIBRARY_PATH`/`DYLD_LIBRARY_PATH`. That proves the installed-name path
/// works, but it cannot prove the path the loader actually takes in an app:
/// on Apple platforms `_openYuvLibrary` returns `DynamicLibrary.process()`
/// because the sources are compiled into the pod target, and a plain VM never
/// exercises that branch. A macOS pod target that built no operation sources
/// at all — which is exactly what this package shipped before YUV-06 — would
/// still have passed the VM smoke through the side-loaded dylib.
///
/// This suite closes that hole: it runs in the built app bundle, so the symbols
/// must come from wherever the platform's real packaging put them. It is the
/// app-runtime counterpart of the VM smoke, not a replacement for it.
///
/// Unlike the other native suites in this repository it never skips when the
/// library cannot be opened. A run where the native cases skipped and a run
/// where they passed used to look identical in a CI log, which is how broken
/// packaging stayed green.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the plugin loads from the application bundle and performs real native work', (tester) async {
    expect(kIsWeb, isFalse, reason: 'this gate covers native packaging; the Web backend is proven by the WASM suites');

    // Fails loudly rather than skipping: see the library doc above.
    await YuvFfi.ensureInitialized();

    const width = 4;
    const height = 4;

    // A deterministic, non-uniform source, so a backend that returned zeroes or
    // echoed its input could not pass by coincidence.
    final rgba = Uint8List(width * height * 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = (y * width + x) * 4;
        rgba[i] = (x * 60 + 10) & 0xFF;
        rgba[i + 1] = (y * 60 + 20) & 0xFF;
        rgba[i + 2] = (x * 20 + y * 20 + 30) & 0xFF;
        rgba[i + 3] = 255;
      }
    }

    // A conversion and an in-place effect exercise two different symbol groups:
    // a pod target that forwarded the conversion sources but not the effect
    // ones would pass on the conversion alone.
    final image = YuvImage.i420(width, height)..fromRgba8888(rgba);
    final bgra = image.toBgra8888();

    expect(bgra, hasLength(width * height * 4), reason: 'toBgra8888 must return a tightly packed buffer');
    expect(bgra.any((byte) => byte != 0), isTrue, reason: 'a conversion that produced only zeroes means the native symbols did not run');

    final before = Uint8List.fromList(image.getBytes());
    image.negate();
    expect(image.getBytes(), isNot(orderedEquals(before)), reason: 'negate() must change the planes, or the native effect symbol did not run');

    // Recorded so a CI log names the platform that produced this evidence; a
    // green run with no line here would be a run that never executed.
    debugPrint('YUV-06 app-runtime smoke passed on ${Platform.operatingSystem}');
  });
}
