@Tags(['contract'])
library;

import 'dart:ui';
import 'dart:typed_data';

import 'package:flutter/widgets.dart' show Alignment, MatrixUtils;
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

void main() {
  const sourceSize = Size(4, 3);

  group('YuvFrameGeometry source orientation', () {
    final cases = <({YuvImageRotation rotation, bool mirrored, List<Offset> corners})>[
      (rotation: YuvImageRotation.rotation0, mirrored: false, corners: const [Offset(0, 0), Offset(4, 0), Offset(0, 3), Offset(4, 3)]),
      (rotation: YuvImageRotation.rotation90, mirrored: false, corners: const [Offset(3, 0), Offset(3, 4), Offset(0, 0), Offset(0, 4)]),
      (rotation: YuvImageRotation.rotation180, mirrored: false, corners: const [Offset(4, 3), Offset(0, 3), Offset(4, 0), Offset(0, 0)]),
      (rotation: YuvImageRotation.rotation270, mirrored: false, corners: const [Offset(0, 4), Offset(0, 0), Offset(3, 4), Offset(3, 0)]),
      (rotation: YuvImageRotation.rotation0, mirrored: true, corners: const [Offset(4, 0), Offset(0, 0), Offset(4, 3), Offset(0, 3)]),
      (rotation: YuvImageRotation.rotation90, mirrored: true, corners: const [Offset(0, 0), Offset(0, 4), Offset(3, 0), Offset(3, 4)]),
      (rotation: YuvImageRotation.rotation180, mirrored: true, corners: const [Offset(0, 3), Offset(4, 3), Offset(0, 0), Offset(4, 0)]),
      (rotation: YuvImageRotation.rotation270, mirrored: true, corners: const [Offset(3, 4), Offset(3, 0), Offset(0, 4), Offset(0, 0)]),
    ];

    for (final testCase in cases) {
      test('${testCase.rotation.name}, mirrored=${testCase.mirrored}', () {
        final geometry = YuvFrameGeometry(
          sourceSize: sourceSize,
          viewSize: testCase.rotation.swapSize ? const Size(3, 4) : sourceSize,
          orientation: YuvFrameOrientation(rotation: testCase.rotation, mirrored: testCase.mirrored),
        );
        final actual = <Offset>[
          MatrixUtils.transformPoint(geometry.sourceToView, Offset.zero),
          MatrixUtils.transformPoint(geometry.sourceToView, const Offset(4, 0)),
          MatrixUtils.transformPoint(geometry.sourceToView, const Offset(0, 3)),
          MatrixUtils.transformPoint(geometry.sourceToView, const Offset(4, 3)),
        ];

        expect(actual, testCase.corners);
        expect(MatrixUtils.transformRect(geometry.viewToSource, geometry.destinationRect), const Rect.fromLTWH(0, 0, 4, 3));
      });
    }
  });

  test('contain and cover place the destination and visible source according to alignment', () {
    final contain = YuvFrameGeometry(sourceSize: const Size(4, 2), viewSize: const Size(8, 8));
    final cover = contain.copyWith(fit: YuvFrameFit.cover);

    expect(contain.destinationRect, const Rect.fromLTWH(0, 2, 8, 4));
    expect(contain.visibleSourceRect, const Rect.fromLTWH(0, 0, 4, 2));
    expect(cover.destinationRect, const Rect.fromLTWH(-4, 0, 16, 8));
    expect(cover.visibleSourceRect, const Rect.fromLTWH(1, 0, 2, 2));

    final placements = <(Alignment, Rect, Rect)>[
      (Alignment.topLeft, const Rect.fromLTWH(0, 0, 8, 4), const Rect.fromLTWH(0, 0, 2, 2)),
      (Alignment.center, const Rect.fromLTWH(0, 2, 8, 4), const Rect.fromLTWH(1, 0, 2, 2)),
      (Alignment.bottomRight, const Rect.fromLTWH(0, 4, 8, 4), const Rect.fromLTWH(2, 0, 2, 2)),
    ];
    for (final (alignment, containDestination, coverSource) in placements) {
      expect(contain.copyWith(alignment: alignment).destinationRect, containDestination);
      expect(cover.copyWith(alignment: alignment).visibleSourceRect, coverSource);
    }
  });

  test('requires positive sizes and a matching source image', () {
    expect(() => YuvFrameGeometry(sourceSize: Size.zero, viewSize: const Size(1, 1)), throwsArgumentError);
    expect(() => YuvFrameGeometry(sourceSize: const Size(1, 1), viewSize: Size.zero), throwsArgumentError);

    final geometry = YuvFrameGeometry(sourceSize: const Size(2, 2), viewSize: const Size(2, 2));
    expect(() => geometry.apply(YuvImage.bgra(1, 1)), throwsArgumentError);
  });

  test('apply crops the visible source before rotating and mirroring', () async {
    await YuvFfi.initialize();
    final source = YuvImage.bgra(4, 2)..applyRgbaBytes(_uniqueRgba(4, 2));
    final sourceBefore = Uint8List.fromList(source.toBgraBytes());
    final geometry = YuvFrameGeometry(
      sourceSize: source.size,
      viewSize: const Size(2, 2),
      orientation: const YuvFrameOrientation(rotation: YuvImageRotation.rotation90, mirrored: true),
      fit: YuvFrameFit.cover,
    );

    final actual = geometry.apply(source);
    final expected = source.cropped(const Rect.fromLTWH(1, 0, 2, 2))
      ..applyRotation(YuvImageRotation.rotation90)
      ..applyFlipHorizontal();

    expect(actual.toBgraBytes(), expected.toBgraBytes());
    expect(source.toBgraBytes(), sourceBefore);
  });

  test('odd source crops, rotates, and mirrors with cover geometry', () async {
    await YuvFfi.initialize();
    final source = YuvImage.bgra(5, 3)..applyRgbaBytes(_uniqueRgba(5, 3));
    final geometry = YuvFrameGeometry(
      sourceSize: source.size,
      viewSize: const Size(1, 5),
      orientation: const YuvFrameOrientation(rotation: YuvImageRotation.rotation90, mirrored: true),
      fit: YuvFrameFit.cover,
    );

    final actual = geometry.apply(source);
    final expected = source.cropped(geometry.visibleSourceRect).rotated(YuvImageRotation.rotation90)..applyFlipHorizontal();

    expect(actual.toBgraBytes(), expected.toBgraBytes());
    expect(source.width, 5);
    expect(source.height, 3);
  });

  test('apply equals the visible Canvas pixels for every orientation and supported source format', () async {
    await YuvFfi.initialize();
    for (final (format, size) in <(YuvPixelFormat, Size)>[(YuvPixelFormat.bgra8888, const Size(3, 5)), (YuvPixelFormat.i420, const Size(4, 6))]) {
      for (final rotation in YuvImageRotation.values) {
        for (final mirrored in <bool>[false, true]) {
          final source = YuvImage.fromRgbaBytes(
            _colorNoiseRgba(size.width.toInt(), size.height.toInt()),
            width: size.width.toInt(),
            height: size.height.toInt(),
            format: format,
          );
          final orientation = YuvFrameOrientation(rotation: rotation, mirrored: mirrored);
          final uprightSize = rotation.swapSize ? Size(size.height, size.width) : size;
          final geometry = YuvFrameGeometry(
            sourceSize: source.size,
            viewSize: Size(uprightSize.width, uprightSize.height + 2),
            orientation: orientation,
          );

          final canvasBytes = await _drawSourceToView(source, geometry, geometry.destinationRect);
          final applied = geometry.apply(source);

          expect(canvasBytes, _bgraToRgba(applied.toBgraBytes()), reason: '$format, $rotation, mirrored=$mirrored');
        }
      }
    }
  });
}

Uint8List _uniqueRgba(int width, int height) {
  final bytes = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final offset = (y * width + x) * 4;
      bytes[offset] = x * 40;
      bytes[offset + 1] = y * 80;
      bytes[offset + 2] = 200;
      bytes[offset + 3] = 255;
    }
  }
  return bytes;
}

Uint8List _colorNoiseRgba(int width, int height) {
  final bytes = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final offset = (y * width + x) * 4;
      bytes[offset] = (x * 61 + y * 17 + 13) & 0xff;
      bytes[offset + 1] = (x * 29 + y * 73 + 41) & 0xff;
      bytes[offset + 2] = (x * 47 + y * 37 + 97) & 0xff;
      bytes[offset + 3] = 255;
    }
  }
  return bytes;
}

Future<Uint8List> _drawSourceToView(YuvImage source, YuvFrameGeometry geometry, Rect sampleRect) async {
  final sourceImage = await source.toImage();
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.transform(geometry.sourceToView.storage);
  canvas.drawImage(sourceImage, Offset.zero, Paint()..filterQuality = FilterQuality.none);
  sourceImage.dispose();

  final picture = recorder.endRecording();
  final rendered = await picture.toImage(geometry.viewSize.width.toInt(), geometry.viewSize.height.toInt());
  picture.dispose();
  final data = await rendered.toByteData(format: ImageByteFormat.rawRgba);
  rendered.dispose();
  final sourceBytes = data!.buffer.asUint8List();
  final sampleWidth = sampleRect.width.toInt();
  final sampleHeight = sampleRect.height.toInt();
  final sample = Uint8List(sampleWidth * sampleHeight * 4);
  for (var y = 0; y < sampleHeight; y++) {
    final sourceOffset = ((sampleRect.top.toInt() + y) * geometry.viewSize.width.toInt() + sampleRect.left.toInt()) * 4;
    sample.setRange(y * sampleWidth * 4, (y + 1) * sampleWidth * 4, sourceBytes, sourceOffset);
  }
  return sample;
}

Uint8List _bgraToRgba(Uint8List bgra) {
  final rgba = Uint8List.fromList(bgra);
  for (var offset = 0; offset < rgba.length; offset += 4) {
    final blue = rgba[offset];
    rgba[offset] = rgba[offset + 2];
    rgba[offset + 2] = blue;
  }
  return rgba;
}
