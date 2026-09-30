import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// VIEW-04 entry point: splits the preview's "accepted -> presented" interval
/// into BGRA conversion, texture creation, and drawing.
///
/// Built as its own app target so it never touches the example's main screen:
/// `flutter build apk --release -t lib/view04_draw_bench.dart`. Numbers are
/// only meaningful in `--release`; profile and debug runs are kept for
/// contrast and every result line records the build mode it came from.
/// Results go to logcat with the `VIEW-04` prefix and stay on screen.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await YuvFfi.initialize();
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: View04DrawBenchScreen()));
}

const _warmupFrames = 10;
const _measuredFrames = 60;

// Pixel 3 front camera at ResolutionPreset.medium, and the 1080p size the
// Windows BGRA-00 breakdown used.
const _sizes = [(720, 480), (1920, 1080)];

/// Runs every VIEW-04 scenario once on start and shows the result lines.
///
/// Each frame goes the way [YuvFramePresenter] takes it: `toBgraBytes()`,
/// `ImmutableBuffer` -> `ImageDescriptor.raw` -> codec -> `ui.Image`, then one
/// drawn frame, strictly one frame in flight. Raster time comes from engine
/// [ui.FrameTiming]s of the frames drawn inside the measured window.
class View04DrawBenchScreen extends StatefulWidget {
  const View04DrawBenchScreen({super.key});

  @override
  State<View04DrawBenchScreen> createState() => _View04DrawBenchScreenState();
}

class _View04DrawBenchScreenState extends State<View04DrawBenchScreen> {
  final _results = <Map<String, Object?>>[];
  final _timings = <ui.FrameTiming>[];
  ui.Image? _shown;
  int _repaintTick = 0;
  _DrawOrientation _drawOrientation = _DrawOrientation.none;
  ui.FragmentShader? _shader;

  /// Source-from-destination mapping handed to the shader, picked by
  /// [_verifyShader]: `(m00, m01, m10, m11, offsetX, offsetY)`.
  List<double> _shaderMapping = const [];
  bool _drawWithShader = false;
  String _status = 'Starting...';
  Object? _error;

  String get _buildMode => kReleaseMode
      ? 'release'
      : kProfileMode
      ? 'profile'
      : 'debug';

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_timings.addAll);
    // Starts after the first frame so the scaffold's own first layout is not
    // inside any measured window.
    SchedulerBinding.instance.addPostFrameCallback((_) => _runAll().ignore());
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_timings.addAll);
    _shown?.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('VIEW-04 draw bench ($_buildMode)')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              // Keeps the status text out of the measured frames' raster work.
              child: RepaintBoundary(
                child: CustomPaint(painter: _FramePainter(_shown, _repaintTick, _drawOrientation, _drawWithShader ? _shaderDraw : null)),
              ),
            ),
            Padding(padding: const EdgeInsets.all(8), child: Text(_error == null ? _status : 'Error: $_error')),
            if (_results.isNotEmpty)
              SizedBox(
                height: 220,
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

  _ShaderDraw? get _shaderDraw {
    final shader = _shader;
    final image = _shown;
    if (shader == null || image == null || _shaderMapping.isEmpty) {
      return null;
    }
    // The texture is W/4 x H*1.5, so the frame size follows from it.
    return _ShaderDraw(shader, image, image.width * 4, image.height * 2 ~/ 3, _shaderMapping);
  }

  Future<void> _runAll() async {
    try {
      _shader = (await ui.FragmentProgram.fromAsset('shaders/view04_i420.frag')).fragmentShader();
      for (final (width, height) in _sizes) {
        final frame = YuvImage.i420(width, height)..applyRgbaBytes(_pattern(width, height));
        await _verifyShader(frame);
        // A shader path would upload the tight I420 planes as they are:
        // w*h*1.5 bytes, here as an RGBA texture a quarter as wide. Content
        // does not matter for upload cost, only size.
        final planeBytes = Uint8List(width * height * 3 ~/ 2);
        await _measureUpload('bgra_path', width, height, () => frame.toBgraBytes(), width, height, ui.PixelFormat.bgra8888);
        // Runs right after bgra_path, so the full-size BGRA frame is on screen.
        await _measureRedraw('redraw_same_image', width, height);
        await _measureUpload('planes_as_rgba_upload', width, height, () => planeBytes, width ~/ 4, height * 3 ~/ 2, ui.PixelFormat.rgba8888);
        // Interleaved twice so drift over the run (thermal, clocks) hits both
        // variants alike instead of favouring whichever ran first.
        for (var round = 0; round < 2; round++) {
          await _measureConvertControl(frame);
          await _measureFullPath('full_path_cpu_orientation', frame, _PathVariant.cpu);
          await _measureFullPath('full_path_draw_orientation', frame, _PathVariant.canvas);
          await _measureFullPath('full_path_shader', frame, _PathVariant.shader);
        }
      }
      // Left on screen so a screenshot can confirm the on-screen shader
      // draw, which the offscreen check in _verifyShader does not cover.
      final (stillWidth, stillHeight) = _sizes.first;
      final still = YuvImage.i420(stillWidth, stillHeight)..applyRgbaBytes(_pattern(stillWidth, stillHeight));
      await _verifyShader(still);
      _show(await _planesTexture(still.toBytes(), stillWidth, stillHeight));
      setState(() => _drawWithShader = true);
      _setStatus('Done: ${_results.length} scenarios, build mode $_buildMode');
      debugPrint('VIEW-04 done mode=$_buildMode');
    } catch (ex, stack) {
      debugPrint('VIEW-04 failed: $ex\n$stack');
      if (mounted) setState(() => _error = ex);
    }
  }

  Future<void> _measureUpload(
    String scenario,
    int frameWidth,
    int frameHeight,
    Uint8List Function() bytesOf,
    int textureWidth,
    int textureHeight,
    ui.PixelFormat pixelFormat,
  ) async {
    _setStatus('$scenario ${frameWidth}x$frameHeight...');
    await SchedulerBinding.instance.endOfFrame;
    final stages = {
      for (final key in ['convert', 'buffer', 'codec', 'image', 'show', 'total']) key: <int>[],
    };
    final stopwatch = Stopwatch();
    var windowStart = 0;
    for (var i = 0; i < _warmupFrames + _measuredFrames; i++) {
      if (i == _warmupFrames) {
        windowStart = Timeline.now;
      }
      stopwatch
        ..reset()
        ..start();
      final bytes = bytesOf();
      final convertAt = stopwatch.elapsedMicroseconds;
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final bufferAt = stopwatch.elapsedMicroseconds;
      final descriptor = ui.ImageDescriptor.raw(buffer, width: textureWidth, height: textureHeight, pixelFormat: pixelFormat);
      final codec = await descriptor.instantiateCodec();
      final codecAt = stopwatch.elapsedMicroseconds;
      final image = (await codec.getNextFrame()).image;
      final imageAt = stopwatch.elapsedMicroseconds;
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
      _show(image);
      // Completes after build, layout and paint recording of the frame that
      // shows [image]; rasterization runs after it on the raster thread and
      // is taken from FrameTiming instead.
      await SchedulerBinding.instance.endOfFrame;
      final shownAt = stopwatch.elapsedMicroseconds;
      if (i < _warmupFrames) {
        continue;
      }
      stages['convert']?.add(convertAt);
      stages['buffer']?.add(bufferAt - convertAt);
      stages['codec']?.add(codecAt - bufferAt);
      stages['image']?.add(imageAt - codecAt);
      stages['show']?.add(shownAt - imageAt);
      stages['total']?.add(shownAt);
    }
    await _report(scenario, frameWidth, frameHeight, windowStart, Timeline.now, stages, {
      'texture_width': textureWidth,
      'texture_height': textureHeight,
      'texture_bytes': textureWidth * textureHeight * 4,
    });
  }

  /// The whole Android mobile preview path for one frame, from the imported
  /// planes to the drawn frame: a plane copy standing in for
  /// `CameraImage.toYuvImage()`, the front camera's quarter turn and mirror,
  /// conversion, texture, draw. See [_PathVariant] for where each variant
  /// orients and converts.
  Future<void> _measureFullPath(String scenario, YuvImage source, _PathVariant variant) async {
    final width = source.width;
    final height = source.height;
    _setStatus('$scenario ${width}x$height...');
    setState(() {
      _drawOrientation = variant == _PathVariant.canvas ? _DrawOrientation.frontCamera : _DrawOrientation.none;
      _drawWithShader = variant == _PathVariant.shader;
    });
    await SchedulerBinding.instance.endOfFrame;
    final stages = {
      for (final key in ['import', 'rotate', 'flip', 'convert', 'texture', 'work', 'show', 'total']) key: <int>[],
    };
    final stopwatch = Stopwatch();
    var windowStart = 0;
    for (var i = 0; i < _warmupFrames + _measuredFrames; i++) {
      if (i == _warmupFrames) {
        windowStart = Timeline.now;
      }
      stopwatch
        ..reset()
        ..start();
      var frame = source.copy();
      final importAt = stopwatch.elapsedMicroseconds;
      if (variant == _PathVariant.cpu) {
        frame = frame.applyRotation(YuvImageRotation.rotation90);
      }
      final rotateAt = stopwatch.elapsedMicroseconds;
      if (variant == _PathVariant.cpu) {
        frame.applyFlipHorizontal();
      }
      final flipAt = stopwatch.elapsedMicroseconds;
      // For the shader, "convert" is only gathering the planes into one
      // buffer; a real import could write them there in the first place.
      final bytes = variant == _PathVariant.shader ? frame.toBytes() : frame.toBgraBytes();
      final convertAt = stopwatch.elapsedMicroseconds;
      final image = variant == _PathVariant.shader
          ? await _planesTexture(bytes, frame.width, frame.height)
          : await _texture(bytes, frame.width, frame.height, ui.PixelFormat.bgra8888);
      final textureAt = stopwatch.elapsedMicroseconds;
      _show(image);
      await SchedulerBinding.instance.endOfFrame;
      final shownAt = stopwatch.elapsedMicroseconds;
      if (i < _warmupFrames) {
        continue;
      }
      stages['import']?.add(importAt);
      stages['rotate']?.add(rotateAt - importAt);
      stages['flip']?.add(flipAt - rotateAt);
      stages['convert']?.add(convertAt - flipAt);
      stages['texture']?.add(textureAt - convertAt);
      stages['work']?.add(textureAt);
      stages['show']?.add(shownAt - textureAt);
      stages['total']?.add(shownAt);
    }
    await _report(scenario, width, height, windowStart, Timeline.now, stages, {'variant': variant.name});
    setState(() {
      _drawOrientation = _DrawOrientation.none;
      _drawWithShader = false;
    });
  }

  /// Draws [source] through the shader offscreen and compares every pixel
  /// with the CPU path (turn, mirror, `toBgraBytes()`); the prototype's
  /// numbers count only if it draws the same picture.
  ///
  /// The library's quarter-turn direction is not assumed: both mappings a
  /// turn plus mirror can produce are tried, and the one that matches is kept
  /// for the timed runs.
  Future<void> _verifyShader(YuvImage source) async {
    final shader = _shader;
    if (shader == null) {
      throw StateError('shader not loaded');
    }
    final width = source.width;
    final height = source.height;
    final expected = (source.copy().applyRotation(YuvImageRotation.rotation90)..applyFlipHorizontal()).toBgraBytes();
    final texture = await _planesTexture(source.toBytes(), width, height);
    final candidates = {
      'transpose': [0.0, 1.0, 1.0, 0.0, 0.0, 0.0],
      'anti_transpose': [0.0, -1.0, -1.0, 0.0, width - 1.0, height - 1.0],
    };
    final report = <String, Object>{};
    String? matched;
    for (final MapEntry(key: name, value: mapping) in candidates.entries) {
      final recorder = ui.PictureRecorder();
      _ShaderDraw(shader, texture, width, height, mapping).paint(Canvas(recorder), Offset.zero & Size(height.toDouble(), width.toDouble()));
      final drawn = await recorder.endRecording().toImageSync(height, width).toByteData();
      if (drawn == null) {
        throw StateError('shader output unreadable');
      }
      var maxDiff = 0;
      var mismatched = 0;
      for (var p = 0; p < width * height; p++) {
        for (final (rgba, bgra) in [(0, 2), (1, 1), (2, 0)]) {
          final diff = (drawn.getUint8(p * 4 + rgba) - expected[p * 4 + bgra]).abs();
          if (diff > maxDiff) maxDiff = diff;
          if (diff > 1) mismatched++;
        }
      }
      report[name] = {'max_diff': maxDiff, 'channels_off_by_more_than_1': mismatched};
      if (matched == null && maxDiff <= 1) {
        matched = name;
        _shaderMapping = mapping;
      }
    }
    texture.dispose();
    debugPrint('VIEW-04 shader check ${width}x$height mode=$_buildMode matched=$matched ${jsonEncode(report)}');
    if (matched == null) {
      throw StateError('shader output differs from the CPU path: $report');
    }
  }

  Future<ui.Image> _planesTexture(Uint8List planes, int width, int height) => _texture(planes, width ~/ 4, height * 3 ~/ 2, ui.PixelFormat.rgba8888);

  Future<ui.Image> _texture(Uint8List bytes, int width, int height, ui.PixelFormat pixelFormat) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = ui.ImageDescriptor.raw(buffer, width: width, height: height, pixelFormat: pixelFormat);
    final codec = await descriptor.instantiateCodec();
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
    }
  }

  /// Control for the full-path runs: `toBgraBytes()` on a plain copy and on a
  /// turned and mirrored copy, each either right after the work that made it
  /// or after an idle gap, and after a CPU-only spin that touches no frame
  /// memory. Separates the plane layout from CPU clock and cache state.
  Future<void> _measureConvertControl(YuvImage source) async {
    _setStatus('convert_control ${source.width}x${source.height}...');
    await SchedulerBinding.instance.endOfFrame;
    for (final (name, image) in [
      ('source', source),
      ('copy', source.copy()),
      ('oriented', source.copy().applyRotation(YuvImageRotation.rotation90)..applyFlipHorizontal()),
    ]) {
      final planes = image.planes.map((p) => '${p.rowStride}/${p.pixelStride}/${p.height}/${p.bytes.length}/off${p.bytes.offsetInBytes}').join(' ');
      debugPrint(
        'VIEW-04 geometry ${source.width}x${source.height} $name: ${image.width}x${image.height} ${image.format.name} planes(rowStride/pixelStride/height/bytes) $planes',
      );
    }
    final stages = {
      for (final key in ['copy_then_idle', 'copy_then_spin', 'copy_immediate', 'oriented_then_idle', 'oriented_immediate']) key: <int>[],
    };
    final stopwatch = Stopwatch();
    for (var i = 0; i < _warmupFrames + _measuredFrames; i++) {
      final samples = <String, int>{};
      for (final key in stages.keys) {
        var image = source.copy();
        if (key.startsWith('oriented')) {
          image = image.applyRotation(YuvImageRotation.rotation90)..applyFlipHorizontal();
        }
        if (key.endsWith('idle')) {
          await Future<void>.delayed(const Duration(milliseconds: 16));
        } else if (key.endsWith('spin')) {
          final spin = Stopwatch()..start();
          while (spin.elapsedMicroseconds < 10000) {}
        }
        stopwatch
          ..reset()
          ..start();
        image.toBgraBytes();
        samples[key] = stopwatch.elapsedMicroseconds;
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
      if (i >= _warmupFrames) {
        for (final MapEntry(:key, :value) in samples.entries) {
          stages[key]?.add(value);
        }
      }
    }
    final now = Timeline.now;
    await _report('convert_control', source.width, source.height, now, now, stages, const {});
  }

  /// Repaints the image already on screen, so the raster time here is drawing
  /// without a new texture; the difference to bgra_path is the upload share.
  Future<void> _measureRedraw(String scenario, int width, int height) async {
    _setStatus('$scenario ${width}x$height...');
    await SchedulerBinding.instance.endOfFrame;
    final show = <int>[];
    final stopwatch = Stopwatch();
    var windowStart = 0;
    for (var i = 0; i < _warmupFrames + _measuredFrames; i++) {
      if (i == _warmupFrames) {
        windowStart = Timeline.now;
      }
      stopwatch
        ..reset()
        ..start();
      setState(() => _repaintTick++);
      await SchedulerBinding.instance.endOfFrame;
      if (i >= _warmupFrames) {
        show.add(stopwatch.elapsedMicroseconds);
      }
    }
    await _report(scenario, width, height, windowStart, Timeline.now, {'show': show}, const {});
  }

  Future<void> _report(
    String scenario,
    int width,
    int height,
    int windowStart,
    int windowEnd,
    Map<String, List<int>> stages,
    Map<String, Object?> extra,
  ) async {
    // The engine batches FrameTimings (about every 100 ms in release) and
    // sends a batch only when a later frame is rasterized, so one more frame
    // is forced after a pause to flush the window's last frames.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    _setStatus('$scenario ${width}x$height: collecting frame timings...');
    await SchedulerBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 250));

    final window = _timings.where((t) {
      final vsync = t.timestampInMicroseconds(ui.FramePhase.vsyncStart);
      return vsync >= windowStart && vsync <= windowEnd;
    }).toList();
    _timings.clear();

    final result = <String, Object?>{
      'card': 'VIEW-04',
      'build_mode': _buildMode,
      'scenario': scenario,
      'width': width,
      'height': height,
      'samples': _measuredFrames,
      ...extra,
      for (final MapEntry(:key, :value) in stages.entries) ...{'${key}_median_ms': value.median / 1000, '${key}_p90_ms': value.p90 / 1000},
      'frame_timings_in_window': window.length,
      'raster_median_ms': window.map((t) => t.rasterDuration.inMicroseconds).toList().median / 1000,
      'raster_p90_ms': window.map((t) => t.rasterDuration.inMicroseconds).toList().p90 / 1000,
      'build_median_ms': window.map((t) => t.buildDuration.inMicroseconds).toList().median / 1000,
    };
    debugPrint('VIEW-04 result: ${jsonEncode(result)}');
    for (final MapEntry(:key, :value) in stages.entries) {
      debugPrint('VIEW-04 raw $_buildMode $scenario ${width}x$height $key: ${value.join(',')}');
    }
    debugPrint('VIEW-04 raw $_buildMode $scenario ${width}x$height raster: ${window.map((t) => t.rasterDuration.inMicroseconds).join(',')}');
    if (mounted) setState(() => _results.add(result));
  }

  void _show(ui.Image image) {
    final previous = _shown;
    setState(() => _shown = image);
    // The recorded picture keeps its own reference to the drawn image, so the
    // handle can go now, as YuvFramePresenter does with its previous frame.
    previous?.dispose();
  }

  void _setStatus(String status) {
    if (mounted) setState(() => _status = status);
  }

  // Same deterministic gradient as the BGRA-00..02 Pixel 3 runners.
  Uint8List _pattern(int width, int height) {
    final rgba = Uint8List(width * height * 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = (y * width + x) * 4;
        rgba[i] = (x * 3 + 10) & 0xFF;
        rgba[i + 1] = (y * 5 + 20) & 0xFF;
        rgba[i + 2] = (x * 7 + y * 11 + 30) & 0xFF;
        rgba[i + 3] = 255;
      }
    }
    return rgba;
  }
}

/// Where a full-path run orients and converts the frame.
enum _PathVariant {
  /// Turned and mirrored in memory, converted to BGRA: today's preview.
  cpu,

  /// Converted to BGRA as the sensor gave it, turned and mirrored by the
  /// canvas.
  canvas,

  /// Planes uploaded as they are; the shader converts, turns and mirrors.
  shader,
}

/// How the painter orients the frame while drawing it.
enum _DrawOrientation {
  none,

  /// A quarter turn clockwise then a horizontal mirror, as the Android
  /// preview applies to the front camera in memory.
  frontCamera,
}

class _FramePainter extends CustomPainter {
  final ui.Image? image;
  final int repaintTick;
  final _DrawOrientation orientation;
  final _ShaderDraw? shaderDraw;

  _FramePainter(this.image, this.repaintTick, this.orientation, this.shaderDraw);

  @override
  void paint(Canvas canvas, Size size) {
    final image = this.image;
    if (image == null) {
      return;
    }
    final shaderDraw = this.shaderDraw;
    if (shaderDraw != null) {
      final outputSize = shaderDraw.outputSize;
      final destination = Alignment.center.inscribe(applyBoxFit(BoxFit.contain, outputSize, size).destination, Offset.zero & size);
      canvas
        ..save()
        ..translate(destination.left, destination.top)
        ..scale(destination.width / outputSize.width);
      shaderDraw.paint(canvas, Offset.zero & outputSize);
      canvas.restore();
      return;
    }
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    if (orientation == _DrawOrientation.frontCamera) {
      final turnedSize = imageSize.flipped;
      final destination = Alignment.center.inscribe(applyBoxFit(BoxFit.contain, turnedSize, size).destination, Offset.zero & size);
      final scale = destination.width / turnedSize.width;
      // Mirror in screen space after the turn, matching rotate-then-flip in
      // memory: the canvas applies these transforms in reverse order.
      canvas
        ..save()
        ..translate(destination.center.dx, destination.center.dy)
        ..scale(-scale, scale)
        ..rotate(math.pi / 2)
        ..drawImage(image, Offset(-imageSize.width / 2, -imageSize.height / 2), Paint()..filterQuality = FilterQuality.low)
        ..restore();
      return;
    }
    final fitted = applyBoxFit(BoxFit.contain, imageSize, size);
    final destination = Alignment.center.inscribe(fitted.destination, Offset.zero & size);
    canvas.drawImageRect(
      image,
      Alignment.center.inscribe(fitted.source, Offset.zero & imageSize),
      destination,
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(_FramePainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.repaintTick != repaintTick ||
      oldDelegate.orientation != orientation ||
      (oldDelegate.shaderDraw == null) != (shaderDraw == null);
}

/// One shader draw of an I420 planes texture, turned and mirrored by
/// [mapping] into a frame of the swapped size.
class _ShaderDraw {
  final ui.FragmentShader shader;
  final ui.Image planes;
  final int frameWidth;
  final int frameHeight;
  final List<double> mapping;

  Size get outputSize => Size(frameHeight.toDouble(), frameWidth.toDouble());

  const _ShaderDraw(this.shader, this.planes, this.frameWidth, this.frameHeight, this.mapping);

  /// Fills [rect], whose local coordinates are output pixels.
  void paint(Canvas canvas, Rect rect) {
    // Float uniforms in declaration order: uFrameSize, uMap, uOffset,
    // uTextureSize.
    final floats = [frameWidth.toDouble(), frameHeight.toDouble(), ...mapping, planes.width.toDouble(), planes.height.toDouble()];
    for (var i = 0; i < floats.length; i++) {
      shader.setFloat(i, floats[i]);
    }
    shader.setImageSampler(0, planes);
    canvas.drawRect(rect, Paint()..shader = shader);
  }
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
