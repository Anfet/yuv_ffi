import 'dart:async';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_ffi_example/camera_screen.dart';
import 'package:yuv_ffi_example/widgets/impl/yuv_camera_preview_io.dart';

import 'support/fake_camera.dart';

void main() {
  late FakeCameraPlatform platform;

  setUp(() {
    platform = FakeCameraPlatform();
    CameraPlatform.instance = platform;
  });

  Future<CameraController> initializedController(WidgetTester tester) async {
    final cameras = await availableCameras();
    final controller = CameraController(cameras.first, ResolutionPreset.medium, enableAudio: false);
    await controller.initialize();
    return controller;
  }

  group('desktop preview', () {
    late List<String> events;
    late int presented;

    setUp(() {
      events = [];
      presented = 0;
    });

    Future<void> pumpPreview(WidgetTester tester, CameraController? controller, {YuvImage Function(YuvImage image)? transform}) {
      return tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: controller == null
                ? const SizedBox()
                : buildYuvCameraPreview(
                    cameraController: controller,
                    transform: transform,
                    onFramePresented: () {
                      presented++;
                      events.add('presented');
                    },
                  ),
          ),
        ),
      );
    }

    /// Delivers [frame] and lets the preview handle it synchronously; returns
    /// with the decode still running.
    Future<void> deliver(WidgetTester tester, CameraController controller, CameraImageData frame) async {
      platform.emit(controller.cameraId, frame);
      await tester.pump(Duration.zero);
    }

    /// Delivers [frame], waits for its decode and draws it.
    Future<void> deliverAndDraw(WidgetTester tester, CameraController controller, CameraImageData frame) async {
      final before = presented;
      await deliver(tester, controller, frame);
      await pumpUntil(tester, () => presented > before, reason: 'the frame to be drawn');
    }

    testWidgets('streams through CameraPlatform directly and shows the frame transform returned, without transform the camera frame', (tester) async {
      final controller = await initializedController(tester);
      await pumpPreview(
        tester,
        controller,
        transform: (image) {
          events.add('transform:${shadeOfYuv(image)}');
          return yuvFrame(255 - shadeOfYuv(image));
        },
      );
      await tester.pump();
      expect(platform.listens, [controller.cameraId], reason: 'the preview subscribes to the camera_desktop stream itself');
      expect(controller.value.isStreamingImages, isFalse, reason: 'CameraController.startImageStream asserts on desktop and is not used');

      await deliverAndDraw(tester, controller, cameraFrame(40, rowPadding: 8));
      expect(events, ['transform:40', 'presented'], reason: 'frame -> transform -> shown');
      expect(await drawnShade(tester), 215, reason: 'the preview shows what transform returned, not the camera frame');

      await pumpPreview(tester, null);
      await tester.pump();

      final second = await initializedController(tester);
      events.clear();
      await pumpPreview(tester, second);
      await tester.pump();
      await deliverAndDraw(tester, second, cameraFrame(70));
      expect(events, ['presented']);
      expect(await drawnShade(tester), 70, reason: 'without transform the camera frame itself is shown');
    });

    testWidgets('drops frames before transform while the previous one is still decoding or waiting to be drawn', (tester) async {
      final controller = await initializedController(tester);
      final transformed = <int>[];
      await pumpPreview(
        tester,
        controller,
        transform: (image) {
          transformed.add(shadeOfYuv(image));
          return image;
        },
      );
      await tester.pump();

      await deliver(tester, controller, cameraFrame(10));
      await deliver(tester, controller, cameraFrame(11));
      await deliver(tester, controller, cameraFrame(12));
      expect(transformed, [10], reason: 'frames arriving while one is decoding are dropped before transform');

      // Real time for the decode to finish, with no frame drawn in between.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await deliver(tester, controller, cameraFrame(13));
      expect(transformed, [10], reason: 'a frame stays in flight until it is drawn');

      await pumpUntil(tester, () => presented == 1, reason: 'the first frame to be drawn');
      expect(await drawnShade(tester), 10);
      await deliverAndDraw(tester, controller, cameraFrame(14));
      expect(transformed, [10, 14]);
      expect(presented, 2);
      expect(await drawnShade(tester), 14);

      final cache = PaintingBinding.instance.imageCache;
      expect(cache.pendingImageCount + cache.currentSize + cache.liveImageCount, 0, reason: 'preview frames must not pile up in ImageCache');
    });

    testWidgets('switching the camera stops the old stream, drops its frame in flight and shows only frames of the new one', (tester) async {
      final first = await initializedController(tester);
      final second = await initializedController(tester);
      final transformed = <int>[];
      YuvImage transform(YuvImage image) {
        transformed.add(shadeOfYuv(image));
        return image;
      }

      await pumpPreview(tester, first, transform: transform);
      await tester.pump();
      await deliverAndDraw(tester, first, cameraFrame(20));
      expect(await drawnShade(tester), 20);

      // A frame of the first camera is decoding when the camera is switched.
      await deliver(tester, first, cameraFrame(21));
      platform.emit(first.cameraId, cameraFrame(22));
      await pumpPreview(tester, second, transform: transform);
      expect(platform.cancels, [first.cameraId], reason: 'the old stream is stopped on switch');
      expect(drawnImage(tester), isNull, reason: 'the old camera frame is not shown after switching');

      await settleDecodes(tester);
      await tester.pump();
      expect(drawnImage(tester), isNull, reason: 'the frame decoded for the stopped stream must not be shown');
      expect(transformed, [20, 21], reason: 'the frame queued on the stopped stream never reaches transform');
      expect(presented, 1);

      expect(platform.listens, [first.cameraId, second.cameraId]);
      await deliverAndDraw(tester, second, cameraFrame(30));
      expect(await drawnShade(tester), 30);
      expect(presented, 2);
    });

    testWidgets('a restart on the same camera waits for the previous native stop and shows no frame of the stopped stream', (tester) async {
      final first = await initializedController(tester);
      final second = await initializedController(tester);
      await pumpPreview(tester, first);
      await tester.pump();
      await deliverAndDraw(tester, first, cameraFrame(40));

      final gate = platform.stopGate = Completer<void>();
      await pumpPreview(tester, second);
      await tester.pump();
      // Back to the first camera while its native stop is still running.
      await pumpPreview(tester, first);
      await tester.pump();
      expect(platform.listens, [first.cameraId], reason: 'the restart must wait for the pending stops');

      gate.complete();
      await tester.pump();
      await tester.pump();
      expect(platform.listens, [first.cameraId, first.cameraId], reason: 'only the latest requested stream is started');
      expect(platform.overlappingStarts, isEmpty, reason: 'two streams of one camera must never overlap');
      expect(drawnImage(tester), isNull);

      await deliverAndDraw(tester, first, cameraFrame(41));
      expect(await drawnShade(tester), 41);
    });

    testWidgets('after dispose the stream is stopped and neither a frame in flight nor a late one updates the preview', (tester) async {
      final controller = await initializedController(tester);
      var transformCalls = 0;
      await pumpPreview(
        tester,
        controller,
        transform: (image) {
          transformCalls++;
          return image;
        },
      );
      await tester.pump();

      await deliver(tester, controller, cameraFrame(50));
      expect(transformCalls, 1);
      await pumpPreview(tester, null);
      expect(platform.cancels, [controller.cameraId]);
      expect(platform.isStreaming(controller.cameraId), isFalse);

      platform.emit(controller.cameraId, cameraFrame(51));
      await settleDecodes(tester);
      await tester.pump();
      expect(transformCalls, 1);
      expect(presented, 0, reason: 'the frame decoding at dispose is never reported as drawn');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a preview closed while waiting for the previous stop never subscribes', (tester) async {
      final first = await initializedController(tester);
      final second = await initializedController(tester);
      await pumpPreview(tester, first);
      await tester.pump();

      final gate = platform.stopGate = Completer<void>();
      await pumpPreview(tester, second);
      await pumpPreview(tester, null);
      gate.complete();
      await tester.pump();
      await tester.pump();

      expect(platform.listens, [first.cameraId], reason: 'the start waiting for the stop belongs to a disposed preview');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a stream error is shown for the current stream only and stops that stream', (tester) async {
      final first = await initializedController(tester);
      final transformed = <int>[];
      await pumpPreview(
        tester,
        first,
        transform: (image) {
          transformed.add(shadeOfYuv(image));
          return image;
        },
      );
      await tester.pump();
      await deliverAndDraw(tester, first, cameraFrame(55));
      final shown = drawnImage(tester)!;

      platform.emitError(first.cameraId, StateError('camera unplugged'));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('camera unplugged'), findsOneWidget);
      expect(platform.cancels, [first.cameraId], reason: 'the failed stream is stopped, not left running behind the error text');
      expect(platform.isStreaming(first.cameraId), isFalse);
      expect(shown.debugDisposed, isTrue, reason: 'the last frame of the failed stream is released');
      platform.emit(first.cameraId, cameraFrame(56));
      await tester.pump();
      expect(transformed, [55]);

      final second = await initializedController(tester);
      await pumpPreview(tester, second);
      await tester.pump();
      expect(find.textContaining('camera unplugged'), findsNothing, reason: 'the error of the replaced stream is cleared');
      await deliverAndDraw(tester, second, cameraFrame(60));
      expect(await drawnShade(tester), 60);
    });
  });

  group('CameraScreen on desktop', () {
    Future<Future<Object?>> openCameraScreen(WidgetTester tester) async {
      Future<Object?>? popped;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => popped = Navigator.of(context).push<Object?>(MaterialPageRoute(builder: (_) => const CameraScreen())),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      return popped!;
    }

    testWidgets('capture returns the frame shown after transform and owns it independently of the next camera frames', (tester) async {
      final popped = await openCameraScreen(tester);
      const cameraId = 1;
      expect(platform.listens, [cameraId], reason: 'the screen opens the desktop camera through CameraController and camera_desktop');

      platform.emit(cameraId, cameraFrame(80));
      await tester.pump(Duration.zero);
      await pumpUntil(tester, () => drawnImage(tester) != null, reason: 'the first frame');
      expect(await drawnShade(tester), 80);

      await tester.tap(find.byTooltip('Capture frame'));
      await tester.pump();

      platform.emit(cameraId, cameraFrame(90));
      await tester.pump(Duration.zero);
      await settleDecodes(tester);
      await tester.pump();
      expect(await drawnShade(tester), 90, reason: 'the frame handed to capture is the one shown');

      platform.emit(cameraId, cameraFrame(100));
      await tester.pump(Duration.zero);
      await settleDecodes(tester);
      await tester.pump();
      expect(await drawnShade(tester), 100, reason: 'the preview keeps running while takePicture waits');

      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      final captured = await popped;
      expect(captured, isA<YuvImage>());
      expect(shadeOfYuv(captured! as YuvImage), 90, reason: 'later camera frames must not reach the captured frame');

      expect(platform.cancels, [cameraId], reason: 'closing the screen stops the stream');
      expect(platform.disposedCameras, [cameraId], reason: 'and releases the controller');
    });

    testWidgets('closing the screen while the camera initializes releases the controller without an update after dispose', (tester) async {
      final gate = platform.initializeGate = Completer<void>();
      await openCameraScreen(tester);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.byType(CameraScreen), findsNothing);

      gate.complete();
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'no setState after dispose');
      expect(platform.disposedCameras, [1]);
      expect(platform.listens, isEmpty, reason: 'a closed screen never starts the stream');
    });

    testWidgets('closing the screen while cameras are looked up opens no camera', (tester) async {
      final gate = platform.lookupGate = Completer<void>();
      await openCameraScreen(tester);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      gate.complete();
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(platform.createdCameras, 0, reason: 'a controller created after dispose would never be released');
      expect(platform.listens, isEmpty);
    });
  });
}
