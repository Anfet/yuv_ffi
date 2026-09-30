import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_ffi_example/ext.dart';
import 'package:yuv_ffi_example/view04_i420_shader.dart';

/// VIEW-04 live camera entry point: the front camera's real stream shown the
/// way the Android mobile preview does it today (turn and mirror in memory,
/// BGRA, texture) against the I420 shader prototype (planes texture, shader
/// converts, turns and mirrors).
///
/// `flutter build apk --release -t lib/view04_camera_bench.dart`. Only the
/// release numbers count; every result line records the build mode. Results
/// go to logcat with the `VIEW-04 camera` prefix and stay on screen.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await YuvFfi.initialize();
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: View04CameraBenchScreen()));
}

const _warmup = Duration(seconds: 3);
const _window = Duration(seconds: 10);

// Alternated so drift over the session (heat, clocks) hits both paths alike.
const _runs = [
  (30, _Variant.cpu),
  (30, _Variant.shader),
  (30, _Variant.cpu),
  (30, _Variant.shader),
  (60, _Variant.cpu),
  (60, _Variant.shader),
  (60, _Variant.cpu),
  (60, _Variant.shader),
];

/// Where a frame is oriented and converted.
enum _Variant {
  /// Turned and mirrored in memory, converted to BGRA: today's preview.
  cpu,

  /// Planes uploaded as they are; the shader converts, turns and mirrors.
  shader,
}

/// Runs every live camera VIEW-04 run once on start and shows the results.
///
/// Like `YuvCameraPreview`, one frame is in flight at a time: a frame that
/// arrives while the previous one is still being prepared or drawn is dropped
/// before it is imported.
class View04CameraBenchScreen extends StatefulWidget {
  const View04CameraBenchScreen({super.key});

  @override
  State<View04CameraBenchScreen> createState() => _View04CameraBenchScreenState();
}

class _View04CameraBenchScreenState extends State<View04CameraBenchScreen> {
  final _results = <Map<String, Object?>>[];
  final _clock = Stopwatch()..start();
  View04I420Shader? _shader;
  CameraController? _controller;
  ui.Image? _shown;
  List<double>? _shownMapping;
  String _status = 'Starting...';
  Object? _error;

  _Variant _variant = _Variant.cpu;
  YuvImageRotation _rotation = YuvImageRotation.rotation0;
  List<double>? _mapping;
  bool _busy = false;
  bool _measuring = false;
  bool _checked = false;
  int _delivered = 0;
  int _droppedBusy = 0;
  int _presented = 0;
  int? _lastPresentedUs;
  final _stages = <String, List<int>>{};

  String get _buildMode => kReleaseMode
      ? 'release'
      : kProfileMode
      ? 'profile'
      : 'debug';

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback((_) => _runAll().ignore());
  }

  @override
  void dispose() {
    _controller?.dispose();
    _shown?.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('VIEW-04 camera bench ($_buildMode)')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: RepaintBoundary(child: CustomPaint(painter: _FramePainter(_shown, _shownMapping, _shader))),
            ),
            Padding(padding: const EdgeInsets.all(8), child: Text(_error == null ? _status : 'Error: $_error')),
            if (_results.isNotEmpty)
              SizedBox(
                height: 200,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(8),
                  child: SelectableText(
                    const JsonEncoder.withIndent(' ').convert(_results),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _runAll() async {
    try {
      _shader = await View04I420Shader.load();
      final cameras = await availableCameras();
      final camera = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cameras.first);
      // Same rotation the mobile preview derives from the sensor.
      _rotation = YuvImageRotation.values.firstWhere((e) => e.degrees == camera.sensorOrientation.abs()).toZero();
      for (final (index, (fps, variant)) in _runs.indexed) {
        await _runOne(camera, index, fps, variant);
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      _setStatus('Done: ${_results.length} runs, build mode $_buildMode');
      debugPrint('VIEW-04 camera done mode=$_buildMode');
    } catch (ex, stack) {
      debugPrint('VIEW-04 camera failed: $ex\n$stack');
      if (mounted) setState(() => _error = ex);
    }
  }

  Future<void> _runOne(CameraDescription camera, int index, int fps, _Variant variant) async {
    _setStatus('Run $index: ${variant.name} at $fps fps requested, opening camera...');
    _variant = variant;
    _checked = false;
    final controller = _controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      fps: fps,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await controller.initialize();
    await controller.startImageStream(_onImage);

    _setStatus('Run $index: ${variant.name} at $fps fps requested, warm-up...');
    await Future<void>.delayed(_warmup);
    _delivered = 0;
    _droppedBusy = 0;
    _presented = 0;
    _lastPresentedUs = null;
    _stages.clear();
    _measuring = true;
    _setStatus('Run $index: ${variant.name} at $fps fps requested, measuring...');
    await Future<void>.delayed(_window);
    _measuring = false;

    await controller.stopImageStream();
    // Lets a frame still in flight finish before the controller goes away.
    while (_busy) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await controller.dispose();
    _controller = null;

    final seconds = _window.inMicroseconds / 1e6;
    final result = <String, Object?>{
      'card': 'VIEW-04',
      'phase': 'live_camera',
      'build_mode': _buildMode,
      'run_index': index,
      'variant': variant.name,
      'fps_requested': fps,
      'delivered': _delivered,
      'delivered_hz': _delivered / seconds,
      'dropped_busy': _droppedBusy,
      'presented': _presented,
      'presented_fps': _presented / seconds,
      for (final MapEntry(:key, :value) in _stages.entries) ...{'${key}_median_ms': value.median / 1000, '${key}_p90_ms': value.p90 / 1000},
    };
    debugPrint('VIEW-04 camera result: ${jsonEncode(result)}');
    if (mounted) setState(() => _results.add(result));
  }

  void _onImage(CameraImage image) {
    if (_measuring) _delivered++;
    if (_busy) {
      if (_measuring) _droppedBusy++;
      return;
    }
    _busy = true;
    _present(image).whenComplete(() => _busy = false).ignore();
  }

  Future<void> _present(CameraImage image) async {
    final startUs = _clock.elapsedMicroseconds;
    // Copies the planes before the first await: the camera reuses its buffer
    // once this callback returns.
    var frame = image.toYuvImage();
    final importUs = _clock.elapsedMicroseconds;
    if (!_checked) {
      _checked = true;
      await _check(frame);
    }
    final orientStartUs = _clock.elapsedMicroseconds;
    final ui.Image texture;
    final int convertUs;
    final int orientUs;
    if (_variant == _Variant.cpu) {
      frame = frame.applyRotation(_rotation);
      if (defaultTargetPlatform == TargetPlatform.android) {
        frame.applyFlipHorizontal();
      }
      orientUs = _clock.elapsedMicroseconds;
      final bytes = frame.toBgraBytes();
      convertUs = _clock.elapsedMicroseconds;
      texture = await View04I420Shader.texture(bytes, frame.width, frame.height, ui.PixelFormat.bgra8888);
    } else {
      orientUs = _clock.elapsedMicroseconds;
      final bytes = frame.toBytes();
      convertUs = _clock.elapsedMicroseconds;
      texture = await View04I420Shader.planesTexture(bytes, frame.width, frame.height);
    }
    final textureUs = _clock.elapsedMicroseconds;
    if (!mounted) {
      texture.dispose();
      return;
    }
    final previous = _shown;
    setState(() {
      _shown = texture;
      _shownMapping = _variant == _Variant.shader ? _mapping : null;
    });
    previous?.dispose();
    await SchedulerBinding.instance.endOfFrame;
    final shownUs = _clock.elapsedMicroseconds;
    if (!_measuring) {
      return;
    }
    _presented++;
    final lastPresentedUs = _lastPresentedUs;
    if (lastPresentedUs != null) _add('presented_gap', shownUs - lastPresentedUs);
    _lastPresentedUs = shownUs;
    _add('import', importUs - startUs);
    _add('orient', orientUs - orientStartUs);
    _add('convert', convertUs - orientUs);
    _add('texture', textureUs - convertUs);
    // Without the one-off check, which only ever runs in warm-up.
    _add('work', textureUs - orientStartUs + importUs - startUs);
    _add('show', shownUs - textureUs);
  }

  /// Logs the real frame's geometry and, once per run, matches the shader's
  /// output against the CPU path on this very frame; the run fails rather
  /// than time a shader that draws something else.
  Future<void> _check(YuvImage frame) async {
    final planes = frame.planes.map((p) => '${p.rowStride}/${p.pixelStride}/${p.height}/${p.bytes.length}').join(' ');
    debugPrint(
      'VIEW-04 camera geometry ${frame.width}x${frame.height} ${frame.format.name} '
      'planes(rowStride/pixelStride/height/bytes) $planes rotation=${_rotation.name}',
    );
    if (_variant != _Variant.shader) {
      return;
    }
    final shader = _shader;
    if (shader == null) {
      throw StateError('shader not loaded');
    }
    final bytes = frame.toBytes();
    if (frame.format != YuvPixelFormat.i420 || frame.width % 4 != 0 || frame.height % 4 != 0 || bytes.length != frame.width * frame.height * 3 ~/ 2) {
      throw StateError('prototype needs a tight I420 frame with sides divisible by 4, got $frame, ${bytes.length} bytes');
    }
    final oriented = frame.copy().applyRotation(_rotation);
    if (defaultTargetPlatform == TargetPlatform.android) {
      oriented.applyFlipHorizontal();
    }
    final texture = await View04I420Shader.planesTexture(bytes, frame.width, frame.height);
    final (matched, report) = await shader.match(texture, frame.width, frame.height, oriented.toBgraBytes());
    texture.dispose();
    debugPrint('VIEW-04 camera shader check ${frame.width}x${frame.height} matched=$matched max_diff=${jsonEncode(report)}');
    if (matched == null) {
      throw StateError('shader output differs from the CPU path on a camera frame: $report');
    }
    _mapping = View04I420Shader.orientations(frame.width, frame.height)[matched];
  }

  void _add(String stage, int micros) => (_stages[stage] ??= []).add(micros);

  void _setStatus(String status) {
    if (mounted) setState(() => _status = status);
  }
}

class _FramePainter extends CustomPainter {
  final ui.Image? image;

  /// Set when [image] is an I420 planes texture to draw through [shader].
  final List<double>? mapping;
  final View04I420Shader? shader;

  _FramePainter(this.image, this.mapping, this.shader);

  @override
  void paint(Canvas canvas, Size size) {
    final image = this.image;
    if (image == null) {
      return;
    }
    final mapping = this.mapping;
    final shader = this.shader;
    if (mapping != null && shader != null) {
      final outputSize = View04I420Shader.outputSize(mapping, image.width * 4, image.height * 2 ~/ 3);
      final destination = Alignment.center.inscribe(applyBoxFit(BoxFit.contain, outputSize, size).destination, Offset.zero & size);
      canvas
        ..save()
        ..translate(destination.left, destination.top)
        ..scale(destination.width / outputSize.width);
      shader.draw(canvas, Offset.zero & outputSize, image, mapping);
      canvas.restore();
      return;
    }
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    final destination = Alignment.center.inscribe(applyBoxFit(BoxFit.contain, imageSize, size).destination, Offset.zero & size);
    canvas.drawImageRect(image, Offset.zero & imageSize, destination, Paint()..filterQuality = FilterQuality.low);
  }

  @override
  bool shouldRepaint(_FramePainter oldDelegate) => oldDelegate.image != image || oldDelegate.mapping != mapping;
}

extension on List<int> {
  int get median => _at(0.5);

  int get p90 => _at(0.9);

  int _at(double quantile) {
    if (isEmpty) {
      return 0;
    }
    final sorted = toList()..sort();
    return sorted[((sorted.length - 1) * quantile).round()];
  }
}
