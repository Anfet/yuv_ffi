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
  // the callback cannot be detached earlier; frames tagged with an older
  // generation belong to a stopped or replaced stream and are ignored.
  int streamGeneration = 0;

  @override
  void initState() {
    subscribeToImageStream();
    super.initState();
  }

  @override
  void didUpdateWidget(covariant _YuvCameraPreviewMobile oldWidget) {
    if (oldWidget.cameraController != widget.cameraController) {
      streamGeneration++;
      presenter.reset();
      var oldController = oldWidget.cameraController;
      if (oldController.value.isInitialized && oldController.value.isStreamingImages) {
        oldController.stopImageStream().ignore();
      }

      if (!mounted || !widget.cameraController.value.isInitialized) {
        return;
      }

      subscribeToImageStream().ignore();
    }

    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    streamGeneration++;
    if (widget.cameraController.value.isStreamingImages) {
      widget.cameraController.stopImageStream().ignore();
    }

    presenter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return YuvFrameView(presenter: presenter);
  }

  Future<void> subscribeToImageStream() async {
    if (!widget.cameraController.value.isInitialized) {
      throw ArgumentError('CameraController should be initialized');
    }

    if (widget.cameraController.value.isStreamingImages == true) {
      throw ArgumentError('CameraController should not be streaming images in initialization');
    }

    final generation = streamGeneration;
    await widget.cameraController.startImageStream((image) => onNewImageAvailable(image, generation));
  }

  void onNewImageAvailable(CameraImage image, int generation) {
    // Dropped before the planes are copied: while a frame is still decoding or
    // waiting to be drawn, converting this one would only queue work behind it.
    if (!mounted || generation != streamGeneration || presenter.isBusy) {
      return;
    }

    try {
      final rotation = YuvImageRotation.values.firstWhere((e) => e.degrees == widget.cameraController.description.sensorOrientation.abs());
      var yuv = image.toYuvImage();
      if (Platform.isAndroid) {
        yuv = yuv.applyRotation(rotation.toZero());

        if (kYuvCameraPreviewFlipAndroid) yuv.applyFlipHorizontal();
      }
      yuv = widget.transform?.call(yuv) ?? yuv;
      presenter.present(yuv);
    } catch (ex) {
      debugPrint('_YuvCameraPreviewMobile stream error: $ex');
    }
  }
}
