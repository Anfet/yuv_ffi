part of 'yuv_camera_preview_io.dart';

class _YuvCameraPreviewDesktop extends StatefulWidget {
  final YuvImage Function(YuvImage image)? transform;

  const _YuvCameraPreviewDesktop({
    super.key,
    this.transform,
  });

  @override
  State<_YuvCameraPreviewDesktop> createState() => _YuvCameraPreviewDesktopState();
}

class _YuvCameraPreviewDesktopState extends State<_YuvCameraPreviewDesktop> {
  static const Duration _desktopProcessingInterval = Duration(milliseconds: 120);
  final RTCVideoRenderer _renderer = RTCVideoRenderer();
  MediaStream? _mediaStream;
  MediaStreamTrack? _videoTrack;
  Timer? _captureTimer;
  YuvImage? _reusableBgraFrame;
  bool _rendererInitialized = false;
  bool _isProcessing = false;
  Object? _lastError;

  @override
  void initState() {
    super.initState();
    unawaited(_startStream());
  }

  @override
  void dispose() {
    _captureTimer?.cancel();
    _captureTimer = null;
    unawaited(_stopStream());
    unawaited(_renderer.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_lastError != null) {
      return Center(
        child: Text(
          'Desktop camera error: $_lastError',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.white),
        ),
      );
    }

    if (!_rendererInitialized) {
      return const SizedBox.shrink();
    }

    return RTCVideoView(_renderer, mirror: false);
  }

  Future<void> _startStream() async {
    try {
      if (!_rendererInitialized) {
        await _renderer.initialize();
        _rendererInitialized = true;
      }

      final constraints = <String, dynamic>{
        'audio': false,
        'video': <String, dynamic>{
          'width': <String, dynamic>{'ideal': 640},
          'height': <String, dynamic>{'ideal': 480},
          'frameRate': <String, dynamic>{'ideal': 15},
        },
      };

      _mediaStream = await navigator.mediaDevices.getUserMedia(constraints);
      final tracks = _mediaStream?.getVideoTracks() ?? const <MediaStreamTrack>[];
      if (tracks.isEmpty) {
        throw StateError('No video tracks available from WebRTC stream');
      }

      _renderer.srcObject = _mediaStream;
      _videoTrack = tracks.first;
      _captureTimer?.cancel();
      if (widget.transform != null) {
        _captureTimer = Timer.periodic(_desktopProcessingInterval, (_) => _captureNextFrame());
      }
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      _lastError = e;
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _stopStream() async {
    _captureTimer?.cancel();
    _captureTimer = null;
    _isProcessing = false;

    final stream = _mediaStream;
    _videoTrack = null;
    _mediaStream = null;
    _reusableBgraFrame = null;
    if (_rendererInitialized) {
      _renderer.srcObject = null;
    }

    if (stream == null) {
      return;
    }

    for (final track in stream.getTracks()) {
      await track.stop();
    }
    await stream.dispose();
  }

  Future<void> _captureNextFrame() async {
    if (!mounted || _isProcessing) {
      return;
    }
    final videoTrack = _videoTrack;
    if (videoTrack == null) {
      return;
    }

    _isProcessing = true;
    try {
      final encodedBuffer = await videoTrack.captureFrame();
      final encodedBytes = encodedBuffer.asUint8List();
      if (encodedBytes.isEmpty) {
        return;
      }

      final codec = await ui.instantiateImageCodec(encodedBytes);
      try {
        final frame = await codec.getNextFrame();
        final image = frame.image;
        try {
          final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
          if (rgba == null) {
            return;
          }
          final rgbaBytes = rgba.buffer.asUint8List();
          var yuv = _reusableBgraFrame;
          if (yuv == null || yuv.width != image.width || yuv.height != image.height) {
            yuv = YuvImage.bgra(image.width, image.height);
            _reusableBgraFrame = yuv;
          }
          yuv.fromRgba8888(rgbaBytes);
          widget.transform?.call(yuv);
        } finally {
          image.dispose();
        }
      } finally {
        codec.dispose();
      }
    } catch (e) {
      _lastError = e;
      _captureTimer?.cancel();
      _captureTimer = null;
      if (mounted) {
        setState(() {});
      }
    } finally {
      _isProcessing = false;
    }
  }
}
