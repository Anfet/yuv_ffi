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

/// [onFramePresented] fires once per frame drawn from the image stream.
/// [cameraController] must be initialized; desktop streams it through
/// `camera_desktop`.
Widget buildYuvCameraPreview({
  Key? key,
  CameraController? cameraController,
  YuvImage Function(YuvImage image)? transform,
  VoidCallback? onFramePresented,
}) {
  if (cameraController == null) {
    throw ArgumentError('CameraController is required on mobile and desktop platforms');
  }

  switch (_previewPlatform()) {
    case TargetPlatform.android || TargetPlatform.iOS:
      return _YuvCameraPreviewMobile(key: key, cameraController: cameraController, transform: transform, onFramePresented: onFramePresented);
    case TargetPlatform.linux || TargetPlatform.macOS || TargetPlatform.windows:
      return _YuvCameraPreviewDesktop(key: key, cameraController: cameraController, transform: transform, onFramePresented: onFramePresented);
    case _:
      throw UnsupportedError('Platform not supported');
  }
}

// The host decides, not defaultTargetPlatform, which reports Android in every
// `flutter test` process. A debug override set by a test wins, so the mobile
// path, whose CameraController.startImageStream asserts on that override, can
// run on a desktop test host; release builds ignore it like Flutter does.
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
