import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_ffi_example/editor/editor_screen.dart';

void main() {
  testWidgets('an operation changes the presented frame and reset restores the original', (tester) async {
    await YuvFfi.initialize();
    final image = YuvImage.bgra(2, 2)..applyRgbaBytes(Uint8List.fromList([10, 20, 30, 255, 40, 50, 60, 255, 70, 80, 90, 255, 100, 110, 120, 255]));
    final originalBytes = image.toBytes();

    await tester.pumpWidget(MaterialApp(home: EditorScreen(initialImage: image)));
    await tester.pump();
    expect(find.byType(YuvFrameView), findsOneWidget);

    await tester.tap(find.byTooltip('Negate'));
    await tester.pump();
    final state = tester.state<EditorScreenState>(find.byType(EditorScreen));
    expect(state.image!.toBytes(), isNot(orderedEquals(originalBytes)));

    await tester.tap(find.byTooltip('Reset'));
    await tester.pump();
    expect(state.image!.toBytes(), orderedEquals(originalBytes));
  });
}
