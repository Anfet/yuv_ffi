// VIEW-01A / VIEW-01B diagnostic tool. Not wired into `main.dart` and not part
// of the demo app's UI; run it directly on a desktop platform with a physical
// camera to reproduce the frame-stream smoke test recorded in
// `todo.md` (VIEW-01A, second pass). Keep this file until VIEW-01B lands a
// real desktop `camera_desktop` integration with its own test coverage, then
// it can be deleted along with this note.
//
// Run (from `example/`):
//   flutter run -t lib/camera_desktop_smoke_main.dart -d windows
//   flutter run -t lib/camera_desktop_smoke_main.dart -d macos
//   flutter run -t lib/camera_desktop_smoke_main.dart -d linux
//
// What it proves and why it bypasses `CameraController.startImageStream`:
// `camera` 0.11.0+2's `CameraController.startImageStream`/`stopImageStream`
// assert `defaultTargetPlatform` is Android or iOS
// (camera_controller.dart:488, :524 in camera-0.11.0+2). That assert fires in
// debug/profile regardless of which `CameraPlatform.instance` is registered,
// even though the method's actual body is just
// `CameraPlatform.instance.onStreamedFrameAvailable(cameraId).listen(...)`,
// which is not platform-gated at all. This smoke calls
// `CameraPlatform.instance.onStreamedFrameAvailable` directly -- the same
// call `startImageStream` would make -- so it streams real frames on desktop
// without tripping that assert, while still using `CameraController` for
// `initialize`/`dispose`/lifecycle. VIEW-01B's desktop preview should use the
// same bypass rather than calling `controller.startImageStream()` directly.
import 'dart:async';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:yuv_ffi_example/ext.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _SmokeApp());
}

class _SmokeApp extends StatelessWidget {
  const _SmokeApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('camera_desktop image-stream smoke')),
        body: const _SmokeBody(),
      ),
    );
  }
}

class _SmokeBody extends StatefulWidget {
  const _SmokeBody();

  @override
  State<_SmokeBody> createState() => _SmokeBodyState();
}

class _SmokeBodyState extends State<_SmokeBody> {
  final List<String> _log = <String>[];
  bool _running = false;

  @override
  void initState() {
    super.initState();
    unawaited(_runSmoke());
  }

  void _append(String line) {
    // Printed as well as shown on screen: `flutter run`'s console is the
    // artifact a reviewer copies into a report; the on-screen list is for
    // watching it live.
    debugPrint('[camera_desktop_smoke] $line');
    if (mounted) {
      setState(() => _log.add(line));
    } else {
      _log.add(line);
    }
  }

  Future<void> _runSmoke() async {
    if (_running) {
      return;
    }
    _running = true;
    int? cameraId;
    StreamSubscription<CameraImageData>? subscription;
    try {
      final cameras = await availableCameras();
      _append('availableCameras: ${cameras.length}');
      for (final c in cameras) {
        _append('  ${c.name} lensDirection=${c.lensDirection} sensorOrientation=${c.sensorOrientation}');
      }
      if (cameras.isEmpty) {
        _append('No camera available; stopping.');
        return;
      }

      final description = cameras.first;
      cameraId = await CameraPlatform.instance.createCamera(description, ResolutionPreset.medium, enableAudio: false);
      _append('createCamera -> cameraId=$cameraId');

      final initialized = CameraPlatform.instance.onCameraInitialized(cameraId).first;
      await CameraPlatform.instance.initializeCamera(cameraId);
      final initEvent = await initialized;
      _append('initializeCamera -> previewSize=${initEvent.previewWidth}x${initEvent.previewHeight}');

      var framesSeen = 0;
      const targetFrames = 5;
      final framesDone = Completer<void>();

      // The bypass described in the file header: this is exactly what
      // `CameraController.startImageStream` calls internally, minus its
      // Android/iOS-only assert.
      subscription = CameraPlatform.instance
          .onStreamedFrameAvailable(cameraId)
          .listen(
            (CameraImageData data) {
              if (framesDone.isCompleted) {
                return;
              }
              framesSeen++;
              final image = CameraImage.fromPlatformInterface(data);
              final plane = image.planes.first;
              _append(
                'frame $framesSeen: ${image.width}x${image.height} '
                'format=${image.format.group} raw=${image.format.raw} '
                'planes=${image.planes.length} bytesPerRow=${plane.bytesPerRow} '
                'bytesPerPixel=${plane.bytesPerPixel} bufferLength=${plane.bytes.length}',
              );

              try {
                final yuv = image.toYuvImage();
                final bgra = yuv.toBgraBytes();
                _append(
                  'toYuvImage/toBgraBytes ok: format=${yuv.format} '
                  'firstPixel=${bgra.sublist(0, 4)}',
                );
              } catch (e) {
                _append('toYuvImage/toBgraBytes FAILED: $e');
              }

              if (framesSeen >= targetFrames && !framesDone.isCompleted) {
                framesDone.complete();
              }
            },
            onError: (Object e) {
              _append('onStreamedFrameAvailable error: $e');
              if (!framesDone.isCompleted) {
                framesDone.complete();
              }
            },
          );

      await framesDone.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => _append('Timed out waiting for $targetFrames frames (got $framesSeen).'),
      );

      // Mirrors CameraController.stopImageStream's body (cancel the
      // subscription) without its Android/iOS-only assert.
      await subscription.cancel();
      subscription = null;
      _append('stream stopped, subscription cancelled');
    } catch (e, st) {
      _append('SMOKE FAILED: $e');
      debugPrint('$st');
    } finally {
      await subscription?.cancel();
      if (cameraId != null) {
        await CameraPlatform.instance.dispose(cameraId);
        _append('dispose($cameraId) done');
      }
      _append('SMOKE COMPLETE');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: _log.length,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Text(_log[index], style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
      ),
    );
  }
}
