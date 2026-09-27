part of 'yuv_camera_preview_io.dart';

/// Desktop (Windows/macOS/Linux) preview fed by the `camera_desktop` image
/// stream of [cameraController].
///
/// `camera` 0.11.0+2 guards `CameraController.startImageStream` and
/// `stopImageStream` with an Android/iOS-only assert that fires in debug and
/// profile builds, while their bodies only subscribe to and cancel
/// `CameraPlatform.instance.onStreamedFrameAvailable(cameraId)`. The preview
/// makes that subscription itself and stops the stream by cancelling it;
/// `camera_desktop` sends the native stop from the stream's `onCancel`. The
/// controller still owns `initialize` and `dispose`, and its
/// `isStreamingImages` stays `false` on desktop.
///
/// Frames are BGRA8888 with a single plane and are not mirrored, also for a
/// front camera on Windows; they are shown and captured as delivered.
class _YuvCameraPreviewDesktop extends StatefulWidget {
  final CameraController cameraController;
  final YuvImage Function(YuvImage image)? transform;
  final VoidCallback? onFramePresented;

  const _YuvCameraPreviewDesktop({super.key, required this.cameraController, this.transform, this.onFramePresented});

  @override
  State<_YuvCameraPreviewDesktop> createState() => _YuvCameraPreviewDesktopState();
}

class _YuvCameraPreviewDesktopState extends State<_YuvCameraPreviewDesktop> {
  late final YuvFramePresenter presenter = YuvFramePresenter(onFramePresented: () => widget.onFramePresented?.call());

  // Bumped on every stop; a subscription, a pending start or a stream error
  // tagged with an older value belongs to a stopped or replaced stream.
  int streamGeneration = 0;
  StreamSubscription<CameraImageData>? subscription;

  // camera_desktop keeps one active stream per camera and stops the native
  // one asynchronously in onCancel, so a restart on the same camera waits for
  // the previous stop instead of racing it.
  Future<void> previousStop = Future<void>.value();
  Object? lastError;

  @override
  void initState() {
    super.initState();
    startStream().ignore();
  }

  @override
  void didUpdateWidget(covariant _YuvCameraPreviewDesktop oldWidget) {
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
          'Desktop camera error: $lastError',
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

    subscription = CameraPlatform.instance
        .onStreamedFrameAvailable(controller.cameraId)
        .listen((data) => onFrameAvailable(data, generation), onError: (Object error) => onStreamError(error, generation));
  }

  void stopStream() {
    streamGeneration++;
    final current = subscription;
    subscription = null;
    if (current != null) {
      previousStop = current.cancel().catchError((Object error) => debugPrint('_YuvCameraPreviewDesktop stop error: $error'));
    }
  }

  void onFrameAvailable(CameraImageData data, int generation) {
    // Dropped before the plane is copied: while a frame is still decoding or
    // waiting to be drawn, converting this one would only queue work behind it.
    if (!mounted || generation != streamGeneration || presenter.isBusy) {
      return;
    }

    final YuvImage frame;
    try {
      frame = CameraImage.fromPlatformInterface(data).toYuvImage();
    } catch (ex) {
      debugPrint('_YuvCameraPreviewDesktop stream error: $ex');
      return;
    }

    presentCameraFrame(presenter, frame, widget.transform);
  }

  void onStreamError(Object error, int generation) {
    if (!mounted || generation != streamGeneration) {
      return;
    }
    // Stopped rather than left running behind the error text: the camera would
    // stay on and keep delivering frames nobody can see.
    stopStream();
    presenter.reset();
    setState(() => lastError = error);
  }
}
