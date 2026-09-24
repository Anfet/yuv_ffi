import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_codec.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Web acceptance for YUV-07: the serialization codec (`YuvCodec`), shared by
/// the native and Web backends, must prove its contract executing on the real
/// WASM backend served by a browser, not only on the VM.
///
/// This ports the core cases from `test/yuv_serialization_test.dart` into this
/// package's integration harness (see `wasm_bootstrap_test.dart`) instead of
/// `flutter test --platform chrome`, which serves no asset bundle and cannot
/// load the WASM module.
///
/// Cases that depend on an unclosed `StreamController` staying open (guarded by
/// a 5-second timeout in the VM suite) are intentionally not ported here: they
/// are timing-sensitive and belong to the VM suite, not this deterministic one.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Serializes [image] the way a caller would.
  Future<Uint8List> save(YuvImage image) async {
    final chunks = <List<int>>[];
    await image.save(_CollectingSink(chunks));
    final total = chunks.fold<int>(0, (sum, chunk) => sum + chunk.length);
    final out = Uint8List(total);
    int offset = 0;
    for (final chunk in chunks) {
      out.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return out;
  }

  /// A valid payload for an image whose planes carry a recognisable pattern.
  Future<Uint8List> validPayload({YuvFileFormat format = YuvFileFormat.i420, int width = 8, int height = 8}) async {
    final image = YuvImage(format, width, height);
    for (int i = 0; i < image.planes.length; i++) {
      final bytes = image.planes[i].bytes;
      for (int j = 0; j < bytes.length; j++) {
        bytes[j] = ((i + 1) * 31 + j) & 0xFF;
      }
    }
    return save(image);
  }

  Stream<List<int>> asStream(List<int> bytes) => Stream<List<int>>.fromIterable(<List<int>>[bytes]);

  /// Feeds the payload in small chunks, the way a real file or socket would.
  Stream<List<int>> asFragmentedStream(List<int> bytes, {int chunk = 7}) => Stream<List<int>>.fromIterable(<List<int>>[
    for (int start = 0; start < bytes.length; start += chunk) bytes.sublist(start, (start + chunk).clamp(0, bytes.length)),
  ]);

  setUpAll(() async {
    await YuvFfi.ensureInitialized();
  });

  group('round-trip', () {
    for (final format in YuvFileFormat.values) {
      testWidgets('preserves format, dimensions, strides and bytes for ${format.name}', (tester) async {
        expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');

        await YuvFfi.ensureInitialized();

        final source = YuvImage(format, 8, 8);
        for (int i = 0; i < source.planes.length; i++) {
          final bytes = source.planes[i].bytes;
          for (int j = 0; j < bytes.length; j++) {
            bytes[j] = ((i + 1) * 17 + j) & 0xFF;
          }
        }

        final target = YuvImage(format, 2, 2);
        await target.load(asStream(await save(source)));

        expect(target.format, source.format);
        expect(target.width, source.width);
        expect(target.height, source.height);
        expect(target.planes.length, source.planes.length);
        for (int i = 0; i < source.planes.length; i++) {
          expect(target.planes[i].rowStride, source.planes[i].rowStride, reason: 'plane $i rowStride');
          expect(target.planes[i].pixelStride, source.planes[i].pixelStride, reason: 'plane $i pixelStride');
          expect(target.planes[i].bytes, orderedEquals(source.planes[i].bytes), reason: 'plane $i bytes');
        }
      });
    }

    testWidgets('survives a fragmented stream', (tester) async {
      expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');

      await YuvFfi.ensureInitialized();

      final payload = await validPayload();
      final target = YuvImage.i420(2, 2);

      await target.load(asFragmentedStream(payload));

      expect(target.width, 8);
      expect(target.height, 8);
    });

    testWidgets('preserves a padded plane layout', (tester) async {
      expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');

      await YuvFfi.ensureInitialized();

      final source = YuvImage.bgra(2, 2, planes: <YuvPlane>[YuvPlane(2, 16, 4, Uint8List(32))]);
      final target = YuvImage.bgra(1, 1);

      await target.load(asStream(await save(source)));

      expect(target.yPlane.rowStride, 16);
      expect(target.yPlane.bytes.length, 32);
    });
  });

  group('malformed payloads throw FormatException', () {
    testWidgets('an empty payload', (tester) async {
      expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');

      await YuvFfi.ensureInitialized();

      await expectLater(YuvImage.i420(2, 2).load(asStream(const <int>[])), throwsFormatException);
    });

    testWidgets('a truncated header', (tester) async {
      expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');

      await YuvFfi.ensureInitialized();

      final payload = await validPayload();
      await expectLater(YuvImage.i420(2, 2).load(asStream(payload.sublist(0, 3))), throwsFormatException);
    });

    testWidgets('a payload truncated midway through the planes', (tester) async {
      expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');

      await YuvFfi.ensureInitialized();

      final payload = await validPayload();
      await expectLater(YuvImage.i420(2, 2).load(asStream(payload.sublist(0, payload.length ~/ 2))), throwsFormatException);
    });

    testWidgets('trailing bytes after a complete payload', (tester) async {
      expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');

      await YuvFfi.ensureInitialized();

      final payload = await validPayload();
      final withTrailer = Uint8List.fromList(<int>[...payload, 0, 0, 0]);
      await expectLater(YuvCodec.decode(withTrailer), throwsFormatException);
    });
  });

  group('a failed load leaves the image untouched', () {
    testWidgets('after a truncated payload', (tester) async {
      expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');

      await YuvFfi.ensureInitialized();

      final image = YuvImage.i420(8, 8);
      for (int i = 0; i < image.yPlane.bytes.length; i++) {
        image.yPlane.bytes[i] = (i + 7) & 0xFF;
      }
      final before = (
        width: image.width,
        height: image.height,
        format: image.format,
        planeCount: image.planes.length,
        bytes: Uint8List.fromList(image.getBytes()),
      );

      final payload = await validPayload(format: YuvFileFormat.nv21, width: 16, height: 16);
      await expectLater(image.load(asStream(payload.sublist(0, payload.length ~/ 2))), throwsFormatException);

      expect(image.width, before.width);
      expect(image.height, before.height);
      expect(image.format, before.format);
      expect(image.planes.length, before.planeCount);
      expect(image.getBytes(), orderedEquals(before.bytes), reason: 'plane bytes were mutated by a failed load');
    });
  });

  group('load() and the revision contract', () {
    testWidgets('a successful load advances the revision exactly once', (tester) async {
      expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');

      await YuvFfi.ensureInitialized();

      final payload = await validPayload(width: 16, height: 16);
      final target = YuvImage.i420(2, 2);
      final before = target.revision;

      await target.load(asStream(payload));

      expect(target.revision, before + 1);
    });

    testWidgets('a rejected payload leaves the revision untouched', (tester) async {
      expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');

      await YuvFfi.ensureInitialized();

      final payload = await validPayload(width: 16, height: 16);
      final target = YuvImage.i420(2, 2);
      final before = target.revision;

      await expectLater(target.load(asStream(payload.sublist(0, payload.length ~/ 2))), throwsFormatException);

      expect(target.revision, before, reason: 'a failed load must not look like a new frame');
    });
  });

  group('the payload is read sequentially', () {
    testWidgets('trailing bytes delivered in a later chunk are still rejected', (tester) async {
      // A file read in chunks puts a trailer in its own delivery, so checking
      // only what happens to be buffered when the payload ends would miss it.
      // EOF is the frame boundary, so a trailer delivered later is still a
      // trailer.
      expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');

      await YuvFfi.ensureInitialized();

      final payload = await validPayload(width: 16, height: 16);

      await expectLater(
        YuvCodec.decodeStream(
          Stream<List<int>>.fromIterable(<List<int>>[
            payload,
            <int>[9, 9, 9],
          ]),
        ),
        throwsFormatException,
      );
    });
  });
}

class _CollectingSink implements Sink<List<int>> {
  _CollectingSink(this.chunks);

  final List<List<int>> chunks;

  @override
  void add(List<int> data) => chunks.add(List<int>.from(data));

  @override
  void close() {}
}

// ignore_for_file: deprecated_member_use
// This suite specifies the retained legacy save/load compatibility contract.
