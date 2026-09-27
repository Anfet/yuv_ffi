import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

import 'impl/yuv_camera_preview_web.dart' if (dart.library.io) 'impl/yuv_camera_preview_io.dart' as impl;

class YuvCameraPreview extends StatefulWidget {
  final CameraController? cameraController;

  /// Called for every frame the preview accepts; the returned image is what the
  /// preview shows, on mobile, web and desktop alike. Without [transform] the
  /// camera frame itself is shown. A frame that arrives while the previous one
  /// is still being decoded or drawn is dropped without this call, and so is
  /// every frame of a stream that was stopped or replaced.
  ///
  /// To capture what the preview shows, keep the frame this callback returns.
  /// Both frames are only valid during the call: the web preview reuses one
  /// instance and writes the next frame into it. Keep a frame beyond the call
  /// only through `copy()`.
  ///
  /// An error thrown here is reported through `FlutterError.reportError` and
  /// drops only that frame; the stream keeps running.
  final YuvImage Function(YuvImage image)? transform;
  final Widget? child;
  final bool showDebugInfo;

  const YuvCameraPreview({super.key, this.cameraController, this.transform, this.child, this.showDebugInfo = false});

  @override
  State<YuvCameraPreview> createState() => _YuvCameraPreviewState();
}

class _YuvCameraPreviewState extends State<YuvCameraPreview> {
  late final Timer fpsTimer;

  /// Frames drawn during the last second, or `null` while the platform
  /// preview has not reported a drawn frame yet.
  late final ValueNotifier<int?> fpsTicker = ValueNotifier(null);
  late final ValueNotifier<String> infoTicker = ValueNotifier('');
  int? presentedFrames;

  @override
  void initState() {
    fpsTimer = Timer.periodic(Duration(seconds: 1), onTimerTick);
    super.initState();
  }

  @override
  void dispose() {
    infoTicker.dispose();
    fpsTicker.dispose();
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
            onFramePresented: onFramePresented,
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
                return fps == null ? const SizedBox.shrink() : Text('$fps fps', style: baseStyle);
              },
            ),
          ),
        if (widget.child != null) Positioned.fill(child: widget.child!),
      ],
    );
  }

  void onTimerTick(Timer timer) {
    final frames = presentedFrames;
    if (frames == null) {
      return;
    }
    fpsTicker.value = frames;
    presentedFrames = 0;
  }

  // Counted on draw, not in infoTransformer: transform also runs for frames
  // that never reach the screen, so counting there reports the delivery rate.
  void onFramePresented() => presentedFrames = (presentedFrames ?? 0) + 1;

  YuvImage infoTransformer(YuvImage image) {
    infoTicker.value = image.toString();
    return widget.transform?.call(image) ?? image;
  }
}
