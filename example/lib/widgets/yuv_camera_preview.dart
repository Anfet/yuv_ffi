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

  /// Called once the frame returned by the latest [transform] call has been
  /// drawn. [transform] runs only when no earlier frame is in flight, so each
  /// call answers the [transform] call right before it. A frame dropped after
  /// [transform] — its stream stopped or replaced, its decode failed — is
  /// never reported here, and the next [transform] call starts a new frame.
  ///
  /// Together with [transform] this tells which frame the user actually saw,
  /// e.g. to capture it: keep a `copy()` in [transform], confirm it here.
  final VoidCallback? onFramePresented;

  /// Called when the preview stops showing frames of its stream while it
  /// stays on screen: the controller was replaced, or a camera error ended
  /// or prevented the stream. A frame in flight at that moment is dropped and
  /// never reaches [onFramePresented]. Not called on dispose.
  ///
  /// May be called while the widget tree is being built, so it must not call
  /// `setState` synchronously.
  final VoidCallback? onStreamStopped;
  final Widget? child;
  final bool showDebugInfo;
  final bool flipAndroidCameraHorizontally;

  const YuvCameraPreview({
    super.key,
    this.cameraController,
    this.transform,
    this.onFramePresented,
    this.onStreamStopped,
    this.child,
    this.showDebugInfo = false,
    this.flipAndroidCameraHorizontally = false,
  });

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
            flipAndroidCameraHorizontally: widget.flipAndroidCameraHorizontally,
            transform: infoTransformer,
            onFramePresented: onFramePresented,
            onStreamStopped: widget.onStreamStopped,
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
  void onFramePresented() {
    presentedFrames = (presentedFrames ?? 0) + 1;
    widget.onFramePresented?.call();
  }

  YuvImage infoTransformer(YuvImage image) {
    infoTicker.value = image.toString();
    return widget.transform?.call(image) ?? image;
  }
}
