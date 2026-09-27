import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';

import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_ffi_example/ext.dart';

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

  if (Platform.isAndroid || Platform.isIOS) {
    return _YuvCameraPreviewMobile(key: key, cameraController: cameraController, transform: transform, onFramePresented: onFramePresented);
  }

  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    return _YuvCameraPreviewDesktop(key: key, cameraController: cameraController, transform: transform, onFramePresented: onFramePresented);
  }

  throw UnsupportedError('Platform not supported');
}
