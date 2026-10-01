part of 'yuv_camera_preview_io.dart';

/// Android/iOS preview fed by the image stream of [cameraController].
///
/// `camera` 0.11.0+2 `CameraController.startImageStream` only subscribes to
/// `CameraPlatform.instance.onStreamedFrameAvailable(cameraId)`, and does so
/// without `onError`: a camera error after the start would reach the zone as
/// an uncaught error and leave the stream running. The preview makes that
/// subscription itself, as the desktop preview does, stops the stream on an
/// error by cancelling it, and shows the error. The controller still owns
/// `initialize` and `dispose`; its `isStreamingImages` stays `false`.
class _YuvCameraPreviewMobile extends StatefulWidget {
  final CameraController cameraController;
  final bool flipAndroidCameraHorizontally;
  final YuvImage Function(YuvImage image)? transform;
  final VoidCallback? onFramePresented;
  final VoidCallback? onStreamStopped;

  const _YuvCameraPreviewMobile({
    super.key,
    required this.cameraController,
    required this.flipAndroidCameraHorizontally,
    this.transform,
    this.onFramePresented,
    this.onStreamStopped,
  });

  @override
  State<_YuvCameraPreviewMobile> createState() => _YuvCameraPreviewMobileState();
}

class _YuvCameraPreviewMobileState extends State<_YuvCameraPreviewMobile> {
  late final YuvFramePresenter presenter = YuvFramePresenter(onFramePresented: () => widget.onFramePresented?.call());

  // Bumped on every stop; frames, a pending start and a stream error tagged
  // with an older value belong to a stopped or replaced stream.
  int streamGeneration = 0;
  StreamSubscription<CameraImageData>? subscription;

  // The platform keeps one frame stream per camera and stops it
  // asynchronously in onCancel, so a restart waits for the previous stop
  // instead of racing it with a second listener on the same camera.
  Future<void> previousStop = Future<void>.value();
  Object? lastError;

  @override
  void initState() {
    super.initState();
    startStream().ignore();
  }

  @override
  void didUpdateWidget(covariant _YuvCameraPreviewMobile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cameraController != widget.cameraController) {
      stopStream();
      presenter.reset();
      lastError = null;
      widget.onStreamStopped?.call();
      startStream().ignore();
    }
  }

  @override
  void dispose() {
    stopStream();
    presenter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (lastError != null) {
      return Center(
        child: Text(
          'Camera error: $lastError',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: Colors.white),
        ),
      );
    }

    return YuvFrameView(presenter: presenter);
  }

  Future<void> startStream() async {
    final generation = streamGeneration;
    final controller = widget.cameraController;
    await previousStop;
    if (!mounted || generation != streamGeneration) {
      return;
    }

    if (!controller.value.isInitialized) {
      onStreamError(StateError('CameraController should be initialized'), generation);
      return;
    }

    try {
      subscription = CameraPlatform.instance
          .onStreamedFrameAvailable(controller.cameraId)
          .listen(
            (data) => onNewImageAvailable(CameraImage.fromPlatformInterface(data), generation),
            onError: (Object error) => onStreamError(error, generation),
          );
    } catch (error) {
      onStreamError(error, generation);
    }
  }

  void stopStream() {
    streamGeneration++;
    final current = subscription;
    subscription = null;
    // Cancelled synchronously: the owner may dispose the controller right
    // after this preview (CameraScreen does), and the stop is already issued.
    if (current != null) {
      previousStop = current.cancel().catchError((Object error) => debugPrint('_YuvCameraPreviewMobile stop error: $error'));
    }
  }

  void onNewImageAvailable(CameraImage image, int generation) {
    // Dropped before the planes are copied: while a frame is still decoding or
    // waiting to be drawn, converting this one would only queue work behind it.
    if (!mounted || generation != streamGeneration) {
      return;
    }
    if (presenter.isBusy) {
      return;
    }

    final YuvImage frame;
    try {
      final rotation = YuvImageRotation.values.firstWhere((e) => e.degrees == widget.cameraController.description.sensorOrientation.abs());
      var yuv = image.toYuvImage();
      if (_previewPlatform() == TargetPlatform.android) {
        yuv = yuv.applyRotation(rotation);

        if (widget.flipAndroidCameraHorizontally) yuv.applyFlipHorizontal();
      }
      frame = yuv;
    } catch (ex) {
      debugPrint('_YuvCameraPreviewMobile stream error: $ex');
      return;
    }

    presentCameraFrame(presenter, frame, widget.transform);
  }

  // A camera error of the current stream, at start or after it: shown instead
  // of the preview, with the stream stopped rather than left running behind it.
  void onStreamError(Object error, int generation) {
    if (!mounted || generation != streamGeneration) {
      debugPrint('_YuvCameraPreviewMobile error of a stopped stream: $error');
      return;
    }
    stopStream();
    presenter.reset();
    setState(() => lastError = error);
    widget.onStreamStopped?.call();
  }
}
