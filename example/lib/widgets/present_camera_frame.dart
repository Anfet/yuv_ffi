import 'package:flutter/foundation.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Hands one accepted camera [frame] to [presenter]: the frame [transform]
/// returns when it is set, otherwise [frame] itself. Shared by the mobile, web
/// and desktop previews so the `transform` contract is the same everywhere.
///
/// An error thrown by [transform] or by the conversion in
/// [YuvFramePresenter.present] is reported through [FlutterError.reportError]
/// and drops only this frame: the presenter stays free and the stream keeps
/// running. It is not a camera error and does not stop the preview.
///
/// Returns whether the frame was taken by [presenter].
bool presentCameraFrame(YuvFramePresenter presenter, YuvImage frame, YuvImage Function(YuvImage image)? transform) {
  try {
    return presenter.present(transform?.call(frame) ?? frame);
  } catch (error, stack) {
    FlutterError.reportError(
      FlutterErrorDetails(exception: error, stack: stack, library: 'yuv_ffi_example', context: ErrorDescription('transforming a camera frame')),
    );
    return false;
  }
}
