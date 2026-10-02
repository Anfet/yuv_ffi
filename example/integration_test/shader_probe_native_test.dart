import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

import 'helpers/probe/probe_seed.dart';
import 'helpers/yuv_frame_render_reference.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('matches CPU conversion for I420 and NV12 in every orientation', (tester) async {
    await YuvFfi.initialize();
    final renderer = await YuvFrameRenderer.load();
    expect(renderer.hasShader, isTrue);
    for (final frame in [_i420(), _nv12()]) {
      for (final rotation in YuvImageRotation.values) {
        for (final mirrored in [false, true]) {
          final viewSize = rotation.swapSize ? const Size(9, 16) : const Size(16, 9);
          final geometry = YuvFrameGeometry(
            sourceSize: frame.size,
            viewSize: viewSize,
            orientation: YuvFrameOrientation(rotation: rotation, mirrored: mirrored),
          );
          final texture = await renderer.upload(frame);
          final recorder = PictureRecorder();
          renderer.paint(Canvas(recorder), texture, geometry);
          final drawn = await recorder.endRecording().toImage(viewSize.width.toInt(), viewSize.height.toInt());
          final bytes = (await drawn.toByteData(format: ImageByteFormat.rawRgba))!.buffer.asUint8List();
          final expected = renderYuvFrameReference(frame, geometry);
          var maxDiff = 0;
          for (var i = 0; i < bytes.length; i++) {
            final difference = (bytes[i] - expected[i]).abs();
            maxDiff = maxDiff > difference ? maxDiff : difference;
          }
          expect(maxDiff, lessThanOrEqualTo(1), reason: '${frame.format}, $rotation, mirrored=$mirrored');
          drawn.dispose();
          texture.dispose();
        }
      }
    }
    renderer.dispose();
  });
}

YuvImage _i420() => YuvImage.i420(16, 9, planes: [_plane(9, 16, 1), _plane(5, 8, 1), _plane(5, 8, 1)], layout: YuvPlaneLayout.preserve);

YuvImage _nv12() => YuvImage.nv12(16, 9, planes: [_plane(9, 16, 1), _plane(5, 16, 2)], layout: YuvPlaneLayout.preserve);

YuvPlane _plane(int height, int rowStride, int pixelStride) {
  var seed = height * 1000 + rowStride * 10 + pixelStride;
  return YuvPlane(
    height,
    rowStride,
    pixelStride,
    Uint8List.fromList(
      List.generate(height * rowStride, (_) {
        seed = probeNextSeed(seed);
        return seed & 255;
      }),
    ),
  );
}
