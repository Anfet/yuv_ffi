@Tags(['contract'])
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

const int _width = 8;
const int _height = 6;

/// An opaque grey frame whose every channel equals [shade], so the decoded
/// pixels tell which frame is on screen.
YuvImage _frame(int shade) {
  final frame = YuvImage.bgra(_width, _height);
  frame.yPlane.assignFrom(
    Uint8List.fromList([
      for (int i = 0; i < _width * _height; i++) ...[shade, shade, shade, 255],
    ]),
  );
  frame.markDirty();
  return frame;
}

/// Decoding goes through the engine, which only answers outside the test's
/// fake clock, so presenting and waiting both run inside [WidgetTester.runAsync].
Future<void> _waitUntil(WidgetTester tester, bool Function() condition, {String reason = 'condition'}) async {
  await tester.runAsync(() async {
    for (int i = 0; i < 400 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  });
  expect(condition(), isTrue, reason: 'timed out waiting for $reason');
}

Future<int> _shadeOf(WidgetTester tester, ui.Image image) async {
  final data = await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.rawRgba));
  return data!.getUint8(0);
}

ui.Image? _drawnImage(WidgetTester tester) {
  final raw = find.byType(RawImage);
  return raw.evaluate().isEmpty ? null : tester.widget<RawImage>(raw).image;
}

void main() {
  late int presented;
  late YuvFramePresenter presenter;

  setUp(() {
    presented = 0;
    presenter = YuvFramePresenter(onFramePresented: () => presented++);
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  Future<void> pumpView(WidgetTester tester, {Key? viewKey}) => tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: RepaintBoundary(
          key: viewKey,
          child: YuvFrameView(presenter: presenter),
        ),
      ),
    ),
  );

  testWidgets('synchronous BGRA copy errors leave the presenter free for the next frame', (tester) async {
    await pumpView(tester);
    expect(() => presenter.present(_ThrowingImage(_frame(1))), throwsA(isA<StateError>()));
    expect(presenter.isBusy, isFalse);

    await tester.runAsync(() async => expect(presenter.present(_frame(2)), isTrue));
    await _waitUntil(tester, () => presenter.image != null, reason: 'the valid frame to decode');
    await tester.pump();
    expect(await _shadeOf(tester, require(_drawnImage(tester))), 2);
  });

  testWidgets('shader BGRA fallback errors leave the presenter free for the next frame', (tester) async {
    final viewKey = GlobalKey();
    presenter.dispose();
    presented = 0;
    presenter = YuvFramePresenter(onFramePresented: () => presented++, useShader: true);
    await pumpView(tester, viewKey: viewKey);

    expect(() => presenter.present(_ThrowingImage(_frame(1))), throwsA(isA<StateError>()));
    expect(presenter.isBusy, isFalse);

    await tester.runAsync(() async => expect(presenter.present(_frame(3)), isTrue));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    expect(presenter.isBusy, isFalse);
    expect(presented, 1);
    final boundary = viewKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final screenshot = await tester.runAsync(() => boundary.toImage());
    expect(await _shadeOf(tester, require(screenshot)), 3);
    screenshot!.dispose();
  });

  testWidgets('keeps one frame in flight, drops frames arriving meanwhile and then shows the latest finished one', (tester) async {
    await pumpView(tester);

    final accepted = <int>[];
    await tester.runAsync(() async {
      // A burst of 30 frames before the first decode finishes: the old
      // StreamBuilder + YuvImageWidget path started 30 loads here.
      for (int shade = 1; shade <= 30; shade++) {
        if (presenter.present(_frame(shade))) accepted.add(shade);
      }
    });
    expect(accepted, [1], reason: 'only the first frame of a burst may be in flight');
    expect(presenter.isBusy, isTrue);

    await _waitUntil(tester, () => presenter.image != null, reason: 'the first frame to decode');
    expect(presenter.isBusy, isTrue, reason: 'a decoded frame stays in flight until it is drawn');
    expect(presenter.present(_frame(31)), isFalse);

    await tester.pump();
    expect(presenter.isBusy, isFalse);
    expect(presented, 1);
    expect(await _shadeOf(tester, require(_drawnImage(tester))), 1);

    await tester.runAsync(() async => expect(presenter.present(_frame(40)), isTrue));
    await _waitUntil(tester, () => presented == 1 && presenter.image != null && !presenter.image!.isCloneOf(require(_drawnImage(tester))));
    await tester.pump();
    expect(presented, 2);
    expect(await _shadeOf(tester, require(_drawnImage(tester))), 40, reason: 'the screen shows the latest finished frame');

    final cache = PaintingBinding.instance.imageCache;
    expect(cache.pendingImageCount + cache.currentSize + cache.liveImageCount, 0, reason: 'preview frames must not pile up in ImageCache');
  });

  testWidgets('disposes the replaced frame explicitly and the last one on dispose', (tester) async {
    await pumpView(tester);

    await tester.runAsync(() async => presenter.present(_frame(10)));
    await _waitUntil(tester, () => presenter.image != null);
    await tester.pump();
    final first = require(presenter.image);

    await tester.runAsync(() async => presenter.present(_frame(20)));
    await _waitUntil(tester, () => !identical(presenter.image, first), reason: 'the second frame');
    await tester.pump();
    final second = require(presenter.image);

    expect(first.debugDisposed, isTrue, reason: 'the presenter releases its handle to a replaced frame at once');
    expect(second.debugDisposed, isFalse);
    expect(require(_drawnImage(tester)).isCloneOf(second), isTrue);

    await tester.pumpWidget(const SizedBox());
    presenter.dispose();
    expect(second.debugDisposed, isTrue);
  });

  testWidgets('a frame still decoding when the preview is disposed never reaches the screen or the frame counter', (tester) async {
    await pumpView(tester);
    await tester.runAsync(() async => presenter.present(_frame(50)));

    await tester.pumpWidget(const SizedBox());
    presenter.dispose();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();

    expect(presented, 0);
    expect(presenter.image, isNull);
    expect(presenter.present(_frame(51)), isFalse, reason: 'a disposed presenter accepts no frames');
  });

  testWidgets('reset drops the shown frame and a frame still in flight, and keeps one frame in flight across it', (tester) async {
    await pumpView(tester);
    await tester.runAsync(() async => presenter.present(_frame(60)));
    await _waitUntil(tester, () => presenter.image != null);
    await tester.pump();
    final shown = require(presenter.image);

    await tester.runAsync(() async => presenter.present(_frame(70)));
    presenter.reset();
    expect(shown.debugDisposed, isTrue);
    expect(presenter.present(_frame(71)), isFalse, reason: 'the discarded decode still counts as in flight');

    await _waitUntil(tester, () => !presenter.isBusy, reason: 'the discarded decode to finish');
    await tester.pump();
    expect(presenter.image, isNull, reason: 'a frame of the stopped stream must not be shown');
    expect(_drawnImage(tester), isNull);
    expect(presented, 1);

    await tester.runAsync(() async => expect(presenter.present(_frame(80)), isTrue));
    await _waitUntil(tester, () => presenter.image != null);
    await tester.pump();
    expect(presented, 2);
    expect(await _shadeOf(tester, require(_drawnImage(tester))), 80);
  });

  testWidgets('the frame counter follows frames drawn, not frames received', (tester) async {
    await pumpView(tester);

    int received = 0;
    int drawn = 0;
    ui.Image? lastDrawn;
    // A camera delivering four frames per display frame.
    for (int vsync = 0; vsync < 40; vsync++) {
      await tester.runAsync(() async {
        for (int i = 0; i < 4; i++) {
          received++;
          presenter.present(_frame(received % 250));
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }
      });
      await tester.pump();
      final image = _drawnImage(tester);
      if (image != null && (lastDrawn == null || !image.isCloneOf(lastDrawn))) {
        drawn++;
      }
      lastDrawn = image;
    }

    expect(drawn, greaterThan(0));
    expect(presented, drawn, reason: 'one report per frame actually drawn');
    expect(received, greaterThan(presented));
  });

  testWidgets('rotation changes the aspect ratio and reports geometry only when it changes', (tester) async {
    final geometries = <YuvFrameGeometry>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: YuvFrameView(presenter: presenter, onGeometryChanged: geometries.add),
        ),
      ),
    );

    await tester.runAsync(() async => presenter.present(_frame(90), orientation: const YuvFrameOrientation(rotation: YuvImageRotation.rotation90)));
    await _waitUntil(tester, () => presenter.image != null, reason: 'the oriented frame');
    await tester.pump();

    expect(tester.widget<AspectRatio>(find.byType(AspectRatio)).aspectRatio, _height / _width);
    expect(geometries, hasLength(1));
    expect(geometries.single.orientation.rotation, YuvImageRotation.rotation90);

    await tester.pump();
    expect(geometries, hasLength(1));
  });
}

class _ThrowingImage implements YuvImage {
  final YuvImage _delegate;

  _ThrowingImage(this._delegate);

  @override
  int get width => _delegate.width;

  @override
  int get height => _delegate.height;

  @override
  ui.Size get size => _delegate.size;

  @override
  Uint8List toBgraBytes() => throw StateError('copy failed');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

T require<T extends Object>(T? value) => value ?? (throw StateError('Expected a non-null $T'));
