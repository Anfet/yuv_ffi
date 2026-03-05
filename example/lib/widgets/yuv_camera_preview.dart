import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

import 'impl/yuv_camera_preview_web.dart' if (dart.library.io) 'impl/yuv_camera_preview_io.dart' as impl;

class YuvCameraPreview extends StatefulWidget {
  final CameraController? cameraController;
  final YuvImage Function(YuvImage image)? transform;
  final Widget? child;
  final bool showDebugInfo;

  const YuvCameraPreview({
    super.key,
    this.cameraController,
    this.transform,
    this.child,
    this.showDebugInfo = false,
  });

  @override
  State<YuvCameraPreview> createState() => _YuvCameraPreviewState();
}

class _YuvCameraPreviewState extends State<YuvCameraPreview> {
  late final Timer fpsTimer;
  late final ValueNotifier<int> fpsTicker = ValueNotifier(0);
  late final ValueNotifier<String> infoTicker = ValueNotifier('');
  int dynamicFps = 0;

  @override
  void initState() {
    fpsTimer = Timer.periodic(Duration(seconds: 1), onTimerTick);
    super.initState();
  }

  @override
  void dispose() {
    infoTicker.dispose();
    fpsTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var baseStyle = (Theme.of(context).textTheme.labelSmall ?? const TextStyle(fontSize: 11)).copyWith(
      // color: Colors.cyanAccent,
      foreground: Paint()
        ..blendMode = BlendMode.difference
        ..color = Colors.white,
    );
    return Stack(
      clipBehavior: Clip.hardEdge,
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: impl.buildYuvCameraPreview(
            key: widget.key,
            cameraController: widget.cameraController,
            transform: infoTransformer,
          ),
        ),
        if (widget.showDebugInfo)
          Positioned(
            bottom: 4,
            left: 4,
            child: ValueListenableBuilder(
              valueListenable: infoTicker,
              builder: (context, info, _) {
                return Text(info, style: baseStyle);
              },
            ),
          ),
        if (widget.showDebugInfo)
          Positioned(
            bottom: 4,
            right: 4,
            child: ValueListenableBuilder(
              valueListenable: fpsTicker,
              builder: (context, fps, _) {
                return Text('$fps fps', style: baseStyle);
              },
            ),
          ),
        if (widget.child != null) Positioned.fill(child: widget.child!),
      ],
    );
  }

  void onTimerTick(Timer timer) {
    fpsTicker.value = dynamicFps;
    dynamicFps = 0;
  }

  YuvImage infoTransformer(YuvImage image) {
    dynamicFps++;
    infoTicker.value = image.toString();
    return widget.transform?.call(image) ?? image;
  }
}
