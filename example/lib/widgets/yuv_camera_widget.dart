import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_ffi_example/ext.dart';

class YuvCameraWidget extends StatefulWidget {
  final CameraController cameraController;
  final YuvImage Function(YuvImage image)? transform;
  final ValueChanged<int>? fpsChanged;

  const YuvCameraWidget({super.key, required this.cameraController, this.transform, this.fpsChanged});

  @override
  State<YuvCameraWidget> createState() => _YuvCameraWidgetState();
}

class _YuvCameraWidgetState extends State<YuvCameraWidget> {
  final StreamController<YuvImage?> streamController = StreamController.broadcast();
  bool isProcessing = false;
  int fps = 0;
  Timer? timer;

  @override
  void initState() {
    resubscribe();
    super.initState();
  }

  @override
  void didUpdateWidget(covariant YuvCameraWidget oldWidget) {
    if (oldWidget.cameraController != widget.cameraController &&
        oldWidget.cameraController.value.isInitialized &&
        oldWidget.cameraController.value.isStreamingImages) {
      oldWidget.cameraController.stopImageStream().then((value) => resubscribe());
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    if (widget.cameraController.value.isInitialized && widget.cameraController.value.isStreamingImages) {
      widget.cameraController.stopImageStream();
    }

    streamController.close();
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: streamController.stream,
      initialData: null,
      builder: (context, snapshot) {
        final yuv = snapshot.data;
        return yuv != null
            ? AspectRatio(
                aspectRatio: yuv.width / yuv.height,
                child: YuvImageWidget(image: yuv),
              )
            : SizedBox();
      },
    );
  }

  Future resubscribe() async {
    await widget.cameraController.startImageStream(onNewImageAvailable);
    timer = Timer.periodic(Duration(seconds: 1), (timer) {
      widget.fpsChanged?.call(fps);
      fps = 0;
    });
  }

  Future onNewImageAvailable(CameraImage image) async {
    if (isProcessing) {
      return;
    }

    isProcessing = true;
    fps++;
    try {
      YuvImageRotation rotation = YuvImageRotation.values.firstWhere((e) => e.degrees == widget.cameraController.description.sensorOrientation.abs());
      var yuv = image.toYuvImage(); //rotate(image.toYuvImage(), rotation.toZero());
      yuv = widget.transform?.call(yuv) ?? yuv;
      streamController.add(yuv);
    } catch (ex) {
      print(ex);
    } finally {
      isProcessing = false;
    }
  }
}
