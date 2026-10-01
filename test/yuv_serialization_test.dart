@Tags(['contract'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

void main() {
  test('codec v2 round-trips format, geometry and preserved plane bytes', () async {
    final source = YuvImage.bgra(
      2,
      2,
      planes: [
        YuvPlane(2, 12, 4, Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24])),
      ],
      layout: YuvPlaneLayout.preserve,
    );
    final chunks = <List<int>>[];

    await source.encodeTo(_ListSink(chunks));
    final decoded = await YuvImage.decode(Stream<List<int>>.fromIterable(chunks));

    expect(decoded.format, YuvPixelFormat.bgra8888);
    expect(decoded.width, 2);
    expect(decoded.height, 2);
    expect(decoded.yPlane.rowStride, 12);
    expect(decoded.toBytes(), orderedEquals(source.toBytes()));
  });

  test('codec rejects a truncated payload', () async {
    await expectLater(YuvImage.decode(Stream<List<int>>.value(<int>[1, 0, 0])), throwsFormatException);
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
