@Tags(['contract'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_image_decoder.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

void main() {
  final failure = StateError('controlled decode failure');

  setUp(() {
    resetYuvImageDecodeOverride();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  tearDown(() {
    resetYuvImageDecodeOverride();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  testWidgets('toImage completes with the asynchronous decoder error', (tester) async {
    debugYuvImageDecodeOverride = (_, _, _, _) async => throw failure;
    final image = YuvImage.bgra(1, 1);

    await tester.runAsync(() async {
      await expectLater(image.toImage(), throwsA(same(failure)));
    });
  });

  testWidgets('ImageProvider forwards decode failure to errorBuilder and a new frame decodes', (tester) async {
    debugYuvImageDecodeOverride = (_, _, _, _) async => throw failure;
    final failedProvider = YuvImageProvider(YuvImage.bgra(1, 1));
    Object? actualError;
    await tester.pumpWidget(
      MaterialApp(
        home: Image(
          image: failedProvider,
          errorBuilder: (context, error, stackTrace) {
            actualError = error;
            return const Text('decode failed', key: ValueKey('decode-error'));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('decode-error')), findsOneWidget);
    expect(actualError, same(failure));
    expect(PaintingBinding.instance.imageCache.containsKey(failedProvider), isFalse);

    resetYuvImageDecodeOverride();
    await tester.pumpWidget(Image(image: YuvImageProvider(YuvImage.bgra(1, 1))));
    await tester.pumpAndSettle();

    expect(find.byType(RawImage), findsOneWidget);
  });
}
