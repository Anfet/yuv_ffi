import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_ffi_example/camera_screen.dart';
import 'package:yuv_ffi_example/main.dart' as demo;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('demo captures a camera frame, detects faces, crops and applies an effect', (tester) async {
    await YuvFfi.initialize();
    await tester.pumpWidget(const demo.MyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Take photo'));
    await _pumpUntil(tester, find.byType(CameraScreen), 'camera screen should open');
    expect(find.byType(CameraScreen), findsOneWidget);

    final captureButton = find.byTooltip('Capture frame');
    await _pumpUntil(tester, captureButton, 'camera preview should become ready');
    expect(captureButton, findsOneWidget, reason: 'camera preview should become ready');

    await tester.tap(captureButton);
    await _pumpUntilGone(tester, find.byType(CameraScreen, skipOffstage: false), 'captured frame should return to the demo screen');
    expect(find.byType(CameraScreen), findsNothing, reason: 'camera frame should return to the demo screen');

    final imageWidgetFinder = find.byType(YuvImageWidget);
    expect(imageWidgetFinder, findsOneWidget);
    final image = tester.widget<YuvImageWidget>(imageWidgetFinder).image;

    // Exercise the same awaited detector path used by the Face detection button.
    await (tester.state(find.byType(demo.MyApp)) as dynamic).doFaceDetection();
    expect(tester.takeException(), isNull);

    final originalWidth = image.width;
    final originalHeight = image.height;
    await tester.tap(find.byTooltip('crop image'));
    await tester.pump();
    expect(image.width, lessThan(originalWidth));
    expect(image.height, lessThan(originalHeight));

    final beforeEffect = image.toBytes();
    await tester.tap(find.byTooltip('Negate'));
    await tester.pump();
    expect(image.toBytes(), isNot(orderedEquals(beforeEffect)));
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(minutes: 3)));
}

Future<void> _pumpUntil(WidgetTester tester, Finder finder, String reason) async {
  for (var attempt = 0; attempt < 80; attempt++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 250));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
  }
  fail('Timed out: $reason');
}

Future<void> _pumpUntilGone(WidgetTester tester, Finder finder, String reason) async {
  for (var attempt = 0; attempt < 80; attempt++) {
    if (finder.evaluate().isEmpty) return;
    await tester.pump(const Duration(milliseconds: 250));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
  }
  fail('Timed out: $reason');
}
