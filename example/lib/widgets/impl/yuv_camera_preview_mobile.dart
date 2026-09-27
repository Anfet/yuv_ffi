part of 'yuv_camera_preview_io.dart';

class _YuvCameraPreviewMobile extends StatefulWidget {
  final CameraController cameraController;
  final YuvImage Function(YuvImage image)? transform;
  final VoidCallback? onFramePresented;

  const _YuvCameraPreviewMobile({super.key, required this.cameraController, this.transform, this.onFramePresented});

  @override
  State<_YuvCameraPreviewMobile> createState() => _YuvCameraPreviewMobileState();
}

class _YuvCameraPreviewMobileState extends State<_YuvCameraPreviewMobile> {
  late final YuvFramePresenter presenter = YuvFramePresenter(onFramePresented: () => widget.onFramePresented?.call());

  // The camera keeps delivering frames until stopImageStream completes, and
  // the callback cannot be detached earlier; frames, a pending start and a
  // start error tagged with an older generation belong to a stopped or
  // replaced stream and are ignored.
  int streamGeneration = 0;

  // The controller whose image stream this preview started, and that start,
  // completing with whether it succeeded. Tracked here rather than read from
  // isStreamingImages, which a start still in progress does not report yet.
  CameraController? streamingController;
  Future<bool> streamStarted = Future.value(false);

  // The platform keeps one frame stream per camera and stops it
  // asynchronously, so a restart waits for the previous stop instead of
  // racing it with a second listener on the same camera.
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
      setState(() => lastError = StateError('CameraController should be initialized'));
      return;
    }

    streamingController = controller;
    streamStarted = controller
        .startImageStream((image) => onNewImageAvailable(image, generation))
        .then(
          (_) => true,
          onError: (Object error) {
            onStartError(error, generation);
            return false;
          },
        );
  }

  void stopStream() {
    streamGeneration++;
    final controller = streamingController;
    if (controller == null) {
      return;
    }

    streamingController = null;
    // Stopped right away once the start went through: the owner may dispose
    // the controller right after this preview (CameraScreen does), and
    // stopImageStream refuses a disposed controller. A start still in
    // progress is stopped when it completes.
    final stop = controller.value.isStreamingImages
        ? controller.stopImageStream()
        : streamStarted.then<void>((started) async {
            if (started) {
              await controller.stopImageStream();
            }
          });
    previousStop = stop.catchError((Object error) => debugPrint('_YuvCameraPreviewMobile stop error: $error'));
  }

  void onNewImageAvailable(CameraImage image, int generation) {
    // Dropped before the planes are copied: while a frame is still decoding or
    // waiting to be drawn, converting this one would only queue work behind it.
    if (!mounted || generation != streamGeneration || presenter.isBusy) {
      return;
    }

    final YuvImage frame;
    try {
      final rotation = YuvImageRotation.values.firstWhere((e) => e.degrees == widget.cameraController.description.sensorOrientation.abs());
      var yuv = image.toYuvImage();
      if (_previewPlatform() == TargetPlatform.android) {
        yuv = yuv.applyRotation(rotation.toZero());

        if (kYuvCameraPreviewFlipAndroid) yuv.applyFlipHorizontal();
      }
      frame = yuv;
    } catch (ex) {
      debugPrint('_YuvCameraPreviewMobile stream error: $ex');
      return;
    }

    presentCameraFrame(presenter, frame, widget.transform);
  }

  void onStartError(Object error, int generation) {
    if (!mounted || generation != streamGeneration) {
      debugPrint('_YuvCameraPreviewMobile start error of a stopped stream: $error');
      return;
    }
    streamingController = null;
    setState(() => lastError = error);
  }
}
