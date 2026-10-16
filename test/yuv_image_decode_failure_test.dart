@Tags(['contract'])
library;

import 'dart:async';
import 'dart:ui' as ui;

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

    resetYuvImageDecodeOverride();
    final decoded = await tester.runAsync(image.toImage);
    expect(decoded, isNotNull);
    final result = decoded!;
    expect(result.width, 1);
    expect(result.height, 1);
    result.dispose();
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
    final nextProvider = YuvImageProvider(YuvImage.bgra(2, 3));
    await tester.pumpWidget(Image(image: nextProvider));
    await tester.pumpAndSettle();

    final decoded = await tester.runAsync(() => _decodeProvider(nextProvider));
    await tester.pump();
    expect(decoded, isNotNull);
    final result = decoded!;
    expect(result.width, 2);
    expect(result.height, 3);
    final rawImage = tester.widget<RawImage>(find.byType(RawImage));
    expect(rawImage.image, isNotNull);
    expect(rawImage.image!.width, 2);
    expect(rawImage.image!.height, 3);
  });
}

Future<ui.Image> _decodeProvider(YuvImageProvider provider) async {
  final stream = provider.resolve(ImageConfiguration.empty);
  final completer = Completer<ui.Image>();
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      if (!completer.isCompleted) completer.complete(info.image);
    },
    onError: (error, stackTrace) {
      if (!completer.isCompleted) completer.completeError(error, stackTrace);
    },
  );
  stream.addListener(listener);
  try {
    return await completer.future.timeout(const Duration(seconds: 5));
  } finally {
    stream.removeListener(listener);
  }
}
