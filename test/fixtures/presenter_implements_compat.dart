import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

// The public surface implemented by consumers before lazy frames were added.
class _ExternalPresenter implements YuvFramePresenter {
  @override
  VoidCallback? get onFramePresented => null;

  @override
  bool get useShader => false;

  @override
  ui.Image? get image => null;

  @override
  bool get isBusy => false;

  @override
  bool get hasShader => false;

  @override
  bool get hasListeners => false;

  @override
  bool present(YuvImage frame, {YuvFrameOrientation orientation = YuvFrameOrientation.upright}) => false;

  @override
  void reset() {}

  @override
  void dispose() {}

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}

  @override
  void notifyListeners() {}
}

class _SubclassPresenter extends YuvFramePresenter {
  _SubclassPresenter() : super(useShader: false);
}

// Resolve the named extension solely through the public package import.
void main() {
  final YuvFramePresenter implemented = _ExternalPresenter();
  implemented.present;
  final YuvFramePresenter subclass = _SubclassPresenter();
  subclass.presentLazy(() => YuvImage.bgra(2, 2));
  subclass.dispose();
}
