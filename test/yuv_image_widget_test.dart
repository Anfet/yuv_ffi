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
  YuvImage copy({bool blank = false}) =>
      _FakeBgraImage(width, height, bytes: blank ? Uint8List(_bytes.length) : Uint8List.fromList(_bytes), shouldThrow: _shouldThrow);

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
    conversions++;
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
