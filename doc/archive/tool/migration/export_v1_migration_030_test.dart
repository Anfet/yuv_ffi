// ignore_for_file: deprecated_member_use

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Run this file with flutter test in a checkout of commit 42c2ae1 (0.3.0).
///
/// It exercises the old public load()/save() API and prints the application
/// migration record committed as test/fixtures/codec_v1_i420_2x2_intermediate.json
/// in the 0.4.0 checkout.
void main() {
  test('exports a v1 frame through the 0.3.0 public API', () async {
    final v1 = base64Decode(
      'MgAAAHsidmVyc2lvbiI6MSwiZm9ybWF0IjoiaTQyMCIsIndpZHRoIjoyLCJoZWlnaHQiOjJ9AwIAAAACAAAAAQAAAAQAAAABAgMEAQAAAAEAAAABAAAAAQAAAAUBAAAAAQAAAAEAAAABAAAABg==',
    );

    final image = YuvImage.i420(1, 1);
    // ignore: deprecated_member_use_from_same_package
    await image.load(Stream<List<int>>.value(v1));

    expect(image.format.name, 'i420');
    expect(image.width, 2);
    expect(image.height, 2);
    expect(image.planes.map((plane) => plane.bytes.length), orderedEquals(<int>[4, 1, 1]));

    final resaved = <List<int>>[];
    // ignore: deprecated_member_use_from_same_package
    await image.save(_ListSink(resaved));
    expect(resaved.expand((chunk) => chunk), orderedEquals(v1));

    final record = <String, Object>{
      'migrationSchema': 1,
      'format': image.format.name,
      'width': image.width,
      'height': image.height,
      'planes': <Map<String, Object>>[
        for (final plane in image.planes)
          <String, Object>{
            'height': plane.height,
            'rowStride': plane.rowStride,
            'pixelStride': plane.pixelStride,
            'bytesBase64': base64Encode(plane.bytes),
          },
      ],
    };
    // ignore: avoid_print
    print('REL07_INTERMEDIATE_JSON ${jsonEncode(record)}');
  });
}

class _ListSink implements Sink<List<int>> {
  _ListSink(this.chunks);

  final List<List<int>> chunks;

  @override
  void add(List<int> data) => chunks.add(List<int>.from(data));

  @override
  void close() {}
}
