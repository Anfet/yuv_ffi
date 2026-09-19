import 'dart:ffi';

import 'package:yuv_ffi/src/functions/bindings/yuv_ffi_bingings.dart';
import 'package:yuv_ffi/src/yuv/impl/io/defs/native_allocator.dart';
import 'package:yuv_ffi/src/yuv/yuv.dart';

/// Dart holder for ffi pointer classes
/// must be disposed to avoid memory leaks
class YUVDefClass {
  late final Pointer<YUVDef> pointer;

  /// Allocates the struct and its plane buffers transactionally: if any
  /// allocation throws, every pointer created earlier in this constructor is
  /// released before the original exception propagates.
  YUVDefClass._(YuvImage image) {
    final allocator = NativeAllocator.instance;
    final Pointer<YUVDef> struct = allocator.allocate<YUVDef>(sizeOf<YUVDef>());
    Pointer<Uint8> yPtr = nullptr;
    Pointer<Uint8> uPtr = nullptr;
    Pointer<Uint8> vPtr = nullptr;

    try {
      struct.ref.width = image.width;
      struct.ref.height = image.height;
      struct.ref.yRowStride = image.yPlane.rowStride;
      struct.ref.yPixelStride = image.yPlane.pixelStride;
      struct.ref.uvRowStride = image.u?.rowStride ?? 1;
      struct.ref.uvPixelStride = image.u?.pixelStride ?? 1;

      yPtr = allocator.allocate<Uint8>(image.yPlane.bytes.length);
      struct.ref.y = yPtr;

      if (image.u != null) {
        uPtr = allocator.allocate<Uint8>(image.uPlane.bytes.length);
        struct.ref.u = uPtr;
      }
      if (image.v != null) {
        vPtr = allocator.allocate<Uint8>(image.vPlane.bytes.length);
        struct.ref.v = vPtr;
      }
    } catch (_) {
      if (vPtr != nullptr) allocator.free(vPtr);
      if (uPtr != nullptr) allocator.free(uPtr);
      if (yPtr != nullptr) allocator.free(yPtr);
      allocator.free(struct);
      rethrow;
    }

    pointer = struct;
  }

  factory YUVDefClass.template(YuvImage image) => YUVDefClass._(image);

  factory YUVDefClass(YuvImage image) {
    final def = YUVDefClass._(image);
    try {
      def.pointer.ref.y.asTypedList(image.yPlane.bytes.length).setAll(0, image.yPlane.bytes);
      if (def.pointer.ref.u != nullptr) def.pointer.ref.u.asTypedList(image.uPlane.bytes.length).setAll(0, image.uPlane.bytes);
      if (def.pointer.ref.v != nullptr) def.pointer.ref.v.asTypedList(image.vPlane.bytes.length).setAll(0, image.vPlane.bytes);
    } catch (_) {
      def.dispose();
      rethrow;
    }
    return def;
  }

  void dispose() {
    final allocator = NativeAllocator.instance;
    allocator.free(pointer.ref.y);
    if (pointer.ref.u != nullptr) allocator.free(pointer.ref.u);
    if (pointer.ref.v != nullptr) allocator.free(pointer.ref.v);
    allocator.free(pointer);
  }
}
