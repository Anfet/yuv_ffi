@Tags(['contract'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

void main() {
  test('decode returns an independent image from fragmented encoded bytes', () async {
    final source = YuvImage.i420(
      2,
      2,
      planes: [
        YuvPlane(2, 2, 1, Uint8List.fromList(<int>[1, 2, 3, 4])),
        YuvPlane(1, 1, 1, Uint8List.fromList(<int>[5])),
        YuvPlane(1, 1, 1, Uint8List.fromList(<int>[6])),
      ],
    );
    final chunks = <List<int>>[];
    await source.encodeTo(_Sink(chunks));
    final bytes = Uint8List.fromList(chunks.expand((chunk) => chunk).toList());

    final decoded = await YuvImage.decode(Stream<List<int>>.fromIterable([bytes.sublist(0, 5), bytes.sublist(5)]));
    decoded.yPlane.bytes[0] = 99;

    expect(source.yPlane.bytes.first, 1);
    expect(decoded.yPlane.bytes.first, 99);
  });
}

class _Sink implements Sink<List<int>> {
  _Sink(this.chunks);
  final List<List<int>> chunks;
  @override
  void add(List<int> data) => chunks.add(List<int>.from(data));
  @override
  void close() {}
}
