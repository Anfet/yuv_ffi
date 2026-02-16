import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_ffi_example/ext.dart';

part 'yuv_camera_preview_desk.dart';
part 'yuv_camera_preview_mobile.dart';

/// Android devices tend to mirror camera images horizontally.
///
/// This flag enables automatic horizontal flip for Android image stream path.
bool kYuvCameraPreviewFlipAndroid = true;

Widget buildYuvCameraPreview({
  Key? key,
  required CameraController cameraController,
  YuvImage Function(YuvImage image)? transform,
}) {
  if (Platform.isAndroid || Platform.isIOS) {
    return _YuvCameraPreviewMobile(
      key: key,
      cameraController: cameraController,
      transform: transform,
    );
  }

  if (Platform.isFuchsia || Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    return _YuvCameraPreviewDesktop(
      key: key,
      cameraController: cameraController,
      transform: transform,
    );
  }

  throw UnsupportedError('Platform not supported');
}
