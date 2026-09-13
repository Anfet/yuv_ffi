import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_revision.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Web acceptance for YUV-20: `YuvImageProvider`'s revision-based cache key
/// must reuse a decoded frame for an unmutated image, miss after a package
/// image is mutated, and always miss for a foreign legacy image that mutates
/// without calling `markDirty()`.
///
/// This runs through `IntegrationTestWidgetsFlutterBinding` rather than
/// `flutter test --platform chrome` so it exercises the same `dart:ui` image
/// decode path a real browser uses (see `wasm_bootstrap_test.dart` for why
/// the plain `flutter test` harness cannot serve this package's assets).
/// Neither fixture below touches the native/WASM backend, so no asset
/// bundle is required here.
///
/// A comparison of providers or hashCodes alone is not sufficient proof: it
/// would pass even if the widget re-decoded on every build. Each fixture
/// therefore counts its own `toBgra8888()` calls, and the assertions are on
/// that counter.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  testWidgets('an unmutated package image is reused across rebuilds', (tester) async {
    expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');

    final image = _FakePackageImage(2, 2, bytes: _syntheticBgra(2, 2, seed: 1));

    await tester.pumpWidget(MaterialApp(home: YuvImageWidget(image: image)));
    await tester.pumpAndSettle();
    final afterFirstBuild = image.conversions;
    expect(afterFirstBuild, greaterThan(0));

    // A new widget instance over the same, untouched image: the provider is
    // recreated but its snapshot is equal, so the decoded frame must be reused.
    await tester.pumpWidget(MaterialApp(home: YuvImageWidget(image: image, boxFit: BoxFit.contain)));
    await tester.pumpAndSettle();

    expect(image.conversions, afterFirstBuild, reason: 'an unmutated frame must not be converted again');
    expect(YuvImageProvider(image), equals(YuvImageProvider(image)));
    expect(YuvImageProvider(image).hashCode, equals(YuvImageProvider(image).hashCode));
  });

  testWidgets('a package image miss its cache entry after mutateInPlace bumps the revision', (tester) async {
    expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');

    final image = _FakePackageImage(2, 2, bytes: _syntheticBgra(2, 2, seed: 1));

    await tester.pumpWidget(MaterialApp(home: YuvImageWidget(image: image)));
    await tester.pumpAndSettle();
    final afterFirstBuild = image.conversions;
    expect(afterFirstBuild, greaterThan(0));

    final keyBefore = YuvImageProvider(image);
    image.mutateInPlace();
    final keyAfter = YuvImageProvider(image);

    expect(keyAfter, isNot(equals(keyBefore)), reason: 'a bumped revision must change the cache key');

    await tester.pumpWidget(MaterialApp(home: YuvImageWidget(image: image, boxFit: BoxFit.contain)));
    await tester.pumpAndSettle();

    expect(image.conversions, greaterThan(afterFirstBuild), reason: 'a mutated frame must not be served from the cache');
  });

  testWidgets('a foreign legacy image always misses after a mutation that skips markDirty', (tester) async {
    expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');

    final image = _FakeForeignImage(2, 2, bytes: _syntheticBgra(2, 2, seed: 7));

    await tester.pumpWidget(MaterialApp(home: YuvImageWidget(image: image)));
    await tester.pumpAndSettle();
    final afterFirstBuild = image.conversions;
    expect(afterFirstBuild, greaterThan(0));

    // No revision seam is implemented, so two providers over the very same,
    // untouched instance must never compare equal: this is the deliberate
    // always-miss trade-off, not a bug in the fixture.
    expect(YuvImageProvider(image), isNot(equals(YuvImageProvider(image))));

    image.mutateWithoutReporting();

    await tester.pumpWidget(MaterialApp(home: YuvImageWidget(image: image, boxFit: BoxFit.contain)));
    await tester.pumpAndSettle();

    expect(
      image.conversions,
      greaterThan(afterFirstBuild),
      reason: 'a foreign image that cannot prove its frame is unchanged must always be re-converted',
    );
  });
}

/// Builds a tightly packed BGRA8888 buffer without touching disk, so this
/// file has no `dart:io` dependency and runs on Web.
Uint8List _syntheticBgra(int width, int height, {required int seed}) {
  final bytes = Uint8List(width * height * 4);
  for (int i = 0; i < bytes.length; i++) {
    bytes[i] = (seed + i * 31) & 0xFF;
  }
  return bytes;
}

/// A counting stand-in for one of this package's own backends.
///
/// Implements [YuvRevisionAware], the package-private seam
/// `YuvImageProvider` uses to prove an unmutated image is safe to reuse:
/// every mutation is reported from inside the mutating method.
class _FakePackageImage implements YuvImage, YuvRevisionAware {
  _FakePackageImage(this.width, this.height, {required Uint8List bytes})
      : _bytes = bytes,
        _plane = YuvPlane(height, width * 4, 4, bytes);

  final Uint8List _bytes;
  final YuvPlane _plane;

  int _revision = 0;

  @override
  int get internalRevision => _revision;

  @override
  void bumpInternalRevision() => _revision++;

  /// Number of times this frame was converted to BGRA.
  ///
  /// A cache hit must not convert again, so this count is what proves the
  /// cache key works; comparing providers alone would not.
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
  YuvImage copy({bool blank = false}) => _FakePackageImage(width, height, bytes: blank ? Uint8List(_bytes.length) : Uint8List.fromList(_bytes));

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
    return _bytes;
  }

  @override
  Future<ui.Image> toImage() => throw UnimplementedError();
}

/// A foreign legacy image: `implements YuvImage` only, predating the
/// revision seam. It mutates its bytes but never calls `markDirty()`, so
/// `YuvImageProvider` cannot trust an unchanged revision as proof of an
/// unchanged frame and must always treat it as a miss.
class _FakeForeignImage implements YuvImage {
  _FakeForeignImage(this.width, this.height, {required Uint8List bytes})
      : _bytes = bytes,
        _plane = YuvPlane(height, width * 4, 4, bytes);

  final Uint8List _bytes;
  final YuvPlane _plane;

  /// Number of times this frame was converted to BGRA.
  int conversions = 0;

  /// Changes pixel content directly, the way a pre-0.2.5 image would, without
  /// reporting the mutation through the revision seam.
  void mutateWithoutReporting() {
    _bytes[0] = (_bytes[0] + 1) & 0xFF;
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
  YuvImage copy({bool blank = false}) => _FakeForeignImage(width, height, bytes: blank ? Uint8List(_bytes.length) : Uint8List.fromList(_bytes));

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
    return _bytes;
  }

  @override
  Future<ui.Image> toImage() => throw UnimplementedError();
}
