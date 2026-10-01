@Tags(['contract'])
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Web image-provider key changes after explicit frame invalidation', (_) async {
    expect(kIsWeb, isTrue);
    final image = YuvImage.bgra(2, 2);
    final before = YuvImageProvider(image);

    image.markDirty();

    expect(YuvImageProvider(image), isNot(before));
  });
}
