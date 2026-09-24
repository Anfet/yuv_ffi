import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Run with `flutter test` in a checkout of the published `0.2.4` tag.
///
/// The output is the application-owned migration record used by the 0.4.0 test.
void main() {
  test('exports a published 0.2.4 v1 frame', () async {
    final source = YuvImage.i420(2, 2, uvPixelStride: 1);
    source.yPlane.bytes.setAll(0, <int>[1, 2, 3, 4]);
    source.uPlane.bytes[0] = 5;
    source.vPlane.bytes[0] = 6;

    final savedChunks = <List<int>>[];
    await source.save(_ListSink(savedChunks));
    final v1 = savedChunks.expand((chunk) => chunk).toList();
    expect(v1.length, 216);
    // ignore: avoid_print
    print('REL07_024_V1_BASE64 ${base64Encode(v1)}');

    final loaded = YuvImage.i420(1, 1);
    await loaded.load(Stream<List<int>>.value(v1));
    expect(loaded.format.name, 'i420');
    expect(loaded.width, 2);
    expect(loaded.height, 2);
    expect(loaded.planes.map((plane) => plane.bytes.length), orderedEquals(<int>[4, 1, 1]));

    final record = <String, Object>{
      'migrationSchema': 1,
      'format': loaded.format.name,
      'width': loaded.width,
      'height': loaded.height,
      'planes': <Map<String, Object>>[
        for (final plane in loaded.planes)
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
