import 'dart:async';
import 'dart:js_interop';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web/web.dart' as web;
import 'package:yuv_ffi_example/camera/yuv_camera_frame.dart';
import 'package:yuv_ffi_example/camera/yuv_camera_frame_source.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('fake Web camera delivers a non-empty frame and stops cleanly', (tester) async {
    expect(kIsWeb, isTrue);

    final diagnostics = <String, Object?>{'startedAtUtc': DateTime.now().toUtc().toIso8601String(), 'phase': 'starting'};
    binding.reportData = {'ci3CameraSmoke': diagnostics};
    final elapsed = Stopwatch()..start();
    final progressTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      diagnostics['elapsedMs'] = elapsed.elapsedMilliseconds;
    });
    addTearDown(progressTimer.cancel);

    Future<void> recordCameraPermission(String phase) async {
      diagnostics['phase'] = phase;
      try {
        final permission = await web.window.navigator.permissions.query({'name': 'camera'}.jsify() as JSObject).toDart;
        diagnostics['cameraPermission'] = permission.state;
      } catch (error) {
        diagnostics['cameraPermissionError'] = '$error';
      }
    }

    diagnostics['userAgent'] = web.window.navigator.userAgent;
    await recordCameraPermission('querying-camera-permission-before-enumeration');
    diagnostics['phase'] = 'enumerating-cameras';
    final cameraEnumeration = Stopwatch()..start();
    final cameras = await availableCameras();
    diagnostics['availableCamerasElapsedMs'] = cameraEnumeration.elapsedMilliseconds;
    diagnostics['cameras'] = cameras.map((camera) => {'name': camera.name, 'lensDirection': camera.lensDirection.name}).toList();
    expect(cameras, isNotEmpty, reason: 'Chrome fake-media flags must expose a camera');
    final camera = cameras.firstWhere((camera) => camera.lensDirection == CameraLensDirection.front, orElse: () => cameras.first);
    final controller = CameraController(camera, ResolutionPreset.medium, enableAudio: false);
    addTearDown(controller.dispose);
    await recordCameraPermission('before-controller-initialize');
    diagnostics['phase'] = 'controller-initialize-pending';
    final initializeClock = Stopwatch()..start();
    try {
      await controller.initialize();
      diagnostics['initializeElapsedMs'] = initializeClock.elapsedMilliseconds;
      diagnostics['controllerInitialized'] = controller.value.isInitialized;
    } finally {
      initializeClock.stop();
    }
    await recordCameraPermission('after-controller-initialize');

    final frames = <YuvCameraFrame>[];
    final source = YuvCameraFrameSource(controller, onFrame: frames.add, onError: (error) => throw StateError('$error'));
    addTearDown(source.dispose);
    diagnostics['phase'] = 'starting-frame-source';
    await source.start();
    diagnostics['phase'] = 'waiting-for-frame';
    await _waitFor(tester, () => frames.isNotEmpty);
    final frame = frames.last;
    expect(frame.width, greaterThan(0));
    expect(frame.height, greaterThan(0));
    expect(frame.image.toBgraBytes().any((byte) => byte != 0), isTrue);

    source.dispose();
    final count = frames.length;
    await tester.pump(const Duration(milliseconds: 250));
    expect(frames, hasLength(count));
    diagnostics['testPassed'] = true;
  }, timeout: const Timeout(Duration(seconds: 15)));
}

Future<void> _waitFor(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(condition(), isTrue, reason: 'camera did not deliver a frame');
}
