part of 'yuv_camera_preview_io.dart';

class _YuvCameraPreviewMobile extends StatefulWidget {
  final CameraController cameraController;
  final YuvImage Function(YuvImage image)? transform;

  const _YuvCameraPreviewMobile({
    super.key,
    required this.cameraController,
    this.transform,
  });

  @override
  State<_YuvCameraPreviewMobile> createState() => _YuvCameraPreviewMobileState();
}

class _YuvCameraPreviewMobileState extends State<_YuvCameraPreviewMobile> {
  final StreamController<YuvImage?> streamController = StreamController<YuvImage?>.broadcast();
  bool isProcessing = false;

  @override
  void initState() {
    subscribeToImageStream();
    super.initState();
  }

  @override
  void didUpdateWidget(covariant _YuvCameraPreviewMobile oldWidget) {
    if (oldWidget.cameraController != widget.cameraController) {
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
    if (widget.cameraController.value.isStreamingImages) {
      widget.cameraController.stopImageStream().ignore();
    }

    streamController.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<YuvImage?>(
      stream: streamController.stream,
      initialData: null,
      builder: (context, snapshot) {
        final yuv = snapshot.data;
        return yuv != null
            ? AspectRatio(
                aspectRatio: yuv.width / yuv.height,
                child: YuvImageWidget(image: yuv),
              )
            : const SizedBox();
      },
    );
  }

  Future<void> subscribeToImageStream() async {
    if (!widget.cameraController.value.isInitialized) {
      throw ArgumentError('CameraController should be initialized');
    }

    if (widget.cameraController.value.isStreamingImages == true) {
      throw ArgumentError('CameraController should not be streaming images in initialization');
    }

    await widget.cameraController.startImageStream(onNewImageAvailable);
  }

  Future<void> onNewImageAvailable(CameraImage image) async {
    if (isProcessing) {
      return;
    }

    isProcessing = true;
    try {
      final rotation = YuvImageRotation.values.firstWhere(
        (e) => e.degrees == widget.cameraController.description.sensorOrientation.abs(),
      );
      var yuv = image.toYuvImage();
      if (Platform.isAndroid) {
        yuv = yuv.rotate(rotation.toZero());

        if (kYuvCameraPreviewFlipAndroid) yuv.flipHorizontally();
      }
      yuv = widget.transform?.call(yuv) ?? yuv;
      streamController.add(yuv);
    } catch (ex) {
      debugPrint('_YuvCameraPreviewMobile stream error: $ex');
    } finally {
      isProcessing = false;
    }
  }
}
