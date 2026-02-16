import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

const String _testAssetPath = 'test/assets/test_pattern_512.png';
const String _testAssetGoldenPath = 'goldens/yuv_image_widget_from_test_pattern.png';
const Key _goldenBoundaryKey = ValueKey<String>('yuv-widget-golden-boundary');

Future<_FakeBgraImage> _loadFakeBgraFromAsset() async {
  final pngBytes = await File(_testAssetPath).readAsBytes();
  final codec = await ui.instantiateImageCodec(pngBytes);
  final frame = await codec.getNextFrame();
  final width = frame.image.width;
  final height = frame.image.height;
  final rgba = (await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();

  final bgra = Uint8List(rgba.length);
  for (int i = 0; i < rgba.length; i += 4) {
    bgra[i] = rgba[i + 2];
    bgra[i + 1] = rgba[i + 1];
    bgra[i + 2] = rgba[i];
    bgra[i + 3] = rgba[i + 3];
  }

  return _FakeBgraImage(width, height, bytes: bgra);
}

class _FakeBgraImage implements YuvImage {
  _FakeBgraImage(
    this.width,
    this.height, {
    required Uint8List bytes,
    bool shouldThrow = false,
  })  : _shouldThrow = shouldThrow,
        _bytes = bytes,
        _plane = YuvPlane(height, width * 4, 4, bytes);

  final bool _shouldThrow;
  final Uint8List _bytes;
  final YuvPlane _plane;

  @override
  final int width;

  @override
  final int height;

  @override
  YuvFileFormat get format => YuvFileFormat.bgra8888;

  @override
  List<YuvPlane> get planes => [_plane];

  @override
  YuvPlane get yPlane => _plane;

  @override
  YuvPlane get uPlane => throw UnimplementedError();

  @override
  YuvPlane get vPlane => throw UnimplementedError();

  @override
  YuvPlane get y => _plane;

  @override
  YuvPlane? get u => null;

  @override
  YuvPlane? get v => null;

  @override
  ui.Size get size => ui.Size(width.toDouble(), height.toDouble());

  @override
  Uint8List getBytes() => _bytes;

  @override
  YuvImage copy({bool blank = false}) => _FakeBgraImage(
        width,
        height,
        bytes: blank ? Uint8List(_bytes.length) : Uint8List.fromList(_bytes),
        shouldThrow: _shouldThrow,
      );

  @override
  Future<void> save(Sink<List<int>> sink) => throw UnimplementedError();

  @override
  Future<void> load(Stream<List<int>> stream) => throw UnimplementedError();

  @override
  YuvImage blackwhite() => throw UnimplementedError();

  @override
  YuvImage gaussianBlur({int radius = 2, int sigma = 2}) => throw UnimplementedError();

  @override
  YuvImage boxBlur({int radius = 10, ui.Rect? rect}) => throw UnimplementedError();

  @override
  YuvImage meanBlur({int radius = 2, ui.Rect? rect}) => throw UnimplementedError();

  @override
  YuvImage swapNv() => throw UnimplementedError();

  @override
  YuvImage toYuvNv21() => throw UnimplementedError();

  @override
  YuvImage toYuvI420() => throw UnimplementedError();

  @override
  YuvImage toYuvBgra8888() => this;

  @override
  YuvImage crop(ui.Rect rect) => throw UnimplementedError();

  @override
  YuvImage flipHorizontally() => throw UnimplementedError();

  @override
  YuvImage flipVertically() => throw UnimplementedError();

  @override
  void fromRgba8888(Uint8List bytes) => throw UnimplementedError();

  @override
  YuvImage grayscale() => throw UnimplementedError();

  @override
  YuvImage negate() => throw UnimplementedError();

  @override
  YuvImage rotate(YuvImageRotation rotation) => throw UnimplementedError();

  @override
  Uint8List toBgra8888() {
    if (_shouldThrow) {
      throw UnsupportedError('fake decode failure');
    }
    return _bytes;
  }

  @override
  Future<ui.Image> toImage() => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeBgraImage imageFromAsset;

  setUpAll(() async {
    try {
      await YuvFfi.ensureInitialized();
    } catch (_) {
      // Widget tests can run without native backend initialization.
    }
    imageFromAsset = await _loadFakeBgraFromAsset();
  });

  testWidgets('YuvImageWidget delegates frameBuilder', (tester) async {
    var calls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: YuvImageWidget(
          image: imageFromAsset,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            calls++;
            return child;
          },
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(calls, greaterThan(0));
  });

  testWidgets('YuvImageWidget applies width/height from YuvImage', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: YuvImageWidget(image: imageFromAsset),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final imageWidget = tester.widget<Image>(find.byType(Image));
    expect(imageWidget.width, imageFromAsset.width.toDouble());
    expect(imageWidget.height, imageFromAsset.height.toDouble());
  });

  testWidgets('YuvImageWidget delegates errorBuilder on provider errors', (tester) async {
    final broken = _FakeBgraImage(
      imageFromAsset.width,
      imageFromAsset.height,
      bytes: imageFromAsset.getBytes(),
      shouldThrow: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: YuvImageWidget(
          image: broken,
          errorBuilder: (context, error, stackTrace) {
            return const Text('image-error');
          },
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('image-error'), findsOneWidget);
  });

  testWidgets('YuvImageWidget matches golden', (tester) async {
    await tester.binding.setSurfaceSize(
      Size(imageFromAsset.width.toDouble(), imageFromAsset.height.toDouble()),
    );
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: ColoredBox(
          color: Colors.black,
          child: Center(
            child: RepaintBoundary(
              key: _goldenBoundaryKey,
              child: YuvImageWidget(image: imageFromAsset),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(_goldenBoundaryKey),
      matchesGoldenFile(_testAssetGoldenPath),
    );
  });
}
