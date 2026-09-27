import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_ffi_example/camera_screen.dart';
import 'package:yuv_ffi_example/widgets/impl/yuv_camera_preview_io.dart';

const int _width = 8;
const int _height = 6;

/// A grey BGRA frame the way camera_desktop delivers it: one plane, every
/// channel equal to [shade], so the decoded pixels tell which frame is shown.
/// [rowPadding] extra bytes per row model a native stride above `width * 4`.
CameraImageData _cameraFrame(int shade, {int rowPadding = 0}) {
  final bytesPerRow = _width * 4 + rowPadding;
  final bytes = Uint8List(bytesPerRow * _height);
  for (int row = 0; row < _height; row++) {
    for (int col = 0; col < _width; col++) {
      final offset = row * bytesPerRow + col * 4;
      bytes.setRange(offset, offset + 4, [shade, shade, shade, 255]);
    }
  }
  return CameraImageData(
    format: const CameraImageFormat(ImageFormatGroup.bgra8888, raw: 'BGRA'),
    width: _width,
    height: _height,
    planes: [CameraImagePlane(bytes: bytes, bytesPerRow: bytesPerRow, bytesPerPixel: 4, width: _width, height: _height)],
  );
}

YuvImage _yuvFrame(int shade) {
  final frame = YuvImage.bgra(_width, _height);
  frame.yPlane.assignFrom(
    Uint8List.fromList([
      for (int i = 0; i < _width * _height; i++) ...[shade, shade, shade, 255],
    ]),
  );
  frame.markDirty();
  return frame;
}

int _shadeOfYuv(YuvImage image) => image.toBgraBytes()[0];

/// Stands in for camera_desktop: one single-subscription frame stream per
/// `onStreamedFrameAvailable` call, whose cancel is the native stop.
///
/// Like camera_desktop it keeps one active stream per camera; a second
/// listen on a camera whose previous stream is still stopping is recorded in
/// [overlappingStarts].
class _FakeDesktopCamera extends CameraPlatform {
  final _events = StreamController<CameraEvent>.broadcast();
  final Map<int, StreamController<CameraImageData>> _activeStreams = {};
  final Set<int> _stopping = {};
  int _nextCameraId = 1;

  final List<int> disposedCameras = [];
  final List<int> listens = [];
  final List<int> cancels = [];
  final List<int> overlappingStarts = [];

  /// When set, the native stop of a cancelled stream waits for it.
  Completer<void>? stopGate;

  /// When set, `initializeCamera` waits for it.
  Completer<void>? initializeGate;

  bool isStreaming(int cameraId) => _activeStreams.containsKey(cameraId);

  /// Delivers [frame] to the stream currently listened to on [cameraId], if any.
  void emit(int cameraId, CameraImageData frame) => _activeStreams[cameraId]?.add(frame);

  void emitError(int cameraId, Object error) => _activeStreams[cameraId]?.addError(error);

  @override
  Future<List<CameraDescription>> availableCameras() async => const [
    CameraDescription(name: 'fake-desktop-camera', lensDirection: CameraLensDirection.front, sensorOrientation: 0),
  ];

  @override
  Future<int> createCameraWithSettings(CameraDescription cameraDescription, MediaSettings? mediaSettings) async => _nextCameraId++;

  @override
  Future<void> initializeCamera(int cameraId, {ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown}) async {
    await initializeGate?.future;
    _events.add(CameraInitializedEvent(cameraId, _width.toDouble(), _height.toDouble(), ExposureMode.auto, false, FocusMode.auto, false));
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      _events.stream.where((event) => event.cameraId == cameraId).cast<CameraInitializedEvent>();

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() => const Stream.empty();

  @override
  Stream<CameraImageData> onStreamedFrameAvailable(int cameraId, {CameraImageStreamOptions? options}) {
    late final StreamController<CameraImageData> controller;
    controller = StreamController<CameraImageData>(
      onListen: () {
        listens.add(cameraId);
        if (_activeStreams.containsKey(cameraId) || _stopping.contains(cameraId)) {
          overlappingStarts.add(cameraId);
        }
        _activeStreams[cameraId] = controller;
      },
      onCancel: () async {
        cancels.add(cameraId);
        if (identical(_activeStreams[cameraId], controller)) {
          _activeStreams.remove(cameraId);
        }
        _stopping.add(cameraId);
        await stopGate?.future;
        _stopping.remove(cameraId);
      },
    );
    return controller.stream;
  }

  @override
  Future<void> dispose(int cameraId) async {
    disposedCameras.add(cameraId);
    await _activeStreams.remove(cameraId)?.close();
  }
}

ui.Image? _drawnImage(WidgetTester tester) {
  final raw = find.byType(RawImage);
  return raw.evaluate().isEmpty ? null : tester.widget<RawImage>(raw).image;
}

Future<int?> _drawnShade(WidgetTester tester) async {
  final image = _drawnImage(tester);
  if (image == null) {
    return null;
  }
  final data = await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.rawRgba));
  return data!.getUint8(0);
}

/// Decode callbacks only arrive outside the test's fake clock: each round
/// gives the engine real time, then runs the fake microtasks and draws a frame
/// if a decoded one is waiting.
Future<void> _pumpUntil(WidgetTester tester, bool Function() condition, {String reason = 'condition'}) async {
  for (int i = 0; i < 400 && !condition(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(Duration.zero);
  }
  expect(condition(), isTrue, reason: 'timed out waiting for $reason');
}

/// Gives a decode that may still be running enough real time to finish, then
/// draws whatever it produced.
Future<void> _settleDecodes(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  await tester.pump(Duration.zero);
  await tester.pump();
}

void main() {
  late _FakeDesktopCamera platform;

  setUp(() {
    platform = _FakeDesktopCamera();
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
      await _pumpUntil(tester, () => presented > before, reason: 'the frame to be drawn');
    }

    testWidgets('streams through CameraPlatform directly and shows the frame transform returned, without transform the camera frame', (tester) async {
      final controller = await initializedController(tester);
      await pumpPreview(
        tester,
        controller,
        transform: (image) {
          events.add('transform:${_shadeOfYuv(image)}');
          return _yuvFrame(255 - _shadeOfYuv(image));
        },
      );
      await tester.pump();
      expect(platform.listens, [controller.cameraId], reason: 'the preview subscribes to the camera_desktop stream itself');
      expect(controller.value.isStreamingImages, isFalse, reason: 'CameraController.startImageStream asserts on desktop and is not used');

      await deliverAndDraw(tester, controller, _cameraFrame(40, rowPadding: 8));
      expect(events, ['transform:40', 'presented'], reason: 'frame -> transform -> shown');
      expect(await _drawnShade(tester), 215, reason: 'the preview shows what transform returned, not the camera frame');

      await pumpPreview(tester, null);
      await tester.pump();

      final second = await initializedController(tester);
      events.clear();
      await pumpPreview(tester, second);
      await tester.pump();
      await deliverAndDraw(tester, second, _cameraFrame(70));
      expect(events, ['presented']);
      expect(await _drawnShade(tester), 70, reason: 'without transform the camera frame itself is shown');
    });

    testWidgets('drops frames before transform while the previous one is still decoding or waiting to be drawn', (tester) async {
      final controller = await initializedController(tester);
      final transformed = <int>[];
      await pumpPreview(
        tester,
        controller,
        transform: (image) {
          transformed.add(_shadeOfYuv(image));
          return image;
        },
      );
      await tester.pump();

      await deliver(tester, controller, _cameraFrame(10));
      await deliver(tester, controller, _cameraFrame(11));
      await deliver(tester, controller, _cameraFrame(12));
      expect(transformed, [10], reason: 'frames arriving while one is decoding are dropped before transform');

      // Real time for the decode to finish, with no frame drawn in between.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await deliver(tester, controller, _cameraFrame(13));
      expect(transformed, [10], reason: 'a frame stays in flight until it is drawn');

      await _pumpUntil(tester, () => presented == 1, reason: 'the first frame to be drawn');
      expect(await _drawnShade(tester), 10);
      await deliverAndDraw(tester, controller, _cameraFrame(14));
      expect(transformed, [10, 14]);
      expect(presented, 2);
      expect(await _drawnShade(tester), 14);

      final cache = PaintingBinding.instance.imageCache;
      expect(cache.pendingImageCount + cache.currentSize + cache.liveImageCount, 0, reason: 'preview frames must not pile up in ImageCache');
    });

    testWidgets('switching the camera stops the old stream, drops its frame in flight and shows only frames of the new one', (tester) async {
      final first = await initializedController(tester);
      final second = await initializedController(tester);
      final transformed = <int>[];
      YuvImage transform(YuvImage image) {
        transformed.add(_shadeOfYuv(image));
        return image;
      }

      await pumpPreview(tester, first, transform: transform);
      await tester.pump();
      await deliverAndDraw(tester, first, _cameraFrame(20));
      expect(await _drawnShade(tester), 20);

      // A frame of the first camera is decoding when the camera is switched.
      await deliver(tester, first, _cameraFrame(21));
      platform.emit(first.cameraId, _cameraFrame(22));
      await pumpPreview(tester, second, transform: transform);
      expect(platform.cancels, [first.cameraId], reason: 'the old stream is stopped on switch');
      expect(_drawnImage(tester), isNull, reason: 'the old camera frame is not shown after switching');

      await _settleDecodes(tester);
      await tester.pump();
      expect(_drawnImage(tester), isNull, reason: 'the frame decoded for the stopped stream must not be shown');
      expect(transformed, [20, 21], reason: 'the frame queued on the stopped stream never reaches transform');
      expect(presented, 1);

      expect(platform.listens, [first.cameraId, second.cameraId]);
      await deliverAndDraw(tester, second, _cameraFrame(30));
      expect(await _drawnShade(tester), 30);
      expect(presented, 2);
    });

    testWidgets('a restart on the same camera waits for the previous native stop and shows no frame of the stopped stream', (tester) async {
      final first = await initializedController(tester);
      final second = await initializedController(tester);
      await pumpPreview(tester, first);
      await tester.pump();
      await deliverAndDraw(tester, first, _cameraFrame(40));

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
      expect(_drawnImage(tester), isNull);

      await deliverAndDraw(tester, first, _cameraFrame(41));
      expect(await _drawnShade(tester), 41);
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

      await deliver(tester, controller, _cameraFrame(50));
      expect(transformCalls, 1);
      await pumpPreview(tester, null);
      expect(platform.cancels, [controller.cameraId]);
      expect(platform.isStreaming(controller.cameraId), isFalse);

      platform.emit(controller.cameraId, _cameraFrame(51));
      await _settleDecodes(tester);
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

    testWidgets('a stream error is shown for the current stream only', (tester) async {
      final first = await initializedController(tester);
      await pumpPreview(tester, first);
      await tester.pump();

      platform.emitError(first.cameraId, StateError('camera unplugged'));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('camera unplugged'), findsOneWidget);

      final second = await initializedController(tester);
      await pumpPreview(tester, second);
      await tester.pump();
      expect(find.textContaining('camera unplugged'), findsNothing, reason: 'the error of the replaced stream is cleared');
      await deliverAndDraw(tester, second, _cameraFrame(60));
      expect(await _drawnShade(tester), 60);
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

      platform.emit(cameraId, _cameraFrame(80));
      await tester.pump(Duration.zero);
      await _pumpUntil(tester, () => _drawnImage(tester) != null, reason: 'the first frame');
      expect(await _drawnShade(tester), 80);

      await tester.tap(find.byTooltip('Capture frame'));
      await tester.pump();

      platform.emit(cameraId, _cameraFrame(90));
      await tester.pump(Duration.zero);
      await _settleDecodes(tester);
      await tester.pump();
      expect(await _drawnShade(tester), 90, reason: 'the frame handed to capture is the one shown');

      platform.emit(cameraId, _cameraFrame(100));
      await tester.pump(Duration.zero);
      await _settleDecodes(tester);
      await tester.pump();
      expect(await _drawnShade(tester), 100, reason: 'the preview keeps running while takePicture waits');

      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      final captured = await popped;
      expect(captured, isA<YuvImage>());
      expect(_shadeOfYuv(captured! as YuvImage), 90, reason: 'later camera frames must not reach the captured frame');

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
  });
}
