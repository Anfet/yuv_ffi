@Tags(['contract'])
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Web BGRA factory preserves an explicitly requested padded layout', (_) async {
    expect(kIsWeb, isTrue);
    final bytes = Uint8List.fromList(List<int>.generate(24, (index) => index));
    final image = YuvImage.bgra(2, 2, planes: [YuvPlane(2, 12, 4, bytes)], layout: YuvPlaneLayout.preserve);

    expect(image.yPlane.rowStride, 12);
    expect(image.toBytes(), orderedEquals(bytes));
  });
}
