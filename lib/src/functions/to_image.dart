import 'dart:async';
import 'dart:ui' as ui;

import 'package:yuv_ffi/src/functions/to_bgra8888.dart';
import 'package:yuv_ffi/src/yuv/yuv_image.dart';

extension YuvImageEncoder on YuvImage {
  Future<ui.Image> toImage() async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(toBgra8888(), width, height, ui.PixelFormat.bgra8888, completer.complete);
    return completer.future;
  }
}
