import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_ffi_example/ext.dart';
import 'package:yuv_ffi_example/yuv_image_widget.dart';

class YuvCameraWidget extends StatefulWidget {
  final CameraController cameraController;
  final YuvImage Function(YuvImage image)? transform;

  const YuvCameraWidget({
    super.key,
    required this.cameraController,
    this.transform,
  });

  @override
  State<YuvCameraWidget> createState() => _YuvCameraWidgetState();
}

class _YuvCameraWidgetState extends State<YuvCameraWidget> {
  final ValueNotifier<YuvImage?> cameraImageNotifier = ValueNotifier(null);
  final ValueNotifier<int> fpsNotifier = ValueNotifier(0);
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
      oldWidget.cameraController.stopImageStream();
      resubscribe();
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    if (widget.cameraController.value.isInitialized && widget.cameraController.value.isStreamingImages) {
      widget.cameraController.stopImageStream();
    }

    cameraImageNotifier.dispose();
    fpsNotifier.dispose();
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      return Stack(
        children: [
          Positioned.fill(
            child: ValueListenableBuilder(
              valueListenable: cameraImageNotifier,
              builder: (context, yuv, child) {
                final aspect = yuv == null ? 1.0 : yuv.width / yuv.height;
                return AspectRatio(
                  aspectRatio: aspect,
                  child: yuv != null ? YuvImageWidget(image: yuv) : Container(),
                );
              },
            ),
          ),
          Align(
            alignment: Alignment.bottomRight,
            child: ValueListenableBuilder(
              valueListenable: fpsNotifier,
              builder: (context, fps, child) {
                return Text('fps: $fps', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white));
              },
            ),
          ),
        ],
      );
    });
  }

  void resubscribe() {
    widget.cameraController.startImageStream(onNewImageAvailable);
    timer = Timer.periodic(
      Duration(seconds: 1),
      (timer) {
        fpsNotifier.value = fps;
        fps = 0;
      },
    );
  }

  Future onNewImageAvailable(CameraImage image) async {
    if (isProcessing) {
      return;
    }

    isProcessing = true;
    try {
      YuvImageRotation rotation = YuvImageRotation.values.firstWhere((e) => e.degrees == widget.cameraController.description.sensorOrientation.abs());
      var yuv = rotate(image.toYuvImage(), rotation.toZero());
      yuv = widget.transform?.call(yuv) ?? yuv;
      cameraImageNotifier.value = yuv;
      fps++;
    } finally {
      isProcessing = false;
    }
  }
}
