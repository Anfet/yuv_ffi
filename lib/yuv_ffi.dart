// Public API for `package:yuv_ffi`.
//
// Exposes image model/types, Flutter widget helpers, and package
// initialization entrypoint.
export 'src/yuv/yuv.dart';
// `revision` and `markDirty()` are extension members, so this library has to be
// exported for them to be visible. They are deliberately not interface members:
// adding required members to `YuvImage` would break every external
// `implements YuvImage` on a patch update.
export 'src/yuv/shared/yuv_revision.dart' show YuvImageInvalidation;
export 'src/yuv/shared/yuv_plane.dart';
export 'src/yuv/shared/yuv_image_rotation.dart';
export 'src/yuv/shared/yuv_file_format.dart';
export 'src/yuv/shared/yuv_operation.dart' show YuvOperation;
export 'src/yuv/shared/yuv_pixel_format.dart' show YuvPixelFormat;
export 'src/widgets/yuv_image_widget.dart';
export 'src/yuv_capabilities.dart' show YuvCapabilities;
export 'src/yuv_ffi_initializer.dart';
