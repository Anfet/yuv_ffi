import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Checks hand-written U=37/V=219 chroma bytes and their order through a
/// BGRA round trip on the real WASM backend, loaded by the integration harness.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const int w = 4;
  const int h = 4;
  const int uSample = 37;
  const int vSample = 219;

  YuvPlane buildYPlane() => YuvPlane(h, w, 1, Uint8List(w * h)..fillRange(0, w * h, 16));

  YuvPlane buildUvPlane() {
    final bytes = Uint8List((h ~/ 2) * w); // NV chroma plane: h/2 rows of w bytes each (w/2 (U, V) pairs per row).
    for (int i = 0; i < bytes.length; i += 2) {
      bytes[i] = uSample;
      bytes[i + 1] = vSample;
    }
    return YuvPlane(h ~/ 2, w, 2, bytes);
  }

  testWidgets('nv12 stores hand-written UV chroma bytes on the real WASM backend', (tester) async {
    expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');

    await YuvFfi.initialize();

    final nv12Labeled = YuvImage.nv12(w, h)..applyPlanes([buildYPlane(), buildUvPlane()]);
    for (int i = 0; i < nv12Labeled.uPlane.bytes.length; i += 2) {
      expect(nv12Labeled.uPlane.bytes[i], uSample, reason: 'byte $i (U) of the nv12-labeled chroma plane was not what was written');
      expect(nv12Labeled.uPlane.bytes[i + 1], vSample, reason: 'byte ${i + 1} (V) of the nv12-labeled chroma plane was not what was written');
    }
  });

  testWidgets('chroma byte order survives an NV12 -> BGRA -> NV12 round trip on the real WASM backend', (tester) async {
    expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');

    await YuvFfi.initialize();

    final image = YuvImage.nv12(w, h)..applyPlanes([buildYPlane(), buildUvPlane()]);

    final viaBgra = image.toBgra().toNv12();

    // The exact input bytes are lossy through YUV<->RGB, so this checks the
    // U/V byte order survives (first byte stays "more U-like", second stays
    // "more V-like"), not exact equality -- the same tolerance strategy
    // `test/nv_chroma_order_test.dart` uses for its native lossy round trip.
    expect(
      viaBgra.uPlane.bytes[0] < viaBgra.uPlane.bytes[1],
      uSample < vSample,
      reason: 'chroma byte order flipped somewhere in the NV12 -> BGRA -> NV12 round trip',
    );
  });
}
