import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_ffi_example/editor/editor_screen.dart';

void main() {
  testWidgets('crop and negate change the presented frame and reset restores the original', (tester) async {
    await YuvFfi.initialize();
    final image = YuvImage.bgra(8, 8)..applyRgbaBytes(Uint8List.fromList(List<int>.generate(8 * 8 * 4, (index) => index % 4 == 3 ? 255 : index)));
    final originalBytes = image.toBytes();
    final originalWidth = image.width;
    final originalHeight = image.height;

    await tester.pumpWidget(MaterialApp(home: EditorScreen(initialImage: image)));
    await tester.pump();
    expect(find.byType(YuvFrameView), findsOneWidget);

    await tester.tap(find.byTooltip('crop image'));
    await tester.pump();
    final state = tester.state<EditorScreenState>(find.byType(EditorScreen));
    expect(state.image!.width, lessThan(originalWidth));
    expect(state.image!.height, lessThan(originalHeight));
    final croppedBytes = state.image!.toBytes();

    await tester.tap(find.byTooltip('Negate'));
    await tester.pump();
    expect(state.image!.toBytes(), isNot(orderedEquals(croppedBytes)));

    await tester.tap(find.byTooltip('Reset'));
    await tester.pump();
    expect(state.image!.toBytes(), orderedEquals(originalBytes));
  });
}
