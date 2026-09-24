import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_revision.dart';
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

/// A counting stand-in for one of this package's own backends.
///
/// It implements [YuvRevisionAware], because that is what the real IO and Web
/// images do and what makes revision-based cache keys safe: every mutation is
/// reported from inside the mutating method. A foreign implementation, which
/// reports nothing, is covered separately in
/// `yuv_image_source_compatibility_test.dart`.
class _FakeBgraImage implements YuvImage, YuvRevisionAware {
  _FakeBgraImage(this.width, this.height, {required Uint8List bytes, bool shouldThrow = false})
    : _shouldThrow = shouldThrow,
      _bytes = bytes,
      _plane = YuvPlane(height, width * 4, 4, bytes);

  final bool _shouldThrow;
  final Uint8List _bytes;
  final YuvPlane _plane;

  int _revision = 0;

  @override
  int get internalRevision => _revision;

  @override
  void bumpInternalRevision() => _revision++;

  /// Number of times this frame was converted to BGRA.
  ///
  /// A cache hit must not convert again, so the count is what proves the cache
  /// key works; comparing providers alone would not.
  int conversions = 0;

  /// Simulates an in-place mutation the way the real backends perform one:
  /// change the bytes, then report it from inside the method.
  void mutateInPlace() {
    _bytes[0] = (_bytes[0] + 1) & 0xFF;
    markDirty();
  }

  @override
  final int width;

  @override
  final int height;

  @override
  YuvPixelFormat get format => YuvPixelFormat.bgra8888;

  @override
  List<YuvPlane> get planes => [_plane];

  @override
  YuvPlane get yPlane => _plane;

  @override
  YuvPlane get uPlane => throw UnimplementedError();

  @override
  YuvPlane get vPlane => throw UnimplementedError();

  YuvPlane get y => _plane;

  YuvPlane? get u => null;

  YuvPlane? get v => null;

  @override
  ui.Size get size => ui.Size(width.toDouble(), height.toDouble());

  Uint8List getBytes() => _bytes;

  @override
  YuvImage copy({bool blank = false}) =>
      _FakeBgraImage(width, height, bytes: blank ? Uint8List(_bytes.length) : Uint8List.fromList(_bytes), shouldThrow: _shouldThrow);

  @override
  YuvImage applyPlanes(Iterable<YuvPlane> planes) => throw UnimplementedError();

  @override
  Future<void> encodeTo(Sink<List<int>> sink) => throw UnimplementedError();

  YuvImage blackwhite() => throw UnimplementedError();

  YuvImage gaussianBlur({int radius = 2, int sigma = 2}) => throw UnimplementedError();

  YuvImage boxBlur({int radius = 10, ui.Rect? rect}) => throw UnimplementedError();

  YuvImage meanBlur({int radius = 2, ui.Rect? rect}) => throw UnimplementedError();

  YuvImage swapNv() => throw UnimplementedError();

  YuvImage toYuvNv21() => throw UnimplementedError();

  YuvImage toYuvI420() => throw UnimplementedError();

  YuvImage toYuvBgra8888() => this;

  YuvImage crop(ui.Rect rect) => throw UnimplementedError();

  YuvImage flipHorizontally() => throw UnimplementedError();

  YuvImage flipVertically() => throw UnimplementedError();

  void fromRgba8888(Uint8List bytes) => throw UnimplementedError();

  YuvImage grayscale() => throw UnimplementedError();

  YuvImage negate() => throw UnimplementedError();

  YuvImage rotate(YuvImageRotation rotation) => throw UnimplementedError();

  Uint8List toBgra8888() => _bytes;

  @override
  Future<ui.Image> toImage() => throw UnimplementedError();

  @override
  YuvImage applyRgbaBytes(Uint8List bytes) => throw UnimplementedError();

  @override
  YuvImage applyGrayscale() => throw UnimplementedError();

  @override
  YuvImage applyBlackWhite() => throw UnimplementedError();

  @override
  YuvImage applyNegate() => throw UnimplementedError();

  @override
  YuvImage applyGaussianBlur({required int radius, required double sigma}) => throw UnimplementedError();

  @override
  YuvImage applyMeanBlur({required int radius, ui.Rect? region}) => throw UnimplementedError();

  @override
  YuvImage applyBoxBlur({required int radius, ui.Rect? region}) => throw UnimplementedError();

  @override
  YuvImage applyCrop(ui.Rect region) => throw UnimplementedError();

  @override
  YuvImage applyFlipHorizontal() => throw UnimplementedError();

  @override
  YuvImage applyFlipVertical() => throw UnimplementedError();

  @override
  YuvImage applyRotation(YuvImageRotation rotation) => throw UnimplementedError();

  @override
  YuvImage applyFormat(YuvPixelFormat format) => throw UnimplementedError();

  @override
  YuvImage applyChromaSwap() => throw UnimplementedError();

  @override
  YuvImage cropped(ui.Rect region) => throw UnimplementedError();

  @override
  YuvImage rotated(YuvImageRotation rotation) => throw UnimplementedError();

  @override
  YuvImage toI420() => throw UnimplementedError();

  @override
  YuvImage toNv12() => throw UnimplementedError();

  @override
  YuvImage toBgra() => throw UnimplementedError();

  @override
  Uint8List toBytes() => throw UnimplementedError();

  @override
  Uint8List toBgraBytes() {
    conversions++;
    if (_shouldThrow) {
      throw UnsupportedError('fake decode failure');
    }
    return _bytes;
  }
}

/// A [YuvImage] whose single BGRA plane has row padding and a pixel gap.
///
/// [toBgraBytes] packs only the four live bytes of each logical pixel and
/// skips [YuvPlane.pixelStride] and [YuvPlane.rowStride] slack, mirroring what
/// the real IO/Web backends do (REL-05/REL-12). This class exists to prove the
/// widget/provider layer correctly consumes that tight output, not to
/// re-verify the packing logic itself.
class _PaddedBgraImage implements YuvImage, YuvRevisionAware {
  _PaddedBgraImage(this.width, this.height, {required int pixelStride, required int rowPadding})
    : pixelStride = pixelStride,
      _plane = YuvPlane(height, width * pixelStride + rowPadding, pixelStride) {
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final base = y * _plane.rowStride + x * pixelStride;
        _plane.bytes[base] = (x * 4) & 0xFF;
        _plane.bytes[base + 1] = (x * 4 + 1) & 0xFF;
        _plane.bytes[base + 2] = (x * 4 + 2) & 0xFF;
        _plane.bytes[base + 3] = (x * 4 + 3) & 0xFF;
      }
    }
  }

  final int pixelStride;
  final YuvPlane _plane;
  int _revision = 0;

  @override
  int get internalRevision => _revision;

  @override
  void bumpInternalRevision() => _revision++;

  @override
  final int width;

  @override
  final int height;

  @override
  YuvPixelFormat get format => YuvPixelFormat.bgra8888;

  @override
  List<YuvPlane> get planes => [_plane];

  @override
  YuvPlane get yPlane => _plane;

  @override
  YuvPlane get uPlane => throw UnimplementedError();

  @override
  YuvPlane get vPlane => throw UnimplementedError();

  YuvPlane get y => _plane;

  YuvPlane? get u => null;

  YuvPlane? get v => null;

  @override
  ui.Size get size => ui.Size(width.toDouble(), height.toDouble());

  Uint8List getBytes() => _plane.bytes;

  @override
  YuvImage copy({bool blank = false}) => throw UnimplementedError();

  @override
  YuvImage applyPlanes(Iterable<YuvPlane> planes) => throw UnimplementedError();

  @override
  Future<void> encodeTo(Sink<List<int>> sink) => throw UnimplementedError();

  YuvImage blackwhite() => throw UnimplementedError();

  YuvImage gaussianBlur({int radius = 2, int sigma = 2}) => throw UnimplementedError();

  YuvImage boxBlur({int radius = 10, ui.Rect? rect}) => throw UnimplementedError();

  YuvImage meanBlur({int radius = 2, ui.Rect? rect}) => throw UnimplementedError();

  YuvImage swapNv() => throw UnimplementedError();

  YuvImage toYuvNv21() => throw UnimplementedError();

  YuvImage toYuvI420() => throw UnimplementedError();

  YuvImage toYuvBgra8888() => this;

  YuvImage crop(ui.Rect rect) => throw UnimplementedError();

  YuvImage flipHorizontally() => throw UnimplementedError();

  YuvImage flipVertically() => throw UnimplementedError();

  void fromRgba8888(Uint8List bytes) => throw UnimplementedError();

  YuvImage grayscale() => throw UnimplementedError();

  YuvImage negate() => throw UnimplementedError();

  YuvImage rotate(YuvImageRotation rotation) => throw UnimplementedError();

  Uint8List toBgra8888() => throw UnimplementedError();

  @override
  Future<ui.Image> toImage() => throw UnimplementedError();

  @override
  YuvImage applyRgbaBytes(Uint8List bytes) => throw UnimplementedError();

  @override
  YuvImage applyGrayscale() => throw UnimplementedError();

  @override
  YuvImage applyBlackWhite() => throw UnimplementedError();

  @override
  YuvImage applyNegate() => throw UnimplementedError();

  @override
  YuvImage applyGaussianBlur({required int radius, required double sigma}) => throw UnimplementedError();

  @override
  YuvImage applyMeanBlur({required int radius, ui.Rect? region}) => throw UnimplementedError();

  @override
  YuvImage applyBoxBlur({required int radius, ui.Rect? region}) => throw UnimplementedError();

  @override
  YuvImage applyCrop(ui.Rect region) => throw UnimplementedError();

  @override
  YuvImage applyFlipHorizontal() => throw UnimplementedError();

  @override
  YuvImage applyFlipVertical() => throw UnimplementedError();

  @override
  YuvImage applyRotation(YuvImageRotation rotation) => throw UnimplementedError();

  @override
  YuvImage applyFormat(YuvPixelFormat format) => throw UnimplementedError();

  @override
  YuvImage applyChromaSwap() => throw UnimplementedError();

  @override
  YuvImage cropped(ui.Rect region) => throw UnimplementedError();

  @override
  YuvImage rotated(YuvImageRotation rotation) => throw UnimplementedError();

  @override
  YuvImage toI420() => throw UnimplementedError();

  @override
  YuvImage toNv12() => throw UnimplementedError();

  @override
  YuvImage toBgra() => throw UnimplementedError();

  @override
  Uint8List toBytes() => throw UnimplementedError();

  @override
  Uint8List toBgraBytes() {
    final tight = Uint8List(width * height * 4);
    for (int py = 0; py < height; py++) {
      for (int px = 0; px < width; px++) {
        final srcBase = py * _plane.rowStride + px * pixelStride;
        final dstBase = (py * width + px) * 4;
        tight[dstBase] = _plane.bytes[srcBase];
        tight[dstBase + 1] = _plane.bytes[srcBase + 1];
        tight[dstBase + 2] = _plane.bytes[srcBase + 2];
        tight[dstBase + 3] = _plane.bytes[srcBase + 3];
      }
    }
    return tight;
  }
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
        home: Center(child: YuvImageWidget(image: imageFromAsset)),
      ),
    );
    await tester.pumpAndSettle();

    final imageWidget = tester.widget<Image>(find.byType(Image));
    expect(imageWidget.width, imageFromAsset.width.toDouble());
    expect(imageWidget.height, imageFromAsset.height.toDouble());
  });

  testWidgets('YuvImageWidget delegates errorBuilder on provider errors', (tester) async {
    final broken = _FakeBgraImage(imageFromAsset.width, imageFromAsset.height, bytes: imageFromAsset.getBytes(), shouldThrow: true);

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

  group('image cache key', () {
    setUp(() {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    });

    test('F-006 diagnostic case: two providers of one frame share a key', () {
      final image = _FakeBgraImage(4, 4, bytes: Uint8List(4 * 4 * 4));

      final first = YuvImageProvider(image);
      final second = YuvImageProvider(image);

      expect(first, equals(second));
      expect(first.hashCode, equals(second.hashCode));
    });

    test('a mutation makes a new provider a different key', () {
      final image = _FakeBgraImage(4, 4, bytes: Uint8List(4 * 4 * 4));
      final before = YuvImageProvider(image);

      image.mutateInPlace();
      final after = YuvImageProvider(image);

      expect(after, isNot(equals(before)));
      expect(after.hashCode, isNot(equals(before.hashCode)));
    });

    test('markDirty invalidates the key after a direct plane write', () {
      final image = _FakeBgraImage(4, 4, bytes: Uint8List(4 * 4 * 4));
      final before = YuvImageProvider(image);

      // Writing straight into plane bytes cannot be intercepted, so the key
      // only changes once the caller signals it.
      image.yPlane.bytes[0] = 0xFF;
      expect(YuvImageProvider(image), equals(before), reason: 'a silent write must not change the key on its own');

      image.markDirty();
      expect(YuvImageProvider(image), isNot(equals(before)));
    });

    test('two different images never share a key', () {
      final a = _FakeBgraImage(4, 4, bytes: Uint8List(4 * 4 * 4));
      final b = _FakeBgraImage(4, 4, bytes: Uint8List(4 * 4 * 4));

      expect(YuvImageProvider(a), isNot(equals(YuvImageProvider(b))));
    });

    test('the key snapshot does not drift after a later mutation', () {
      final image = _FakeBgraImage(4, 4, bytes: Uint8List(4 * 4 * 4));
      final key = YuvImageProvider(image);
      final hashWhenCached = key.hashCode;

      image.mutateInPlace();

      // A key already stored in the image cache must keep its hashCode, or the
      // cache entry becomes unreachable and leaks.
      expect(key.hashCode, hashWhenCached);
    });

    testWidgets('an unchanged frame is converted once across rebuilds', (tester) async {
      final image = _FakeBgraImage(imageFromAsset.width, imageFromAsset.height, bytes: imageFromAsset.getBytes());

      await tester.pumpWidget(MaterialApp(home: YuvImageWidget(image: image)));
      await tester.pumpAndSettle();
      final afterFirstBuild = image.conversions;
      expect(afterFirstBuild, greaterThan(0));

      // Rebuild with a new widget instance: the provider is recreated, but the
      // key is equal, so the decoded frame must be reused.
      await tester.pumpWidget(
        MaterialApp(
          home: YuvImageWidget(image: image, boxFit: BoxFit.contain),
        ),
      );
      await tester.pumpAndSettle();

      expect(image.conversions, afterFirstBuild, reason: 'an unchanged frame must not be converted again');
    });

    testWidgets('a mutated frame is converted again', (tester) async {
      final image = _FakeBgraImage(imageFromAsset.width, imageFromAsset.height, bytes: imageFromAsset.getBytes());

      await tester.pumpWidget(MaterialApp(home: YuvImageWidget(image: image)));
      await tester.pumpAndSettle();
      final afterFirstBuild = image.conversions;

      image.mutateInPlace();
      await tester.pumpWidget(
        MaterialApp(
          home: YuvImageWidget(image: image, boxFit: BoxFit.contain),
        ),
      );
      await tester.pumpAndSettle();

      expect(image.conversions, greaterThan(afterFirstBuild), reason: 'a mutated frame must not be served from the cache');
    });

    testWidgets('a direct plane write plus markDirty changes the decoded pixels the widget shows', (tester) async {
      final image = _FakeBgraImage(2, 2, bytes: Uint8List(2 * 2 * 4));

      await tester.pumpWidget(MaterialApp(home: YuvImageWidget(image: image)));
      await tester.pumpAndSettle();

      // Bytes fed to ui.decodeImageFromPixels come straight from toBgraBytes(),
      // so comparing its output before/after is exactly what the widget saw.
      final beforeBytes = Uint8List.fromList(image.toBgraBytes());
      image.conversions = 0;

      // Direct write through the mutable plane API, exactly as documented on
      // `YuvImageInvalidation.markDirty`. This fake's backing bytes are shared
      // with getBytes()/toBgraBytes() through the constructor, mirroring the
      // real backends where the plane and the frame's bytes are one buffer.
      image.getBytes()[0] = 0xAB;
      image.markDirty();

      await tester.pumpWidget(
        MaterialApp(
          home: YuvImageWidget(image: image, boxFit: BoxFit.contain),
        ),
      );
      await tester.pumpAndSettle();

      expect(image.conversions, greaterThan(0), reason: 'markDirty after a direct write must force a redecode, not a cache hit');
      final afterBytes = image.toBgraBytes();
      expect(afterBytes[0], 0xAB);
      expect(afterBytes, isNot(orderedEquals(beforeBytes)));
    });
  });

  testWidgets('YuvImageWidget renders a padded BGRA source through toBgraBytes()', (tester) async {
    const width = 3;
    const height = 2;
    final padded = _PaddedBgraImage(width, height, pixelStride: 5, rowPadding: 7);

    await tester.pumpWidget(
      MaterialApp(
        home: Center(child: YuvImageWidget(image: padded)),
      ),
    );
    await tester.pumpAndSettle();

    final imageWidget = tester.widget<Image>(find.byType(Image));
    expect(imageWidget.width, width.toDouble());
    expect(imageWidget.height, height.toDouble());

    // The widget must have decoded successfully (no error builder triggered)
    // and the tight bytes toBgraBytes() produced must be exactly width*height*4
    // with no padding or gap bytes leaking into the packed pixel content.
    final tight = padded.toBgraBytes();
    expect(tight.length, width * height * 4);
    for (int x = 0; x < width; x++) {
      final base = x * 4;
      expect(tight[base], (x * 4) & 0xFF);
      expect(tight[base + 1], (x * 4 + 1) & 0xFF);
      expect(tight[base + 2], (x * 4 + 2) & 0xFF);
      expect(tight[base + 3], (x * 4 + 3) & 0xFF);
    }
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('YuvImageWidget matches golden', (tester) async {
    await tester.binding.setSurfaceSize(Size(imageFromAsset.width.toDouble(), imageFromAsset.height.toDouble()));
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

    await expectLater(find.byKey(_goldenBoundaryKey), matchesGoldenFile(_testAssetGoldenPath));
  });
}
