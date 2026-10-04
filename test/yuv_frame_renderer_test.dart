@Tags(['contract'])
library;

import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

void main() {
  test('uploads a BGRA snapshot before the first await', () async {
    final frame = YuvImage.bgra(2, 1)..yPlane.assignFrom(Uint8List.fromList([10, 20, 30, 255, 40, 50, 60, 255]));
    final renderer = await YuvFrameRenderer.load();
    final texture = await renderer.upload(frame);
    frame.yPlane.bytes[0] = 200;
    final recorder = PictureRecorder();
    renderer.paint(Canvas(recorder), texture, YuvFrameGeometry(sourceSize: frame.size, viewSize: frame.size));
    final image = await recorder.endRecording().toImage(2, 1);
    final bytes = (await image.toByteData(format: ImageByteFormat.rawRgba))!.buffer.asUint8List();

    expect(bytes.take(4), orderedEquals([30, 20, 10, 255]));
    image.dispose();
    texture.dispose();
    renderer.dispose();
  });

  test('keeps the original dimensions when the source frame is reused during decoding', () async {
    final frame = _ReusableImage(YuvImage.bgra(2, 1));
    final renderer = await YuvFrameRenderer.load();
    final upload = renderer.upload(frame);
    frame.width = 1;
    frame.height = 2;
    final texture = await upload;

    expect(texture.width, 2);
    expect(texture.height, 1);
    texture.dispose();
    renderer.dispose();
  });

  test('rejects a texture painted with another source size', () async {
    final renderer = await YuvFrameRenderer.load();
    final texture = await renderer.upload(YuvImage.bgra(1, 1));
    final recorder = PictureRecorder();

    expect(
      () => renderer.paint(Canvas(recorder), texture, YuvFrameGeometry(sourceSize: const Size(2, 2), viewSize: const Size(2, 2))),
      throwsArgumentError,
    );
    texture.dispose();
    renderer.dispose();
  });
}

class _ReusableImage implements YuvImage {
  final YuvImage delegate;
  @override
  int width;
  @override
  int height;

  _ReusableImage(this.delegate) : width = delegate.width, height = delegate.height;

  @override
  Size get size => Size(width.toDouble(), height.toDouble());

  @override
  Uint8List toBgraBytes() => delegate.toBgraBytes();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
