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

  testWidgets('empty YuvPlane rows reject pixel access in release', (tester) async {
    for (final pixelStride in [1, 4]) {
      final plane = YuvPlane(1, 0, pixelStride);
      expect(plane.bytes, isEmpty);
      expect(() => plane.getPixel(0, 0), throwsArgumentError, reason: 'pixelStride=$pixelStride');
      expect(() => plane.setPixel(0, 0, 1), throwsArgumentError, reason: 'pixelStride=$pixelStride');
      expect(plane.bytes, isEmpty, reason: 'pixelStride=$pixelStride');
    }
  });

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

  testWidgets('default decoded and shader views share contain geometry at larger and smaller constraints', (tester) async {
    await YuvFfi.initialize();
    for (final viewSize in const [Size(128, 96), Size(32, 24)]) {
      final frame = viewSize.width > 64 ? _frame(64, 48) : _constantFrame(64, 48);
      final pixelsByBackend = <bool, Uint8List>{};
      final geometryByBackend = <bool, YuvFrameGeometry>{};
      for (final useShader in [false, true]) {
        final presenter = YuvFramePresenter(useShader: useShader);
        final geometries = <YuvFrameGeometry>[];
        final boundaryKey = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            home: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                key: boundaryKey,
                child: SizedBox.fromSize(
                  size: viewSize,
                  child: YuvFrameView(presenter: presenter, onGeometryChanged: geometries.add),
                ),
              ),
            ),
          ),
        );
        for (var i = 0; useShader && !presenter.hasShader && i < 200; i++) {
          await tester.pump(const Duration(milliseconds: 5));
        }
        if (useShader) expect(presenter.hasShader, isTrue);
        expect(presenter.present(frame), isTrue);
        for (var i = 0; presenter.isBusy && i < 200; i++) {
          await tester.pump(const Duration(milliseconds: 5));
        }
        await tester.pump();

        expect(presenter.isBusy, isFalse);
        expect(geometries, hasLength(1));
        final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey));
        final screenshot = await boundary.toImage();
        final data = await screenshot.toByteData(format: ImageByteFormat.rawRgba) ?? (throw StateError('The rendered frame has no RGBA bytes'));
        final actual = data.buffer.asUint8List();
        pixelsByBackend[useShader] = actual;
        geometryByBackend[useShader] = geometries.single;
        final expected = renderYuvFrameReference(frame, geometries.single);
        for (var i = 0; i < actual.length; i++) {
          expect((actual[i] - expected[i]).abs(), lessThanOrEqualTo(1), reason: '$viewSize useShader=$useShader byte $i');
        }
        screenshot.dispose();
        presenter.dispose();
      }
      expect(geometryByBackend[false], geometryByBackend[true]);
      final geometry = geometryByBackend[false] ?? (throw StateError('The decoded view did not report geometry'));
      final contentHeight = viewSize.width * frame.height / frame.width;
      expect(geometry.destinationRect, Rect.fromLTWH(0, (viewSize.height - contentHeight) / 2, viewSize.width, contentHeight));
      expect(MatrixUtils.transformPoint(geometry.viewToSource, geometry.destinationRect.topLeft), Offset.zero);
      expect(MatrixUtils.transformPoint(geometry.viewToSource, geometry.destinationRect.bottomRight), const Offset(64, 48));
      final decoded = pixelsByBackend[false] ?? (throw StateError('The decoded view has no pixels'));
      final shader = pixelsByBackend[true] ?? (throw StateError('The shader view has no pixels'));
      expect(decoded.length, shader.length);
      for (var i = 0; i < decoded.length; i++) {
        expect((decoded[i] - shader[i]).abs(), lessThanOrEqualTo(1), reason: '$viewSize byte $i');
      }
    }
  });
}

YuvImage _frame([int width = 16, int height = 9]) => YuvImage.i420(
  width,
  height,
  planes: [_plane(height, width, 1, 11), _plane((height + 1) ~/ 2, (width + 1) ~/ 2, 1, 23), _plane((height + 1) ~/ 2, (width + 1) ~/ 2, 1, 37)],
);

YuvImage _constantFrame(int width, int height) {
  final frame = YuvImage.i420(width, height);
  frame.yPlane.bytes.fillRange(0, frame.yPlane.bytes.length, 120);
  frame.uPlane.bytes.fillRange(0, frame.uPlane.bytes.length, 128);
  frame.vPlane.bytes.fillRange(0, frame.vPlane.bytes.length, 128);
  return frame;
}

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
