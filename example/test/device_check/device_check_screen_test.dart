import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi_example/device_check/device_check_report.dart';
import 'package:yuv_ffi_example/device_check/device_check_screen.dart';

void main() {
  testWidgets('skip completes every step and copies the final JSON', (tester) async {
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(const MaterialApp(home: DeviceCheckScreen(cameraEnabled: false)));

    for (int index = 0; index < 7; index++) {
      await tester.tap(find.text('Skip'));
      await tester.pump();
    }

    expect(find.text('Device check result'), findsOneWidget);
    await tester.tap(find.text('Copy'));
    await tester.pump();
    expect(copied, contains('"card": "DEVICE-1"'));
  });

  testWidgets('a question step records the selected answer', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DeviceCheckScreen(cameraEnabled: false)));
    await tester.tap(find.text('Skip'));
    await tester.pump();
    await tester.tap(find.text('Skip'));
    await tester.pump();
    await tester.tap(find.text('Start'));
    await tester.pump(deviceCheckMeasurementDuration);
    await tester.pump();
    await tester.tap(find.text('Yes'));
    await tester.pump();

    for (int index = 0; index < 4; index++) {
      await tester.tap(find.text('Skip'));
      await tester.pump();
    }
    expect(find.textContaining('"answer": true'), findsOneWidget);
  });
}
