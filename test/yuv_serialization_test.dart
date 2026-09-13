import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_codec.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Verifies YUV-07: the serialization format is versioned, transactional and
/// identical on every backend.
///
/// These cases only allocate planes in Dart, so they must run without a native
/// library: a skip branch would hide exactly the defects this card is about.
void main() {
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

  group('round-trip', () {
    for (final format in YuvFileFormat.values) {
      test('preserves format, dimensions, strides and bytes for ${format.name}', () async {
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

    test('survives a fragmented stream', () async {
      final payload = await validPayload();
      final target = YuvImage.i420(2, 2);

      await target.load(asFragmentedStream(payload));

      expect(target.width, 8);
      expect(target.height, 8);
    });

    test('preserves a padded plane layout', () async {
      final source = YuvImage.bgra(2, 2, planes: <YuvPlane>[YuvPlane(2, 16, 4, Uint8List(32))]);
      final target = YuvImage.bgra(1, 1);

      await target.load(asStream(await save(source)));

      expect(target.yPlane.rowStride, 16);
      expect(target.yPlane.bytes.length, 32);
    });
  });

  group('malformed payloads throw FormatException', () {
    test('an empty payload', () async {
      await expectLater(YuvImage.i420(2, 2).load(asStream(const <int>[])), throwsFormatException);
    });

    test('a truncated header', () async {
      final payload = await validPayload();
      await expectLater(YuvImage.i420(2, 2).load(asStream(payload.sublist(0, 3))), throwsFormatException);
    });

    test('a payload truncated midway through the planes', () async {
      final payload = await validPayload();
      await expectLater(YuvImage.i420(2, 2).load(asStream(payload.sublist(0, payload.length ~/ 2))), throwsFormatException);
    });

    test('a header that is not JSON', () async {
      final payload = _payloadWithHeader('this is not json');
      await expectLater(YuvCodec.decode(payload), throwsFormatException);
    });

    test('a header that is a JSON array rather than an object', () async {
      final payload = _payloadWithHeader(jsonEncode(<int>[1, 2, 3]));
      await expectLater(YuvCodec.decode(payload), throwsFormatException);
    });

    test('an unsupported version', () async {
      final payload = _payloadWithHeader(jsonEncode(<String, Object>{'version': 99, 'format': 'i420', 'width': 8, 'height': 8}));
      await expectLater(YuvCodec.decode(payload), throwsFormatException);
    });

    test('a missing version', () async {
      final payload = _payloadWithHeader(jsonEncode(<String, Object>{'format': 'i420', 'width': 8, 'height': 8}));
      await expectLater(YuvCodec.decode(payload), throwsFormatException);
    });

    test('an unknown format name', () async {
      final payload = _payloadWithHeader(jsonEncode(<String, Object>{'version': 1, 'format': 'rgb565', 'width': 8, 'height': 8}));
      await expectLater(YuvCodec.decode(payload), throwsFormatException);
    });

    test('dimensions of the wrong type', () async {
      final payload = _payloadWithHeader(jsonEncode(<String, Object>{'version': 1, 'format': 'i420', 'width': '8', 'height': 8}));
      await expectLater(YuvCodec.decode(payload), throwsFormatException);
    });

    test('non-positive dimensions', () async {
      final payload = _payloadWithHeader(jsonEncode(<String, Object>{'version': 1, 'format': 'i420', 'width': 0, 'height': 8}));
      await expectLater(YuvCodec.decode(payload), throwsFormatException);
    });

    test('a wrong plane count for the format', () async {
      final payload = await validPayload();
      // The plane count byte sits right after the header block.
      final headerLength = ByteData.view(payload.buffer).getUint32(0, Endian.little);
      final patched = Uint8List.fromList(payload)..[4 + headerLength] = 2;
      await expectLater(YuvCodec.decode(patched), throwsFormatException);
    });

    test('trailing bytes after a complete payload', () async {
      final payload = await validPayload();
      final withTrailer = Uint8List.fromList(<int>[...payload, 0, 0, 0]);
      await expectLater(YuvCodec.decode(withTrailer), throwsFormatException);
    });

    test('a plane length that disagrees with its declared geometry', () async {
      final payload = await validPayload();
      final headerLength = ByteData.view(payload.buffer).getUint32(0, Endian.little);
      // First plane record starts after the header block and the count byte.
      final firstPlane = 4 + headerLength + 1;
      final patched = Uint8List.fromList(payload);
      // Claim one more row than the bytes can hold.
      ByteData.view(patched.buffer).setUint32(firstPlane, 999, Endian.little);
      await expectLater(YuvCodec.decode(patched), throwsFormatException);
    });

    test('a plane length far beyond what remains', () async {
      final payload = await validPayload();
      final headerLength = ByteData.view(payload.buffer).getUint32(0, Endian.little);
      final firstPlaneLength = 4 + headerLength + 1 + 12;
      final patched = Uint8List.fromList(payload);
      ByteData.view(patched.buffer).setUint32(firstPlaneLength, 0x7FFFFFFF, Endian.little);
      await expectLater(YuvCodec.decode(patched), throwsFormatException);
    });
  });

  group('a failed load leaves the image untouched', () {
    test('after a truncated payload', () async {
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

    test('after a payload with trailing garbage', () async {
      final image = YuvImage.i420(8, 8);
      final before = Uint8List.fromList(image.getBytes());

      final payload = await validPayload(format: YuvFileFormat.nv21, width: 16, height: 16);
      await expectLater(image.load(asStream(<int>[...payload, 1, 2, 3])), throwsFormatException);

      expect(image.format, YuvFileFormat.i420);
      expect(image.width, 8);
      expect(image.getBytes(), orderedEquals(before));
    });
  });

  group('codec safety does not depend on assert', () {
    test('a truncated buffer is rejected by an explicit check', () async {
      // Run the decoder directly so the result does not depend on whether
      // asserts are enabled, which is what the old reader relied on.
      await expectLater(YuvCodec.decode(Uint8List(2)), throwsFormatException);
    });

    test('the declared version is the one the encoder writes', () async {
      final payload = await validPayload();
      final headerLength = ByteData.view(payload.buffer).getUint32(0, Endian.little);
      final header = jsonDecode(utf8.decode(payload.sublist(4, 4 + headerLength))) as Map<String, dynamic>;

      expect(header['version'], YuvCodec.version);
    });
  });

  group('load() and the revision contract', () {
    test('a successful load advances the revision exactly once', () async {
      final payload = await validPayload(width: 16, height: 16);
      final target = YuvImage.i420(2, 2);
      final before = target.revision;

      await target.load(asStream(payload));

      expect(target.revision, before + 1);
    });

    test('a fragmented successful load still advances it exactly once', () async {
      final payload = await validPayload(width: 16, height: 16);
      final target = YuvImage.i420(2, 2);
      final before = target.revision;

      await target.load(asFragmentedStream(payload));

      expect(target.revision, before + 1);
    });

    test('a rejected payload leaves the revision untouched', () async {
      final payload = await validPayload(width: 16, height: 16);
      final target = YuvImage.i420(2, 2);
      final before = target.revision;

      await expectLater(target.load(asStream(payload.sublist(0, payload.length ~/ 2))), throwsFormatException);

      expect(target.revision, before, reason: 'a failed load must not look like a new frame');
    });

    test('trailing garbage leaves the revision untouched', () async {
      final payload = await validPayload(width: 16, height: 16);
      final target = YuvImage.i420(2, 2);
      final before = target.revision;

      await expectLater(target.load(asStream(<int>[...payload, 7, 7, 7])), throwsFormatException);

      expect(target.revision, before);
    });
  });

  group('the payload is read sequentially', () {
    test('invalid metadata is rejected without reading the declared plane', () async {
      // The plane length word claims far more than the stream will ever supply.
      // A sequential reader rejects it on the metadata alone; a collecting one
      // would first try to accumulate everything.
      final payload = await validPayload();
      final headerLength = ByteData.view(payload.buffer).getUint32(0, Endian.little);
      final firstPlaneLength = 4 + headerLength + 1 + 12;
      final patched = Uint8List.fromList(payload);
      ByteData.view(patched.buffer).setUint32(firstPlaneLength, 0x3FFFFFFF, Endian.little);

      await expectLater(YuvCodec.decode(patched), throwsFormatException);
    });

    test('a never-ending stream is rejected as soon as metadata is impossible', () async {
      // The stream deliberately never closes. A reader that waited for `done`
      // before parsing would hang here instead of failing.
      final payload = await validPayload();
      final headerLength = ByteData.view(payload.buffer).getUint32(0, Endian.little);
      final patched = Uint8List.fromList(payload)..[4 + headerLength] = 7; // impossible plane count

      final controller = StreamController<List<int>>();
      addTearDown(controller.close);
      controller.add(patched);

      await expectLater(
        YuvCodec.decodeStream(controller.stream).timeout(const Duration(seconds: 5)),
        throwsFormatException,
      );
    });

    test('an oversized plane length is refused before allocation', () async {
      final payload = await validPayload();
      final headerLength = ByteData.view(payload.buffer).getUint32(0, Endian.little);
      final firstPlaneLength = 4 + headerLength + 1 + 12;
      final patched = Uint8List.fromList(payload);
      // Above maxPlaneBytes, so it must be refused on the metadata check.
      ByteData.view(patched.buffer).setUint32(firstPlaneLength, 0x7FFFFFFF, Endian.little);

      await expectLater(YuvCodec.decode(patched), throwsFormatException);
    });

    test('an oversized header length is refused before the JSON is parsed', () async {
      final out = Uint8List(8);
      ByteData.view(out.buffer).setUint32(0, 0x7FFFFFFF, Endian.little);

      await expectLater(YuvCodec.decode(out), throwsFormatException);
    });

    test('geometry impossible for the header is rejected without requesting the body', () async {
      // Self-consistent arithmetic (height * rowStride == byteLength), so the
      // earlier length check passes, but a 1x1 BGRA image cannot have a plane of
      // two rows. The stream never closes and never supplies the body: a decoder
      // that waited for those bytes would hang until the timeout instead of
      // rejecting on the metadata it already holds.
      final header = utf8.encode(jsonEncode(<String, Object>{'version': 1, 'format': 'bgra8888', 'width': 1, 'height': 1}));
      final metadata = Uint8List(4 + header.length + 1 + 16);
      final view = ByteData.view(metadata.buffer);
      view.setUint32(0, header.length, Endian.little);
      metadata.setRange(4, 4 + header.length, header);
      int offset = 4 + header.length;
      view.setUint8(offset, 1);
      offset += 1;
      view.setUint32(offset, 2, Endian.little); // height: one row too many
      view.setUint32(offset + 4, 4, Endian.little); // rowStride
      view.setUint32(offset + 8, 4, Endian.little); // pixelStride
      view.setUint32(offset + 12, 8, Endian.little); // byteLength == 2 * 4

      final controller = StreamController<List<int>>();
      addTearDown(controller.close);
      controller.add(metadata);

      await expectLater(
        YuvCodec.decodeStream(controller.stream).timeout(const Duration(seconds: 5)),
        throwsFormatException,
      );
    });

    test('trailing bytes delivered in a later chunk are still rejected', () async {
      // A file read in chunks puts a trailer in its own delivery, so checking
      // only what happens to be buffered when the payload ends would miss it.
      final payload = await validPayload(width: 16, height: 16);

      await expectLater(
        YuvCodec.decodeStream(Stream<List<int>>.fromIterable(<List<int>>[
          payload,
          <int>[9, 9, 9]
        ])),
        throwsFormatException,
      );
    });

    test('a trailer after a fragmented payload is rejected', () async {
      final payload = await validPayload(width: 16, height: 16);
      final chunks = <List<int>>[];
      for (int i = 0; i < payload.length; i += 137) {
        chunks.add(payload.sublist(i, i + 137 > payload.length ? payload.length : i + 137));
      }
      chunks.add(<int>[7, 7, 7]);

      await expectLater(YuvCodec.decodeStream(Stream<List<int>>.fromIterable(chunks)), throwsFormatException);
    });

    test('a trailer delivered long after the payload is still rejected', () async {
      // EOF is the frame boundary, so a trailer is a trailer no matter how late
      // it arrives. A decoder that sampled the buffer, or waited only a fixed
      // grace period, would accept this payload purely because the extra bytes
      // were slow — making the format contract depend on the scheduler.
      final payload = await validPayload(width: 16, height: 16);

      final controller = StreamController<List<int>>();
      controller.add(payload);
      // Well beyond any short grace window a previous implementation allowed.
      Future<void>.delayed(const Duration(milliseconds: 250), () {
        controller.add(<int>[5, 5, 5]);
        controller.close();
      });

      await expectLater(
        YuvCodec.decodeStream(controller.stream).timeout(const Duration(seconds: 5)),
        throwsFormatException,
      );
    });

    test('mismatched I420 chroma strides are rejected without requesting the second body', () async {
      // Each plane is individually legal for an 8x8 I420 image, so no per-plane
      // check catches this: U declares a rowStride of 4 and V declares 8. Only
      // the cross-plane rule rejects it, and it has to do so from V's metadata —
      // the V body is never supplied and the stream never closes.
      final header = utf8.encode(jsonEncode(<String, Object>{'version': 1, 'format': 'i420', 'width': 8, 'height': 8}));
      final builder = BytesBuilder();
      final head = Uint8List(4 + header.length + 1);
      ByteData.view(head.buffer).setUint32(0, header.length, Endian.little);
      head.setRange(4, 4 + header.length, header);
      head[4 + header.length] = 3;
      builder.add(head);

      Uint8List planeMetadata(int height, int rowStride, int pixelStride) {
        final out = Uint8List(16);
        final planeView = ByteData.view(out.buffer);
        planeView.setUint32(0, height, Endian.little);
        planeView.setUint32(4, rowStride, Endian.little);
        planeView.setUint32(8, pixelStride, Endian.little);
        planeView.setUint32(12, height * rowStride, Endian.little);
        return out;
      }

      builder
        ..add(planeMetadata(8, 8, 1))
        ..add(Uint8List(64)) // luma, in full
        ..add(planeMetadata(4, 4, 1))
        ..add(Uint8List(16)) // U, in full
        ..add(planeMetadata(4, 8, 1)); // V: legal alone, but does not match U

      final controller = StreamController<List<int>>();
      addTearDown(controller.close);
      controller.add(builder.takeBytes());

      await expectLater(
        YuvCodec.decodeStream(controller.stream).timeout(const Duration(seconds: 5)),
        throwsFormatException,
      );
    });

    test('a chroma plane impossible for the header is rejected without requesting the body', () async {
      // Same shape for a multi-plane format: the luma plane is correct, and the
      // U plane's own arithmetic is consistent, but its row count does not match
      // the chroma height an 8x8 I420 image requires.
      final header = utf8.encode(jsonEncode(<String, Object>{'version': 1, 'format': 'i420', 'width': 8, 'height': 8}));
      final builder = BytesBuilder();
      final head = Uint8List(4 + header.length + 1);
      ByteData.view(head.buffer).setUint32(0, header.length, Endian.little);
      head.setRange(4, 4 + header.length, header);
      head[4 + header.length] = 3;
      builder.add(head);

      Uint8List planeMetadata(int height, int rowStride, int pixelStride) {
        final out = Uint8List(16);
        final planeView = ByteData.view(out.buffer);
        planeView.setUint32(0, height, Endian.little);
        planeView.setUint32(4, rowStride, Endian.little);
        planeView.setUint32(8, pixelStride, Endian.little);
        planeView.setUint32(12, height * rowStride, Endian.little);
        return out;
      }

      builder
        ..add(planeMetadata(8, 8, 1))
        ..add(Uint8List(64)) // the luma plane, supplied in full
        ..add(planeMetadata(8, 4, 1)); // chroma must be 4 rows, not 8

      final controller = StreamController<List<int>>();
      addTearDown(controller.close);
      controller.add(builder.takeBytes());

      await expectLater(
        YuvCodec.decodeStream(controller.stream).timeout(const Duration(seconds: 5)),
        throwsFormatException,
      );
    });
  });
}

/// Builds a payload whose header is [header] and which declares no planes.
///
/// Used for header-level cases, where the plane table is never reached.
Uint8List _payloadWithHeader(String header) {
  final headerBytes = utf8.encode(header);
  final out = Uint8List(4 + headerBytes.length + 1);
  ByteData.view(out.buffer).setUint32(0, headerBytes.length, Endian.little);
  out.setRange(4, 4 + headerBytes.length, headerBytes);
  return out;
}

class _CollectingSink implements Sink<List<int>> {
  _CollectingSink(this.chunks);

  final List<List<int>> chunks;

  @override
  void add(List<int> data) => chunks.add(List<int>.from(data));

  @override
  void close() {}
}
