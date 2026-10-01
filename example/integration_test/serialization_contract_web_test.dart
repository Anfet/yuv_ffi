@Tags(['contract'])
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Web codec preserves serialized frame metadata and bytes', (_) async {
    expect(kIsWeb, isTrue);
    final source = YuvImage.bgra(2, 2, planes: [YuvPlane(2, 8, 4, Uint8List.fromList(List<int>.generate(16, (index) => index)))]);
    final chunks = <List<int>>[];
    await source.encodeTo(_Sink(chunks));
    final decoded = await YuvImage.decode(Stream<List<int>>.fromIterable(chunks));

    expect(decoded.format, YuvPixelFormat.bgra8888);
    expect(decoded.toBytes(), orderedEquals(source.toBytes()));
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
