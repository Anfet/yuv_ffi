import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

import 'helpers/probe/probe_seed.dart';
import 'helpers/yuv_frame_render_reference.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('YuvFrameView shader path matches the frame-display contract', (tester) async {
    await YuvFfi.initialize();
    for (final orientation in const [YuvFrameOrientation.upright, YuvFrameOrientation(rotation: YuvImageRotation.rotation270, mirrored: true)]) {
      final presenter = YuvFramePresenter(useShader: true);
      final viewSize = orientation.rotation.swapSize ? const Size(9, 16) : const Size(16, 9);
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: SizedBox.fromSize(
                size: viewSize,
                child: YuvFrameView(presenter: presenter),
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 200 && !presenter.hasShader; i++) {
        await tester.pump(const Duration(milliseconds: 5));
      }
      expect(presenter.hasShader, isTrue);
      final frame = _frame();
      expect(() => presenter.present(_ThrowingSizeFrame(frame)), throwsA(isA<StateError>()));
      expect(presenter.isBusy, isFalse);
      expect(() => presenter.present(_ThrowingPlanesFrame(frame)), throwsA(isA<StateError>()));
      expect(presenter.isBusy, isFalse);
      expect(presenter.present(frame, orientation: orientation), isTrue);
      for (var i = 0; i < 200 && presenter.isBusy; i++) {
        await tester.pump(const Duration(milliseconds: 5));
      }
      await tester.pump();

      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey));
      final image = await boundary.toImage();
      final actual = (await image.toByteData(format: ImageByteFormat.rawRgba))!.buffer.asUint8List();
      final geometry = YuvFrameGeometry(sourceSize: frame.size, viewSize: viewSize, orientation: orientation);
      final expected = renderYuvFrameReference(frame, geometry);
      for (var i = 0; i < actual.length; i++) {
        expect((actual[i] - expected[i]).abs(), lessThanOrEqualTo(1), reason: '$orientation byte $i');
      }
      image.dispose();
      presenter.dispose();
    }
  });
}

YuvImage _frame() => YuvImage.i420(16, 9, planes: [_plane(9, 16, 1, 11), _plane(5, 8, 1, 23), _plane(5, 8, 1, 37)]);

YuvPlane _plane(int height, int rowStride, int pixelStride, int seed) {
  var current = seed;
  return YuvPlane(
    height,
    rowStride,
    pixelStride,
    Uint8List.fromList(
      List.generate(height * rowStride, (_) {
        current = probeNextSeed(current);
        return current & 255;
      }),
    ),
  );
}

class _ThrowingPlanesFrame implements YuvImage {
  final YuvImage _delegate;

  _ThrowingPlanesFrame(this._delegate);

  @override
  int get width => _delegate.width;

  @override
  int get height => _delegate.height;

  @override
  YuvPixelFormat get format => _delegate.format;

  @override
  Size get size => _delegate.size;

  @override
  List<YuvPlane> get planes => throw StateError('plane packing failed');

  @override
  YuvPlane get yPlane => throw StateError('plane packing failed');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ThrowingSizeFrame implements YuvImage {
  final YuvImage _delegate;

  _ThrowingSizeFrame(this._delegate);

  @override
  int get width => _delegate.width;

  @override
  int get height => _delegate.height;

  @override
  Size get size => throw StateError('size read failed');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
