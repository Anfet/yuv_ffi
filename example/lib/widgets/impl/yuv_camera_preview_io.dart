import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_ffi_example/ext.dart';
import 'package:yuv_ffi_example/widgets/present_camera_frame.dart';

part 'yuv_camera_preview_desk.dart';
part 'yuv_camera_preview_mobile.dart';

/// Android devices tend to mirror camera images horizontally.
///
/// This flag enables automatic horizontal flip for Android image stream path.
bool kYuvCameraPreviewFlipAndroid = true;

/// A single lifecycle event of the mobile preview's one platform subscription,
/// for [debugYuvCameraPreviewMobileEvent].
enum DebugYuvCameraPreviewMobileEventKind {
  /// A platform frame reached `onNewImageAvailable`, before any check or
  /// conversion runs on it.
  delivered,

  /// [delivered] was dropped before `transform`: [reason] is `'stale'`
  /// (unmounted or a stopped/replaced generation) or `'busy'`
  /// ([YuvFramePresenter.isBusy]).
  droppedBeforeTransform,

  /// [delivered] finished `CameraImage.toYuvImage()` (plane copy from
  /// platform data), before any rotation/flip.
  yuvImageReady,

  /// [yuvImageReady] finished `applyRotation`, before `applyFlipHorizontal`.
  rotationApplied,

  /// [delivered] finished `toYuvImage()`/rotation and is about to reach
  /// `transform` through `presentCameraFrame`.
  acceptedForTransform,
}

/// Measurement hook: sink for [DebugYuvCameraPreviewMobileEventKind]
/// events raised by the mobile preview's single platform subscription, with a
/// monotonic timestamp ([debugYuvCameraPreviewMobileClock]'s elapsed time) and
/// no per-frame allocation beyond the event itself. `null` by default, so it
/// costs nothing outside a measurement run; set and cleared only by an
/// `integration_test`, never read or written by production code.
void Function(DebugYuvCameraPreviewMobileEventKind kind, Duration at, {String? reason})? debugYuvCameraPreviewMobileEvent;

/// Shared monotonic clock for [debugYuvCameraPreviewMobileEvent] timestamps,
/// so events raised inside the mobile preview and events the measuring test
/// raises itself (delivered-to-transform vs. transform-to-presented) share
/// one time base. Not started by production code; a measurement run starts
/// it once before creating the preview.
final Stopwatch debugYuvCameraPreviewMobileClock = Stopwatch();

/// [onFramePresented] fires once per frame drawn from the image stream.
/// [onStreamStopped] fires when the stream stops while the preview stays on
/// screen: the controller was replaced or a camera error ended the stream.
/// [cameraController] must be initialized; desktop streams it through
/// `camera_desktop`.
Widget buildYuvCameraPreview({
  Key? key,
  CameraController? cameraController,
  YuvImage Function(YuvImage image)? transform,
  VoidCallback? onFramePresented,
  VoidCallback? onStreamStopped,
}) {
  if (cameraController == null) {
    throw ArgumentError('CameraController is required on mobile and desktop platforms');
  }

  switch (_previewPlatform()) {
    case TargetPlatform.android || TargetPlatform.iOS:
      return _YuvCameraPreviewMobile(
        key: key,
        cameraController: cameraController,
        transform: transform,
        onFramePresented: onFramePresented,
        onStreamStopped: onStreamStopped,
      );
    case TargetPlatform.linux || TargetPlatform.macOS || TargetPlatform.windows:
      return _YuvCameraPreviewDesktop(
        key: key,
        cameraController: cameraController,
        transform: transform,
        onFramePresented: onFramePresented,
        onStreamStopped: onStreamStopped,
      );
    case _:
      throw UnsupportedError('Platform not supported');
  }
}

// The host decides, not defaultTargetPlatform, which reports Android in every
// `flutter test` process. A debug override set by a test wins, so the mobile
// path, whose Android rotation branch reads this choice, can run on a desktop
// test host; release builds ignore it like Flutter does.
TargetPlatform? _previewPlatform() {
  final override = debugDefaultTargetPlatformOverride;
  if (kDebugMode && override != null) {
    return override;
  }
  return switch (Platform.operatingSystem) {
    'android' => TargetPlatform.android,
    'ios' => TargetPlatform.iOS,
    'linux' => TargetPlatform.linux,
    'macos' => TargetPlatform.macOS,
    'windows' => TargetPlatform.windows,
    _ => null,
  };
}
