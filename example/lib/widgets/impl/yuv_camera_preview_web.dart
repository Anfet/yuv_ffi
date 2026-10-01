// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_ffi_example/widgets/frame_read_loop.dart';
import 'package:yuv_ffi_example/widgets/present_camera_frame.dart';
import 'package:yuv_ffi_example/widgets/stream_start.dart';
import 'js_util_compat_web.dart' as js_util;

/// [onFramePresented] fires once per frame drawn from the camera stream.
/// [onStreamStopped] fires when the stream stops while the preview stays on
/// screen: the controller was replaced or a camera error ended the stream.
Widget buildYuvCameraPreview({
  Key? key,
  CameraController? cameraController,
  bool flipAndroidCameraHorizontally = false,
  YuvImage Function(YuvImage image)? transform,
  VoidCallback? onFramePresented,
  VoidCallback? onStreamStopped,
}) {
  if (cameraController == null) {
    throw ArgumentError('CameraController is required on web platform');
  }
  return _YuvCameraPreviewWeb(
    key: key,
    cameraController: cameraController,
    transform: transform,
    onFramePresented: onFramePresented,
    onStreamStopped: onStreamStopped,
  );
}

class _YuvCameraPreviewWeb extends StatefulWidget {
  final CameraController cameraController;
  final YuvImage Function(YuvImage image)? transform;
  final VoidCallback? onFramePresented;
  final VoidCallback? onStreamStopped;

  const _YuvCameraPreviewWeb({super.key, required this.cameraController, this.transform, this.onFramePresented, this.onStreamStopped});

  @override
  State<_YuvCameraPreviewWeb> createState() => _YuvCameraPreviewWebState();
}

class _YuvCameraPreviewWebState extends State<_YuvCameraPreviewWeb> {
  late final YuvFramePresenter _presenter = YuvFramePresenter(onFramePresented: () => widget.onFramePresented?.call());

  late final html.VideoElement _videoElement;
  late final html.CanvasElement _canvasElement;
  html.CanvasRenderingContext2D? _canvasContext;

  html.MediaStream? _mediaStream;
  int? _rafId;
  int? _videoFrameRequestId;
  Object? _trackReader;
  late final Object _copyToOptionsBgra;
  late final Object _copyToOptionsRgba;
  Uint8List? _rgbaBuffer;
  YuvImage? _reusableBgraFrame;
  bool _running = false;
  // Bumped by _stopLoop. Each start and each TrackProcessor read loop captures
  // the value it began under; a getUserMedia, play, read or copyTo that
  // completes after the stream stopped or restarted carries the old value and
  // its stream, frame or error is dropped.
  int _streamGeneration = 0;
  bool _isProcessing = false;
  Object? _lastError;
  bool _loggedSchedulerPath = false;
  bool _loggedFrameDrop = false;
  bool _copyToUseBgra = true;
  bool _loggedCopyToFormatFallback = false;

  @override
  void initState() {
    super.initState();
    _videoElement = html.VideoElement()
      ..autoplay = true
      ..muted = true;
    _videoElement.setAttribute('playsinline', 'true');
    _canvasElement = html.CanvasElement();
    _canvasContext = _canvasElement.context2D;
    _copyToOptionsBgra = js_util.jsify({'format': 'BGRA'});
    _copyToOptionsRgba = js_util.jsify({'format': 'RGBA'});
    unawaited(_startStream());
  }

  @override
  void didUpdateWidget(covariant _YuvCameraPreviewWeb oldWidget) {
    if (oldWidget.cameraController != widget.cameraController) {
      unawaited(_restartStream());
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    _stopLoop();
    _stopMediaTracks();
    _presenter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_lastError != null) {
      return Center(child: Text('Web camera error: $_lastError', textAlign: TextAlign.center));
    }

    return YuvFrameView(presenter: _presenter);
  }

  Future<void> _restartStream() async {
    debugPrint('[YuvCameraPreviewWeb] Restarting stream');
    _stopLoop();
    _stopMediaTracks();
    _presenter.reset();
    _lastError = null;
    _loggedSchedulerPath = false;
    _loggedFrameDrop = false;
    _copyToUseBgra = true;
    _loggedCopyToFormatFallback = false;
    widget.onStreamStopped?.call();
    if (mounted) {
      setState(() {});
    }
    await _startStream();
  }

  // getUserMedia may wait on the permission prompt for as long as the user
  // likes; the preview can be closed or restarted meanwhile, so everything
  // after each await is bound to the generation this start began under.
  Future<void> _startStream() {
    final generation = _streamGeneration;
    final facingMode = _facingModeFromLens(widget.cameraController.description.lensDirection);
    return runStreamStart<html.MediaStream>(
      open: () async {
        final stream = await html.window.navigator.mediaDevices?.getUserMedia(<String, dynamic>{
          'audio': false,
          'video': <String, dynamic>{'facingMode': facingMode},
        });
        if (stream == null) {
          throw StateError('Could not access user media stream');
        }
        return stream;
      },
      isCurrent: () => mounted && generation == _streamGeneration,
      release: (stream) {
        debugPrint('[YuvCameraPreviewWeb] Releasing the camera stream of a stopped start');
        for (final track in stream.getTracks()) {
          track.stop();
        }
      },
      attach: (stream) async {
        _mediaStream = stream;
        _videoElement.srcObject = stream;
        await _videoElement.play();
      },
      onStarted: () {
        debugPrint('[YuvCameraPreviewWeb] Camera stream started. facingMode=$facingMode');
        _running = true;
        if (!_tryStartTrackProcessor()) {
          debugPrint('[YuvCameraPreviewWeb] Using scheduler pipeline fallback');
          _scheduleNextTick();
        }
      },
      onError: _failStream,
    );
  }

  // A camera error of the current stream: shown instead of the preview, with
  // the loop and the camera tracks stopped rather than left running behind it.
  void _failStream(Object error) {
    debugPrint('[YuvCameraPreviewWeb] Camera stream error: $error');
    _stopLoop();
    _stopMediaTracks();
    _presenter.reset();
    _lastError = error;
    if (mounted) {
      setState(() {});
      widget.onStreamStopped?.call();
    }
  }

  bool _tryStartTrackProcessor() {
    final stream = _mediaStream;
    if (stream == null) {
      debugPrint('[YuvCameraPreviewWeb] TrackProcessor unavailable: media stream is null');
      return false;
    }
    if (!js_util.hasProperty(html.window, 'MediaStreamTrackProcessor')) {
      debugPrint('[YuvCameraPreviewWeb] TrackProcessor unsupported by browser');
      return false;
    }

    final tracks = stream.getVideoTracks();
    if (tracks.isEmpty) {
      debugPrint('[YuvCameraPreviewWeb] TrackProcessor unavailable: no video tracks');
      return false;
    }

    try {
      final track = tracks.first;
      final ctor = js_util.getProperty<Object>(html.window, 'MediaStreamTrackProcessor');
      final processor = js_util.callConstructor<Object>(ctor as dynamic, [
        js_util.jsify({'track': track}),
      ]);
      final readable = js_util.getProperty<Object>(processor, 'readable');
      final reader = js_util.callMethod<Object>(readable, 'getReader', const []);
      _trackReader = reader;
      debugPrint('[YuvCameraPreviewWeb] Using MediaStreamTrackProcessor + VideoFrame.copyTo');
      _trackReadLoop(reader, _streamGeneration).ignore();
      return true;
    } catch (e) {
      debugPrint('[YuvCameraPreviewWeb] TrackProcessor init failed, fallback to scheduler: $e');
      _trackReader = null;
      return false;
    }
  }

  // [generation] is the one [reader] was created under. A read still pending
  // when the stream stops may resolve after the next stream has started, so
  // its frame and error are judged by this value, not by the live state.
  Future<void> _trackReadLoop(Object reader, int generation) {
    return runFrameReadLoop<Object>(
      read: () async {
        final readResult = await js_util.promiseToFuture<Object>(js_util.callMethod<Object>(reader, 'read', const []));
        return (done: js_util.getProperty<bool?>(readResult, 'done') ?? false, frame: js_util.getProperty<Object?>(readResult, 'value'));
      },
      isCurrent: () => generation == _streamGeneration,
      onFrame: (frame) async {
        if (_isProcessing || _presenter.isBusy) {
          js_util.callMethod<void>(frame, 'close', const []);
          return;
        }
        await _processVideoFrame(frame, generation);
      },
      close: (frame) => js_util.callMethod<void>(frame, 'close', const []),
      onError: _failStream,
    );
  }

  Future<void> _processVideoFrame(Object frame, int generation) async {
    if (!mounted || generation != _streamGeneration || _isProcessing) {
      js_util.callMethod<void>(frame, 'close', const []);
      return;
    }

    _isProcessing = true;
    try {
      final width = js_util.getProperty<num?>(frame, 'displayWidth')?.toInt() ?? js_util.getProperty<num?>(frame, 'codedWidth')?.toInt() ?? 0;
      final height = js_util.getProperty<num?>(frame, 'displayHeight')?.toInt() ?? js_util.getProperty<num?>(frame, 'codedHeight')?.toInt() ?? 0;
      if (width <= 0 || height <= 0) {
        return;
      }

      final targetSize = width * height * 4;
      final existing = _rgbaBuffer;
      if (existing == null || existing.lengthInBytes != targetSize) {
        _rgbaBuffer = Uint8List(targetSize);
      }

      var usedBgraCopyFormat = _copyToUseBgra;
      if (usedBgraCopyFormat) {
        try {
          await js_util.promiseToFuture<Object>(js_util.callMethod<Object>(frame, 'copyTo', [_rgbaBuffer!, _copyToOptionsBgra]));
        } catch (e) {
          _copyToUseBgra = false;
          usedBgraCopyFormat = false;
          if (!_loggedCopyToFormatFallback) {
            debugPrint('[YuvCameraPreviewWeb] copyTo(BGRA) unsupported, fallback to RGBA: $e');
            _loggedCopyToFormatFallback = true;
          }
          await js_util.promiseToFuture<Object>(js_util.callMethod<Object>(frame, 'copyTo', [_rgbaBuffer!, _copyToOptionsRgba]));
        }
      } else {
        await js_util.promiseToFuture<Object>(js_util.callMethod<Object>(frame, 'copyTo', [_rgbaBuffer!, _copyToOptionsRgba]));
      }
      if (!mounted || generation != _streamGeneration) {
        return;
      }
      var yuv = _reusableBgraFrame;
      if (yuv == null || yuv.width != width || yuv.height != height) {
        yuv = YuvImage.bgra(width, height);
        _reusableBgraFrame = yuv;
      }
      if (usedBgraCopyFormat) {
        yuv.yPlane.assignFrom(_rgbaBuffer!);
        yuv.markDirty();
      } else {
        yuv.applyRgbaBytes(_rgbaBuffer!);
      }

      // Converts before returning, so the next frame may reuse the instance.
      presentCameraFrame(_presenter, yuv, widget.transform);
    } finally {
      _isProcessing = false;
      js_util.callMethod<void>(frame, 'close', const []);
    }
  }

  void _scheduleNextTick() {
    if (_supportsVideoFrameCallback()) {
      if (!_loggedSchedulerPath) {
        debugPrint('[YuvCameraPreviewWeb] Using requestVideoFrameCallback scheduler');
        _loggedSchedulerPath = true;
      }
      _scheduleVideoFrameCallback();
      return;
    }
    if (!_loggedSchedulerPath) {
      debugPrint('[YuvCameraPreviewWeb] Using requestAnimationFrame scheduler');
      _loggedSchedulerPath = true;
    }
    _scheduleAnimationFrame();
  }

  bool _supportsVideoFrameCallback() {
    return js_util.hasProperty(_videoElement, 'requestVideoFrameCallback');
  }

  void _scheduleVideoFrameCallback() {
    if (!_running) {
      return;
    }

    void callback(num _, JSAny __) {
      _onFrameTick();
      _scheduleVideoFrameCallback();
    }

    final id = js_util.callMethod<Object>(_videoElement, 'requestVideoFrameCallback', [callback.toJS]);
    if (id is int) {
      _videoFrameRequestId = id;
    } else if (id is num) {
      _videoFrameRequestId = id.toInt();
    } else {
      _videoFrameRequestId = null;
    }
  }

  void _scheduleAnimationFrame() {
    if (!_running) {
      return;
    }

    _rafId = html.window.requestAnimationFrame((_) {
      _onFrameTick();
      _scheduleAnimationFrame();
    });
  }

  void _onFrameTick() {
    // If frame processing is still running, intentionally drop this frame.
    if (_isProcessing || _presenter.isBusy) {
      if (!_loggedFrameDrop) {
        debugPrint('[YuvCameraPreviewWeb] Dropping frames while busy');
        _loggedFrameDrop = true;
      }
      return;
    }
    _processFrame();
  }

  void _processFrame() {
    if (!mounted || !_running || _isProcessing) {
      return;
    }

    final width = _videoElement.videoWidth;
    final height = _videoElement.videoHeight;
    if (width <= 0 || height <= 0) {
      return;
    }

    final ctx = _canvasContext;
    if (ctx == null) {
      return;
    }

    _isProcessing = true;
    try {
      if (_canvasElement.width != width) {
        _canvasElement.width = width;
      }
      if (_canvasElement.height != height) {
        _canvasElement.height = height;
      }

      ctx.drawImageScaled(_videoElement, 0, 0, width.toDouble(), height.toDouble());
      final imageData = ctx.getImageData(0, 0, width, height);
      final rgba = imageData.data;
      final rgbaBytes = Uint8List.sublistView(rgba);

      final frame = YuvImage.bgra(width, height)..applyRgbaBytes(rgbaBytes);
      presentCameraFrame(_presenter, frame, widget.transform);
    } catch (e) {
      _failStream(e);
    } finally {
      _isProcessing = false;
    }
  }

  void _stopLoop() {
    _running = false;
    _streamGeneration++;
    _reusableBgraFrame = null;

    final reader = _trackReader;
    if (reader != null) {
      _trackReader = null;
      js_util.callMethod<Object?>(reader, 'cancel', const []);
    }

    final rafId = _rafId;
    if (rafId != null) {
      html.window.cancelAnimationFrame(rafId);
      _rafId = null;
    }

    final vfId = _videoFrameRequestId;
    if (vfId != null && js_util.hasProperty(_videoElement, 'cancelVideoFrameCallback')) {
      js_util.callMethod<void>(_videoElement, 'cancelVideoFrameCallback', [vfId]);
      _videoFrameRequestId = null;
    }
  }

  void _stopMediaTracks() {
    final stream = _mediaStream;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        track.stop();
      }
      _mediaStream = null;
    }
    _videoElement.srcObject = null;
  }

  String _facingModeFromLens(CameraLensDirection direction) {
    switch (direction) {
      case CameraLensDirection.front:
        return 'user';
      case CameraLensDirection.back:
        return 'environment';
      case CameraLensDirection.external:
        return 'environment';
    }
  }
}
