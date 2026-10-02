// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_ffi_example/camera/frame_read_loop.dart';
import 'package:yuv_ffi_example/camera/stream_start.dart';
import 'package:yuv_ffi_example/camera/yuv_camera_frame.dart';
import 'package:yuv_ffi_example/camera/yuv_camera_frame_source.dart';

import 'js_util_compat_web.dart' as js_util;

/// Web camera source backed by `MediaStreamTrackProcessor`, with a canvas
/// fallback for browsers that do not expose it.
final class YuvCameraFrameSourceImpl implements YuvCameraFrameSource {
  YuvCameraFrameSourceImpl(this.controller, {required this.onFrame, required this.onError});

  final CameraController controller;
  final void Function(YuvCameraFrame frame) onFrame;
  final void Function(Object error) onError;
  final Stopwatch _clock = Stopwatch();
  final html.VideoElement _video = html.VideoElement()
    ..autoplay = true
    ..muted = true;
  final html.CanvasElement _canvas = html.CanvasElement();
  html.MediaStream? _stream;
  Object? _reader;
  int? _animationFrame;
  int? _videoFrameRequest;
  int _generation = 0;
  bool _running = false;
  bool _processing = false;
  bool _disposed = false;
  bool _useBgra = true;
  late final Object _bgraOptions = js_util.jsify({'format': 'BGRA'});
  late final Object _rgbaOptions = js_util.jsify({'format': 'RGBA'});

  @override
  Future<void> start() async {
    stop();
    if (_disposed || !controller.value.isInitialized) {
      if (!_disposed) onError(StateError('CameraController should be initialized'));
      return;
    }
    final generation = _generation;
    _video.setAttribute('playsinline', 'true');
    await runStreamStart<html.MediaStream>(
      open: () async {
        final stream = await html.window.navigator.mediaDevices?.getUserMedia({
          'audio': false,
          'video': {'facingMode': _facingMode(controller.description.lensDirection)},
        });
        if (stream == null) throw StateError('Could not access user media stream');
        return stream;
      },
      isCurrent: () => !_disposed && generation == _generation,
      release: _release,
      attach: (stream) async {
        _stream = stream;
        _video.srcObject = stream;
        await _video.play();
      },
      onStarted: () {
        _clock
          ..reset()
          ..start();
        _running = true;
        if (!_startTrackProcessor(generation)) _scheduleNext();
      },
      onError: (error) => _fail(error, generation),
    );
  }

  bool _startTrackProcessor(int generation) {
    final stream = _stream;
    if (stream == null || !js_util.hasProperty(html.window, 'MediaStreamTrackProcessor')) return false;
    final tracks = stream.getVideoTracks();
    if (tracks.isEmpty) return false;
    try {
      final constructor = js_util.getProperty<Object>(html.window, 'MediaStreamTrackProcessor');
      final processor = js_util.callConstructor<Object>(constructor, [
        js_util.jsify({'track': tracks.first}),
      ]);
      final readable = js_util.getProperty<Object>(processor, 'readable');
      final reader = js_util.callMethod<Object>(readable, 'getReader', const []);
      _reader = reader;
      _readLoop(reader, generation).ignore();
      return true;
    } catch (_) {
      _reader = null;
      return false;
    }
  }

  Future<void> _readLoop(Object reader, int generation) => runFrameReadLoop<Object>(
    read: () async {
      final result = await js_util.promiseToFuture<Object>(js_util.callMethod<Object>(reader, 'read', const []));
      return (done: js_util.getProperty<bool?>(result, 'done') ?? false, frame: js_util.getProperty<Object?>(result, 'value'));
    },
    isCurrent: () => !_disposed && generation == _generation,
    onFrame: (frame) => _processVideoFrame(frame, generation),
    close: _closeVideoFrame,
    onError: (error) => _fail(error, generation),
  );

  Future<void> _processVideoFrame(Object videoFrame, int generation) async {
    if (_processing || !_running || generation != _generation) {
      _closeVideoFrame(videoFrame);
      return;
    }
    _processing = true;
    try {
      final width = js_util.getProperty<num?>(videoFrame, 'displayWidth')?.toInt() ?? 0;
      final height = js_util.getProperty<num?>(videoFrame, 'displayHeight')?.toInt() ?? 0;
      if (width <= 0 || height <= 0) return;
      final bytes = Uint8List(width * height * 4);
      var bgra = _useBgra;
      try {
        await js_util.promiseToFuture<Object>(js_util.callMethod<Object>(videoFrame, 'copyTo', [bytes, bgra ? _bgraOptions : _rgbaOptions]));
      } catch (_) {
        if (!bgra) rethrow;
        _useBgra = false;
        bgra = false;
        await js_util.promiseToFuture<Object>(js_util.callMethod<Object>(videoFrame, 'copyTo', [bytes, _rgbaOptions]));
      }
      if (generation == _generation && !_disposed) _deliverBgra(width, height, bytes, bgra);
    } finally {
      _processing = false;
      _closeVideoFrame(videoFrame);
    }
  }

  void _scheduleNext() {
    if (!_running) return;
    if (js_util.hasProperty(_video, 'requestVideoFrameCallback')) {
      void callback(num _, JSAny __) {
        _captureCanvas();
        _scheduleNext();
      }

      final request = js_util.callMethod<Object>(_video, 'requestVideoFrameCallback', [callback.toJS]);
      _videoFrameRequest = (request as num).toInt();
      return;
    }
    _animationFrame = html.window.requestAnimationFrame((_) {
      _captureCanvas();
      _scheduleNext();
    });
  }

  void _captureCanvas() {
    if (_processing || !_running) return;
    final width = _video.videoWidth;
    final height = _video.videoHeight;
    if (width <= 0 || height <= 0) return;
    _processing = true;
    try {
      _canvas
        ..width = width
        ..height = height;
      final context = _canvas.context2D;
      context.drawImageScaled(_video, 0, 0, width.toDouble(), height.toDouble());
      _deliverBgra(width, height, Uint8List.fromList(context.getImageData(0, 0, width, height).data), false);
    } catch (error) {
      _fail(error, _generation);
    } finally {
      _processing = false;
    }
  }

  void _deliverBgra(int width, int height, Uint8List bytes, bool isBgra) {
    onFrame(
      YuvCameraFrame(
        width: width,
        height: height,
        format: YuvPixelFormat.bgra8888,
        orientation: YuvFrameOrientation.upright,
        timestamp: _clock.elapsed,
        load: () {
          final image = YuvImage.bgra(width, height);
          if (isBgra) {
            image.yPlane.assignFrom(bytes);
            image.markDirty();
          } else {
            image.applyRgbaBytes(bytes);
          }
          return image;
        },
      ),
    );
  }

  void _fail(Object error, int generation) {
    if (_disposed || generation != _generation) return;
    stop();
    onError(error);
  }

  @override
  void stop() {
    _generation++;
    _running = false;
    _clock.stop();
    final reader = _reader;
    _reader = null;
    if (reader != null) js_util.callMethod<Object?>(reader, 'cancel', const []);
    final animationFrame = _animationFrame;
    if (animationFrame != null) html.window.cancelAnimationFrame(animationFrame);
    _animationFrame = null;
    final videoFrameRequest = _videoFrameRequest;
    if (videoFrameRequest != null && js_util.hasProperty(_video, 'cancelVideoFrameCallback')) {
      js_util.callMethod<void>(_video, 'cancelVideoFrameCallback', [videoFrameRequest]);
    }
    _videoFrameRequest = null;
    final stream = _stream;
    _stream = null;
    if (stream != null) _release(stream);
    _video.srcObject = null;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    stop();
  }

  void _closeVideoFrame(Object frame) => js_util.callMethod<void>(frame, 'close', const []);

  void _release(html.MediaStream stream) {
    for (final track in stream.getTracks()) {
      track.stop();
    }
  }

  String _facingMode(CameraLensDirection direction) => switch (direction) {
    CameraLensDirection.front => 'user',
    CameraLensDirection.back || CameraLensDirection.external => 'environment',
  };
}
