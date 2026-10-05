import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

Future<ui.Image> _decodeControlBgraImage() {
  const width = 8;
  const height = 8;
  final bytes = Uint8List(width * height * 4);
  for (var offset = 0; offset < bytes.length; offset += 4) {
    bytes[offset] = 0;
    bytes[offset + 1] = 0;
    bytes[offset + 2] = 255;
    bytes[offset + 3] = 255;
  }

  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(bytes, width, height, ui.PixelFormat.bgra8888, completer.complete);
  return completer.future;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('standard RawImage control survives a boxFit rebuild', (tester) async {
    final image = await _decodeControlBgraImage();
    await tester.pumpWidget(MaterialApp(home: RawImage(image: image)));
    await tester.pumpAndSettle();
    await tester.pumpWidget(MaterialApp(home: RawImage(image: image, fit: BoxFit.contain)));
    await tester.pumpAndSettle();
  });

  testWidgets('standard RawImage control survives another boxFit rebuild', (tester) async {
    final image = await _decodeControlBgraImage();
    await tester.pumpWidget(MaterialApp(home: RawImage(image: image)));
    await tester.pumpAndSettle();
    await tester.pumpWidget(MaterialApp(home: RawImage(image: image, fit: BoxFit.contain)));
    await tester.pumpAndSettle();
  });
}
