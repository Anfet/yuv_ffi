import 'dart:async';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_ffi_example/camera_screen.dart';
import 'package:yuv_ffi_example/widgets/impl/yuv_camera_preview_io.dart';
import 'package:yuv_ffi_example/widgets/yuv_camera_preview.dart';

import 'support/fake_camera.dart';

// The mobile and desktop previews are picked by platform; the debug override
// lets one VM host run both. Android shares the mobile path but rotates every
// frame through the native backend, which the example test process does not
// load, so iOS stands in for it.
final _allPlatforms = TargetPlatformVariant({TargetPlatform.iOS, TargetPlatform.windows, TargetPlatform.macOS, TargetPlatform.linux});
final _mobile = TargetPlatformVariant.only(TargetPlatform.iOS);
final _mobileAndDesktop = TargetPlatformVariant({TargetPlatform.iOS, TargetPlatform.windows});

void main() {
  late FakeCameraPlatform platform;

  setUp(() {
    platform = FakeCameraPlatform();
    CameraPlatform.instance = platform;
  });

  Future<CameraController> initializedController() async {
    final cameras = await availableCameras();
    final controller = CameraController(cameras.first, ResolutionPreset.medium, enableAudio: false);
    await controller.initialize();
    return controller;
  }

  late List<int> transformed;
  late int presented;
  late int streamStops;

  setUp(() {
    transformed = [];
    presented = 0;
    streamStops = 0;
  });

  YuvImage recordingTransform(YuvImage image) {
    transformed.add(shadeOfYuv(image));
    return image;
  }

  Future<void> pumpPreview(WidgetTester tester, CameraController? controller, {YuvImage Function(YuvImage image)? transform}) {
    return tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: controller == null
              ? const SizedBox()
              : buildYuvCameraPreview(
                  cameraController: controller,
                  transform: transform,
                  onFramePresented: () => presented++,
                  onStreamStopped: () => streamStops++,
                ),
        ),
      ),
    );
  }

  Future<void> deliver(WidgetTester tester, CameraController controller, CameraImageData frame) async {
    platform.emit(controller.cameraId, frame);
    await tester.pump(Duration.zero);
  }

  Future<void> deliverAndDraw(WidgetTester tester, CameraController controller, CameraImageData frame) async {
    final before = presented;
    await deliver(tester, controller, frame);
    await pumpUntil(tester, () => presented > before, reason: 'the frame to be drawn');
  }

  group('transform contract', () {
    Future<void> pumpPublicPreview(WidgetTester tester, CameraController controller, {YuvImage Function(YuvImage image)? transform}) {
      return tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: YuvCameraPreview(
              cameraController: controller,
              transform: transform,
              onFramePresented: () => presented++,
              onStreamStopped: () => streamStops++,
            ),
          ),
        ),
      );
    }

    Future<void> deliverAndSettle(WidgetTester tester, CameraController controller, CameraImageData frame) async {
      await deliver(tester, controller, frame);
      await settleDecodes(tester);
    }

    testWidgets('the preview shows the frame transform returned and, without transform, the camera frame', (tester) async {
      final controller = await initializedController();
      YuvImage? returned;
      await pumpPublicPreview(
        tester,
        controller,
        transform: (image) {
          transformed.add(shadeOfYuv(image));
          return returned = yuvFrame(255 - shadeOfYuv(image));
        },
      );
      await tester.pump();

      await deliverAndSettle(tester, controller, cameraFrame(40, rowPadding: 8));
      expect(transformed, [40]);
      expect(await drawnShade(tester), 215, reason: 'the preview shows what transform returned, not the camera frame');
      expect(shadeOfYuv(returned!), 215, reason: 'the frame returned for capture is the one shown');

      await tester.pumpWidget(const SizedBox());
      final second = await initializedController();
      await pumpPublicPreview(tester, second);
      await tester.pump();
      await deliverAndSettle(tester, second, cameraFrame(70));
      expect(await drawnShade(tester), 70, reason: 'without transform the camera frame itself is shown');
    }, variant: _allPlatforms);

    testWidgets('a transform that throws drops only its frame, is reported, and the stream keeps running', (tester) async {
      final controller = await initializedController();
      await pumpPublicPreview(
        tester,
        controller,
        transform: (image) {
          final shade = shadeOfYuv(image);
          transformed.add(shade);
          if (shade == 20) {
            throw StateError('transform failed');
          }
          return image;
        },
      );
      await tester.pump();

      await deliverAndSettle(tester, controller, cameraFrame(20));
      expect(tester.takeException(), isStateError, reason: 'the error is reported, not swallowed');
      expect(drawnImage(tester), isNull, reason: 'the failed frame is not shown');
      expect(find.textContaining('error'), findsNothing, reason: 'a transform error is not a camera error');

      await deliverAndSettle(tester, controller, cameraFrame(21));
      expect(transformed, [20, 21], reason: 'the presenter was left free for the next frame');
      expect(await drawnShade(tester), 21);
      expect(platform.cancels, isEmpty, reason: 'the stream keeps running');
    }, variant: _allPlatforms);

    testWidgets('a frame passed to transform whose stream is replaced before the draw is never reported as presented', (tester) async {
      final first = await initializedController();
      final second = await initializedController();
      await pumpPublicPreview(tester, first, transform: recordingTransform);
      await tester.pump();
      await deliverAndDraw(tester, first, cameraFrame(20));
      expect(presented, 1);

      // Frame 21 went through transform and is decoding when the stream is
      // replaced.
      await deliver(tester, first, cameraFrame(21));
      expect(transformed, [20, 21]);
      await pumpPublicPreview(tester, second, transform: recordingTransform);
      expect(streamStops, 1, reason: 'the owner learns that the frame in flight is dropped');

      await settleDecodes(tester);
      expect(presented, 1, reason: 'frame 21 was never drawn, so it must not be reported as presented');
      expect(drawnImage(tester), isNull);

      await deliverAndDraw(tester, second, cameraFrame(30));
      expect(transformed, [20, 21, 30]);
      expect(presented, 2, reason: 'the next drawn frame answers the latest transform call');
      expect(await drawnShade(tester), 30);
    }, variant: _mobileAndDesktop);
  });

  group('mobile preview', () {
    testWidgets('switching the controller stops the old stream and shows no frame of it', (tester) async {
      final first = await initializedController();
      final second = await initializedController();
      await pumpPreview(tester, first, transform: recordingTransform);
      await tester.pump();
      expect(platform.isStreaming(first.cameraId), isTrue);
      await deliverAndDraw(tester, first, cameraFrame(20));
      final shown = drawnImage(tester)!;

      // A frame of the first camera is decoding and another one is queued when
      // the controller is switched.
      await deliver(tester, first, cameraFrame(21));
      platform.emit(first.cameraId, cameraFrame(22));
      await pumpPreview(tester, second, transform: recordingTransform);
      expect(platform.cancels, [first.cameraId]);
      expect(platform.isStreaming(first.cameraId), isFalse);
      expect(streamStops, 1);
      expect(drawnImage(tester), isNull);
      expect(shown.debugDisposed, isTrue, reason: 'the frame of the replaced stream is released');

      await settleDecodes(tester);
      expect(drawnImage(tester), isNull, reason: 'the frame decoded for the stopped stream must not be shown');
      expect(transformed, [20, 21], reason: 'the queued frame of the stopped stream never reaches transform');
      expect(presented, 1);

      await deliverAndDraw(tester, second, cameraFrame(30));
      expect(await drawnShade(tester), 30);
      expect(platform.overlappingStarts, isEmpty);
    }, variant: _mobile);

    testWidgets('a restart on the same controller waits for the previous stop instead of overlapping it', (tester) async {
      final first = await initializedController();
      final second = await initializedController();
      await pumpPreview(tester, first);
      await tester.pump();
      await deliverAndDraw(tester, first, cameraFrame(40));

      final gate = platform.stopGate = Completer<void>();
      await pumpPreview(tester, second);
      await tester.pump();
      await pumpPreview(tester, first);
      await tester.pump();
      expect(platform.listens, [first.cameraId], reason: 'the restart must wait for the pending stop');

      gate.complete();
      await tester.pump();
      await tester.pump();
      expect(platform.listens, [first.cameraId, first.cameraId], reason: 'only the latest requested stream is started');
      expect(platform.overlappingStarts, isEmpty, reason: 'two streams of one camera must never overlap');
      expect(platform.isStreaming(first.cameraId), isTrue);
      expect(platform.isStreaming(second.cameraId), isFalse);

      await deliverAndDraw(tester, first, cameraFrame(41));
      expect(await drawnShade(tester), 41);
    }, variant: _mobile);

    testWidgets('dispose with a frame in flight stops the stream, releases the frame and ignores late frames', (tester) async {
      final controller = await initializedController();
      await pumpPreview(tester, controller, transform: recordingTransform);
      await tester.pump();
      await deliverAndDraw(tester, controller, cameraFrame(50));
      final shown = drawnImage(tester)!;

      await deliver(tester, controller, cameraFrame(51));
      await pumpPreview(tester, null);
      expect(platform.cancels, [controller.cameraId]);
      expect(platform.isStreaming(controller.cameraId), isFalse);
      expect(streamStops, 0, reason: 'dispose is not reported as a stopped stream');
      expect(shown.debugDisposed, isTrue);

      platform.emit(controller.cameraId, cameraFrame(52));
      await settleDecodes(tester);
      expect(transformed, [50, 51]);
      expect(presented, 1, reason: 'the frame decoding at dispose is never reported as drawn');
      expect(tester.takeException(), isNull);
    }, variant: _mobile);

    testWidgets('a preview closed while waiting for the previous stop never starts a stream', (tester) async {
      final first = await initializedController();
      final second = await initializedController();
      await pumpPreview(tester, first);
      await tester.pump();

      final gate = platform.stopGate = Completer<void>();
      await pumpPreview(tester, second);
      await pumpPreview(tester, null);
      gate.complete();
      await tester.pump();
      await tester.pump();

      expect(platform.listens, [first.cameraId]);
      expect(platform.isStreaming(second.cameraId), isFalse, reason: 'a stream started for a disposed preview would never be stopped');
      expect(tester.takeException(), isNull);
    }, variant: _mobile);

    testWidgets('an uninitialized controller is shown as an error, and the preview recovers on the next controller', (tester) async {
      final first = await initializedController();
      await pumpPreview(tester, first);
      await tester.pump();

      final cameras = await availableCameras();
      final uninitialized = CameraController(cameras.first, ResolutionPreset.medium, enableAudio: false);
      await pumpPreview(tester, uninitialized);
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'the error is shown, not thrown from an unawaited start');
      expect(find.textContaining('CameraController should be initialized'), findsOneWidget);
      expect(platform.cancels, [first.cameraId], reason: 'the old stream is stopped even though the new controller cannot start');

      final second = await initializedController();
      await pumpPreview(tester, second);
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('CameraController should be initialized'), findsNothing);
      await deliverAndDraw(tester, second, cameraFrame(60));
      expect(await drawnShade(tester), 60);
    }, variant: _mobile);

    testWidgets('a camera that fails to start streaming is shown as an error, and a later controller streams normally', (tester) async {
      final first = await initializedController();
      platform.failNextStreamStart = PlatformException(code: 'CameraAccessDenied', message: 'camera busy');
      await pumpPreview(tester, first);
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('camera busy'), findsOneWidget);
      expect(platform.isStreaming(first.cameraId), isFalse);
      expect(streamStops, 1, reason: 'a failed start is reported like a stopped stream');

      final second = await initializedController();
      await pumpPreview(tester, second);
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('camera busy'), findsNothing);
      expect(platform.cancels, isEmpty, reason: 'a stream that never started is not stopped');
      await deliverAndDraw(tester, second, cameraFrame(61));
      expect(await drawnShade(tester), 61);
    }, variant: _mobile);

    testWidgets('a camera error after the stream started stops the stream, releases the frame and is shown', (tester) async {
      final controller = await initializedController();
      await pumpPreview(tester, controller, transform: recordingTransform);
      await tester.pump();
      await deliverAndDraw(tester, controller, cameraFrame(62));
      final shown = drawnImage(tester)!;

      await deliver(tester, controller, cameraFrame(63));
      platform.emitError(controller.cameraId, PlatformException(code: 'CameraDisconnected', message: 'camera unplugged'));
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'the error is handled, not left to the zone');
      expect(platform.cancels, [controller.cameraId], reason: 'the stream is stopped, not left running behind the error');
      expect(platform.isStreaming(controller.cameraId), isFalse);
      expect(streamStops, 1);
      expect(find.textContaining('camera unplugged'), findsOneWidget);
      expect(shown.debugDisposed, isTrue);

      platform.emit(controller.cameraId, cameraFrame(64));
      await settleDecodes(tester);
      expect(transformed, [62, 63], reason: 'no frame reaches transform after the error');
      expect(presented, 1, reason: 'the frame decoding at the error is never reported as drawn');
    }, variant: _mobile);
  });

  group('CameraScreen', () {
    late Future<Object?>? popped;

    Future<void> openCameraScreen(WidgetTester tester) async {
      popped = null;
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
    }

    Future<void> deliverToScreen(WidgetTester tester, int cameraId, int shade) async {
      platform.emit(cameraId, cameraFrame(shade));
      await tester.pump(Duration.zero);
      await pumpUntil(tester, () => drawnImage(tester) != null, reason: 'the frame to be drawn');
      await settleDecodes(tester);
    }

    testWidgets('reopening after close starts a new stream that shows no frame of the old one and releases the old resources', (tester) async {
      await openCameraScreen(tester);
      await deliverToScreen(tester, 1, 80);
      expect(await drawnShade(tester), 80);
      final firstShown = drawnImage(tester)!;

      // The previews log a failed stop instead of throwing it; a stop that
      // runs only after CameraScreen disposed the controller shows up here.
      final logs = <String>[];
      final previousDebugPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
      try {
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();
      } finally {
        debugPrint = previousDebugPrint;
      }
      expect(platform.cancels, [1], reason: 'closing stops the stream');
      expect(logs.where((line) => line.contains('stop error')), isEmpty, reason: 'the stream is stopped before the controller is disposed');
      expect(platform.disposedCameras, [1], reason: 'and releases the controller');
      expect(firstShown.debugDisposed, isTrue, reason: 'and the last shown frame');

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(platform.listens, [1, 2]);
      expect(drawnImage(tester), isNull, reason: 'the reopened screen starts empty, not with the old frame');
      platform.emit(1, cameraFrame(81));
      await deliverToScreen(tester, 2, 90);
      expect(await drawnShade(tester), 90);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(platform.disposedCameras, [1, 2]);
      final cache = PaintingBinding.instance.imageCache;
      expect(cache.pendingImageCount + cache.currentSize + cache.liveImageCount, 0);
    }, variant: _mobileAndDesktop);

    testWidgets('a second capture tap before the frame arrives joins the pending capture instead of orphaning it', (tester) async {
      await openCameraScreen(tester);
      // _CameraScreenState is private to the example, so takePicture is reached
      // dynamically rather than widened for the test.
      final dynamic screen = tester.state(find.byType(CameraScreen));
      var firstDone = false;
      var secondDone = false;
      (screen.takePicture() as Future<void>).then((_) => firstDone = true);
      (screen.takePicture() as Future<void>).then((_) => secondDone = true);
      await tester.pump();

      await deliverToScreen(tester, 1, 70);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(firstDone, isTrue, reason: 'the first capture must complete, not wait forever');
      expect(secondDone, isTrue);
      final captured = await popped;
      expect(captured, isA<YuvImage>());
      expect(shadeOfYuv(captured! as YuvImage), 70);
      expect(find.text('open'), findsOneWidget, reason: 'only the camera screen was popped');
    }, variant: _mobileAndDesktop);

    testWidgets('closing the screen while a capture waits for a frame completes the capture without a result', (tester) async {
      await openCameraScreen(tester);
      final dynamic screen = tester.state(find.byType(CameraScreen));
      var captureDone = false;
      (screen.takePicture() as Future<void>).then((_) => captureDone = true);
      await tester.pump();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(captureDone, isTrue, reason: 'a capture pending at close must not wait forever');
      expect(await popped, isNull);
      expect(find.text('open'), findsOneWidget, reason: 'the pending capture must not pop the route below');
      expect(platform.cancels, [1]);
      expect(tester.takeException(), isNull);
    }, variant: _mobileAndDesktop);

    testWidgets('a capture completes only once its frame is drawn, with the frame that was drawn', (tester) async {
      await openCameraScreen(tester);
      final dynamic screen = tester.state(find.byType(CameraScreen));
      var captureDone = false;
      (screen.takePicture() as Future<void>).then((_) => captureDone = true);
      await tester.pump();

      // Frame 72 has passed transform, but its decode needs real time, which
      // fake-clock pumps do not give: it is not on screen yet.
      platform.emit(1, cameraFrame(72));
      await tester.pump(Duration.zero);
      await tester.pump(const Duration(milliseconds: 600));
      expect(drawnImage(tester), isNull);
      expect(captureDone, isFalse, reason: 'a frame that is not drawn yet must not be captured');

      await pumpUntil(tester, () => drawnImage(tester) != null, reason: 'the frame to be drawn');
      await settleDecodes(tester);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(captureDone, isTrue);
      final captured = await popped;
      expect(shadeOfYuv(captured! as YuvImage), 72);
    }, variant: _mobileAndDesktop);

    testWidgets('a stream stopped between transform and draw ends the capture without a frame', (tester) async {
      await openCameraScreen(tester);
      final dynamic screen = tester.state(find.byType(CameraScreen));
      var captureDone = false;
      (screen.takePicture() as Future<void>).then((_) => captureDone = true);
      var poppedDone = false;
      popped!.then((_) => poppedDone = true);
      await tester.pump();

      // Frame 73 has passed transform and is decoding when a camera error
      // stops the stream; its decode then finishes for a stopped stream.
      platform.emit(1, cameraFrame(73));
      await tester.pump(Duration.zero);
      platform.emitError(1, PlatformException(code: 'CameraDisconnected', message: 'camera unplugged'));
      await tester.pump();
      await settleDecodes(tester);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(platform.cancels, [1], reason: 'the camera error stopped the stream');
      expect(drawnImage(tester), isNull, reason: 'frame 73 was never shown');
      expect(captureDone, isTrue, reason: 'the capture pending at the stop must end, not wait for a frame that will not come');
      expect(poppedDone, isFalse, reason: 'a frame that was never shown must not be returned');
      expect(find.byType(CameraScreen), findsOneWidget);
    }, variant: _mobileAndDesktop);
  });
}
