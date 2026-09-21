import 'dart:async';
import 'dart:ffi';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:yuv_ffi/src/loader/loader.dart';
import 'package:yuv_ffi/src/yuv/impl/io/defs/native_allocator.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_file_format.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_geometry.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_image_rotation.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_image_state.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_plane.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_revision.dart';
import 'package:yuv_ffi/src/yuv/yuv.dart';

import 'defs/yuv_def.dart';

/// Native backend implementation, dispatching to the `yuv_ffi` C library.
///
/// Format, geometry, plane, copy and serialization state lives in the shared
/// [YuvImageState] this holds by composition (YUV-28); what remains here is the
/// FFI dispatch itself.
class YuvImageImpl implements YuvImage, YuvRevisionAware {
  final YuvImageState _state;

  @override
  int get internalRevision => _state.revision;

  @override
  void bumpInternalRevision() => _state.bumpRevision();

  @override
  YuvFileFormat get format => _state.format;

  @override
  int get width => _state.width;

  @override
  int get height => _state.height;

  @override
  List<YuvPlane> get planes => _state.planes;

  @override
  YuvPlane get yPlane => _state.yPlane;

  @override
  YuvPlane get uPlane => _state.uPlane;

  @override
  YuvPlane get vPlane => _state.vPlane;

  @override
  YuvPlane get y => _state.yPlane;

  @override
  YuvPlane? get u => _state.u;

  @override
  YuvPlane? get v => _state.v;

  @override
  ui.Size get size => _state.size;

  // I420 stores U and V as separate single-byte-per-sample planes, so the
  // default pixelStride is 1, unlike NV21's interleaved (U, V) pairs.
  YuvImageImpl.i420(int width, int height, {int yPixelStride = 1, int uvPixelStride = 1, Iterable<YuvPlane>? planes})
      : this(YuvFileFormat.i420, width, height, yPixelStride: yPixelStride, uvPixelStride: uvPixelStride, planes: planes);

  YuvImageImpl.nv21(int width, int height, {int yPixelStride = 1, int uvPixelStride = 2, Iterable<YuvPlane>? planes})
      : this(YuvFileFormat.nv21, width, height, yPixelStride: yPixelStride, uvPixelStride: uvPixelStride, planes: planes);

  /// Creates a BGRA image, optionally adopting a caller-supplied plane.
  ///
  /// A valid padded plane keeps its `rowStride` and `pixelStride`: the plane is
  /// deep-copied as given rather than repacked at construction time. Producing
  /// a tight buffer is the job of [toBgra8888], not a reason to discard the
  /// caller's layout. This matches the generic
  /// `YuvImage(YuvFileFormat.bgra8888, ...)` constructor, so both entry points
  /// share one validation and copy contract.
  YuvImageImpl.bgra(int width, int height, {Iterable<YuvPlane>? planes})
      : this(YuvFileFormat.bgra8888, width, height, yPixelStride: 4, planes: planes);

  YuvImageImpl(YuvFileFormat format, int width, int height, {int yPixelStride = 1, int uvPixelStride = 1, Iterable<YuvPlane>? planes})
      : _state = YuvImageState(format, width, height, yPixelStride: yPixelStride, uvPixelStride: uvPixelStride, planes: planes);

  @override
  Uint8List getBytes() => _state.getBytes();

  @override
  YuvImage copy({bool blank = false}) => YuvImageImpl(
        format,
        width,
        height,
        planes: _state.copiedPlanes(blank: blank),
        yPixelStride: _state.yPixelStride,
        uvPixelStride: _state.uvPixelStride,
      );

  @override
  Future save(Sink<List<int>> sink) async {
    sink.add(_state.encode());
  }

  @override
  Future<void> load(Stream<List<int>> stream) => _state.decodeAndReplace(stream);

  @override
  String toString() {
    return '${format.name}, $width:$height / ${planes.length}';
  }

  @override
  YuvImage blackwhite() {
    final def = YUVDefClass(this);
    try {
      switch (format) {
        case YuvFileFormat.i420:
          ffiBingings.yuv420_blackwhite(def.pointer);
          yPlane.assignFromPtr(def.pointer.ref.y);
          uPlane.assignFromPtr(def.pointer.ref.u);
          vPlane.assignFromPtr(def.pointer.ref.v);
          break;
        case YuvFileFormat.nv21:
          ffiBingings.nv21_blackwhite(def.pointer);
          yPlane.assignFromPtr(def.pointer.ref.y);
          uPlane.assignFromPtr(def.pointer.ref.u);
          break;
        case YuvFileFormat.bgra8888:
          ffiBingings.bgra8888_blackwhite(def.pointer);
          yPlane.assignFromPtr(def.pointer.ref.y);
          break;
      }
    } finally {
      def.dispose();
    }

    _state.bumpRevision();
    return this;
  }

  @override
  YuvImage boxBlur({int radius = 10, ui.Rect? rect}) {
    YuvGeometry.validateBlurRadius(radius);
    if (radius == 0) {
      return this;
    }
    _state.requireTightBgraFor('boxBlur');
    final def = YUVDefClass(this);
    final Pointer<Uint32> rectPtr;
    try {
      rectPtr = rect == null ? nullptr : NativeAllocator.instance.allocate<Uint32>(4 * sizeOf<Uint32>());
      if (rect != null) {
        rectPtr.asTypedList(4)
          ..[0] = rect.left.toInt()
          ..[1] = rect.top.toInt()
          ..[2] = rect.right.toInt()
          ..[3] = rect.bottom.toInt();
      }
    } catch (_) {
      def.dispose();
      rethrow;
    }
    try {
      switch (format) {
        case YuvFileFormat.i420:
          ffiBingings.yuv420_box_blur(def.pointer, radius, rectPtr);
          yPlane.assignFromPtr(def.pointer.ref.y);
          uPlane.assignFromPtr(def.pointer.ref.u);
          vPlane.assignFromPtr(def.pointer.ref.v);
          break;
        case YuvFileFormat.nv21:
          ffiBingings.nv21_box_blur(def.pointer, radius, rectPtr);
          yPlane.assignFromPtr(def.pointer.ref.y);
          uPlane.assignFromPtr(def.pointer.ref.u);
          break;
        case YuvFileFormat.bgra8888:
          ffiBingings.bgra8888_box_blur(def.pointer, radius, rectPtr);
          yPlane.assignFromPtr(def.pointer.ref.y);
          break;
      }
    } finally {
      if (rectPtr != nullptr) {
        NativeAllocator.instance.free(rectPtr);
      }
      def.dispose();
    }
    _state.bumpRevision();
    return this;
  }

  @override
  YuvImage crop(ui.Rect rect) {
    final region = _state.clampCrop(rect);
    if (region == null) {
      return this;
    }

    final YuvImage dst = YuvImageImpl(format, region.width, region.height, yPixelStride: _state.yPixelStride, uvPixelStride: _state.uvPixelStride);
    final srcDef = YUVDefClass(this);
    final YUVDefClass dstDef;
    try {
      dstDef = YUVDefClass(dst);
    } catch (_) {
      srcDef.dispose();
      rethrow;
    }
    try {
      switch (format) {
        case YuvFileFormat.i420:
          ffiBingings.yuv420_crop_rect(srcDef.pointer, dstDef.pointer, region.left, region.top, region.width, region.height);
          dst.yPlane.assignFromPtr(dstDef.pointer.ref.y);
          dst.uPlane.assignFromPtr(dstDef.pointer.ref.u);
          dst.vPlane.assignFromPtr(dstDef.pointer.ref.v);

          break;
        case YuvFileFormat.nv21:
          ffiBingings.nv21_crop_rect(srcDef.pointer, dstDef.pointer, region.left, region.top, region.width, region.height);
          dst.yPlane.assignFromPtr(dstDef.pointer.ref.y);
          dst.uPlane.assignFromPtr(dstDef.pointer.ref.u);
          break;
        case YuvFileFormat.bgra8888:
          ffiBingings.bgra8888_crop_rect(srcDef.pointer, dstDef.pointer, region.left, region.top, region.width, region.height);
          dst.yPlane.assignFromPtr(dstDef.pointer.ref.y);
          break;
      }

      _state.replace(format: format, width: dst.width, height: dst.height, planes: dst.planes);
    } finally {
      srcDef.dispose();
      dstDef.dispose();
    }

    return this;
  }

  @override
  YuvImage flipHorizontally() {
    final def = YUVDefClass(this);
    try {
      switch (format) {
        case YuvFileFormat.i420:
          ffiBingings.yuv420_flip_horizontally(def.pointer);
          yPlane.assignFromPtr(def.pointer.ref.y);
          uPlane.assignFromPtr(def.pointer.ref.u);
          vPlane.assignFromPtr(def.pointer.ref.v);
          break;
        case YuvFileFormat.nv21:
          ffiBingings.nv21_flip_horizontally(def.pointer);
          yPlane.assignFromPtr(def.pointer.ref.y);
          uPlane.assignFromPtr(def.pointer.ref.u);
          break;
        case YuvFileFormat.bgra8888:
          ffiBingings.bgra8888_flip_horizontally(def.pointer);
          yPlane.assignFromPtr(def.pointer.ref.y);
          break;
      }
    } finally {
      def.dispose();
    }

    _state.bumpRevision();
    return this;
  }

  @override
  YuvImage flipVertically() {
    final def = YUVDefClass(this);
    try {
      switch (format) {
        case YuvFileFormat.i420:
          ffiBingings.yuv420_flip_vertically(def.pointer);
          yPlane.assignFromPtr(def.pointer.ref.y);
          uPlane.assignFromPtr(def.pointer.ref.u);
          vPlane.assignFromPtr(def.pointer.ref.v);
          break;
        case YuvFileFormat.nv21:
          ffiBingings.nv21_flip_vertically(def.pointer);
          yPlane.assignFromPtr(def.pointer.ref.y);
          uPlane.assignFromPtr(def.pointer.ref.u);
          break;
        case YuvFileFormat.bgra8888:
          ffiBingings.bgra8888_flip_vertically(def.pointer);
          yPlane.assignFromPtr(def.pointer.ref.y);
          break;
      }
    } finally {
      def.dispose();
    }
    _state.bumpRevision();
    return this;
  }

  @override
  void fromRgba8888(Uint8List bytes) {
    _state.validateRgba8888Length(bytes.length);
    if (format == YuvFileFormat.bgra8888 && !_state.isTightBgra) {
      // The BGRA C converter addresses its destination as a tight buffer. Use
      // a tight staging image, then copy only logical four-byte samples into
      // the caller's layout so row/pixel padding remains untouched.
      final tight = YuvImageImpl.bgra(width, height);
      tight.fromRgba8888(bytes);
      _state.copyTightBgraSamplesFrom(tight.yPlane);
      // This branch writes the planes directly and returns early, so it has to
      // bump the revision itself.
      _state.bumpRevision();
      return;
    }
    final rgbaPlaneLength = bytes.length;
    final rgbaPtr = NativeAllocator.instance.allocate<Uint8>(rgbaPlaneLength);
    final YUVDefClass def;
    try {
      rgbaPtr.asTypedList(bytes.length).setRange(0, bytes.length, bytes);
      // Seed the native destination with the current plane contents. The C
      // conversion writes logical samples only; copying first preserves row
      // and pixel padding instead of replacing public plane bytes with the
      // zeroed backing allocation.
      def = YUVDefClass(this);
    } catch (_) {
      NativeAllocator.instance.free(rgbaPtr);
      rethrow;
    }
    try {
      switch (format) {
        case YuvFileFormat.i420:
          ffiBingings.yuv420_from_rgba8888(rgbaPtr, def.pointer);
          yPlane.assignFromPtr(def.pointer.ref.y);
          uPlane.assignFromPtr(def.pointer.ref.u);
          vPlane.assignFromPtr(def.pointer.ref.v);
          break;
        case YuvFileFormat.nv21:
          ffiBingings.nv21_from_rgba8888(rgbaPtr, def.pointer);
          yPlane.assignFromPtr(def.pointer.ref.y);
          uPlane.assignFromPtr(def.pointer.ref.u);
          break;
        case YuvFileFormat.bgra8888:
          ffiBingings.bgra8888_from_rgba8888(rgbaPtr, def.pointer);
          yPlane.assignFromPtr(def.pointer.ref.y);
          break;
      }
    } finally {
      def.dispose();
      NativeAllocator.instance.free(rgbaPtr);
    }
    _state.bumpRevision();
  }

  @override
  YuvImage gaussianBlur({int radius = 2, int sigma = 2}) {
    YuvGeometry.validateBlurRadius(radius);
    if (radius == 0) {
      return this;
    }
    _state.requireTightBgraFor('gaussianBlur');
    final def = YUVDefClass(this);
    try {
      switch (format) {
        case YuvFileFormat.i420:
          ffiBingings.yuv420_gaussblur(def.pointer, radius, sigma);
          yPlane.assignFromPtr(def.pointer.ref.y);
          uPlane.assignFromPtr(def.pointer.ref.u);
          vPlane.assignFromPtr(def.pointer.ref.v);
          break;
        case YuvFileFormat.nv21:
          ffiBingings.nv21_gaussian_blur(def.pointer, radius, sigma.toDouble());
          yPlane.assignFromPtr(def.pointer.ref.y);
          uPlane.assignFromPtr(def.pointer.ref.u);
          break;
        case YuvFileFormat.bgra8888:
          ffiBingings.bgra8888_gaussian_blur(def.pointer, radius, sigma.toDouble());
          yPlane.assignFromPtr(def.pointer.ref.y);
          break;
      }
    } finally {
      def.dispose();
    }

    _state.bumpRevision();
    return this;
  }

  @override
  YuvImage grayscale() {
    final def = YUVDefClass(this);

    try {
      switch (format) {
        case YuvFileFormat.i420:
          ffiBingings.yuv420_grayscale(def.pointer);
          uPlane.assignFromPtr(def.pointer.ref.u);
          vPlane.assignFromPtr(def.pointer.ref.v);
          break;
        case YuvFileFormat.nv21:
          ffiBingings.nv21_grayscale(def.pointer);
          uPlane.assignFromPtr(def.pointer.ref.u);
          break;
        case YuvFileFormat.bgra8888:
          ffiBingings.bgra8888_grayscale(def.pointer);
          yPlane.assignFromPtr(def.pointer.ref.y);
          break;
      }
    } finally {
      def.dispose();
    }
    _state.bumpRevision();
    return this;
  }

  @override
  YuvImage meanBlur({int radius = 2, ui.Rect? rect}) {
    YuvGeometry.validateBlurRadius(radius);
    if (radius == 0) {
      return this;
    }
    _state.requireTightBgraFor('meanBlur');
    final def = YUVDefClass(this);
    final Pointer<Uint32> rectPtr;
    try {
      rectPtr = rect == null ? nullptr : NativeAllocator.instance.allocate<Uint32>(4 * sizeOf<Uint32>());
      if (rect != null) {
        rectPtr.asTypedList(4)
          ..[0] = rect.left.toInt()
          ..[1] = rect.top.toInt()
          ..[2] = rect.right.toInt()
          ..[3] = rect.bottom.toInt();
      }
    } catch (_) {
      def.dispose();
      rethrow;
    }
    try {
      switch (format) {
        case YuvFileFormat.i420:
          ffiBingings.yuv420_mean_blur(def.pointer, radius, rectPtr);
          yPlane.assignFromPtr(def.pointer.ref.y);
          uPlane.assignFromPtr(def.pointer.ref.u);
          vPlane.assignFromPtr(def.pointer.ref.v);
          break;

        case YuvFileFormat.nv21:
          ffiBingings.nv21_mean_blur(def.pointer, radius, rectPtr);
          yPlane.assignFromPtr(def.pointer.ref.y);
          uPlane.assignFromPtr(def.pointer.ref.u);
          break;
        case YuvFileFormat.bgra8888:
          ffiBingings.bgra8888_mean_blur(def.pointer, radius, rectPtr);
          yPlane.assignFromPtr(def.pointer.ref.y);
          break;
      }
    } finally {
      if (rectPtr != nullptr) {
        NativeAllocator.instance.free(rectPtr);
      }
      def.dispose();
    }

    _state.bumpRevision();
    return this;
  }

  @override
  YuvImage negate() {
    final def = YUVDefClass(this);

    try {
      switch (format) {
        case YuvFileFormat.i420:
          ffiBingings.yuv420_negate(def.pointer);
          yPlane.assignFromPtr(def.pointer.ref.y);
          uPlane.assignFromPtr(def.pointer.ref.u);
          vPlane.assignFromPtr(def.pointer.ref.v);
          break;
        case YuvFileFormat.nv21:
          ffiBingings.nv21_negate(def.pointer);
          yPlane.assignFromPtr(def.pointer.ref.y);
          uPlane.assignFromPtr(def.pointer.ref.u);
          break;
        case YuvFileFormat.bgra8888:
          ffiBingings.bgra8888_negate(def.pointer);
          yPlane.assignFromPtr(def.pointer.ref.y);
          break;
      }
    } finally {
      def.dispose();
    }

    _state.bumpRevision();
    return this;
  }

  @override
  YuvImage rotate(YuvImageRotation rotation) {
    // No multiple-of-90 assert: YuvImageRotation is an enum whose only values
    // are 0, 90, 180 and 270, so the check could never fail. Web never had it.
    final int degrees = YuvImageState.normalizeRotationDegrees(rotation.degrees);

    if (degrees == 0) {
      return this;
    }

    final srcDef = YUVDefClass(this);
    final dstWidth = (rotation.swapSize ? height : width).toInt();
    final dstHeight = (rotation.swapSize ? width : height).toInt();
    final YuvImageImpl dstImage;
    final YUVDefClass dstDef;
    try {
      dstImage = YuvImageImpl(format, dstWidth, dstHeight, yPixelStride: _state.yPixelStride, uvPixelStride: _state.uvPixelStride);
      dstDef = YUVDefClass(dstImage);
    } catch (_) {
      srcDef.dispose();
      rethrow;
    }
    try {
      switch (format) {
        case YuvFileFormat.i420:
          ffiBingings.yuv420_rotate(srcDef.pointer, dstDef.pointer, degrees);
          dstImage.yPlane.assignFromPtr(dstDef.pointer.ref.y);
          dstImage.uPlane.assignFromPtr(dstDef.pointer.ref.u);
          dstImage.vPlane.assignFromPtr(dstDef.pointer.ref.v);
          break;
        case YuvFileFormat.nv21:
          ffiBingings.nv21_rotate(srcDef.pointer, dstDef.pointer, degrees);
          dstImage.yPlane.assignFromPtr(dstDef.pointer.ref.y);
          dstImage.uPlane.assignFromPtr(dstDef.pointer.ref.u);
          break;
        case YuvFileFormat.bgra8888:
          ffiBingings.bgra8888_rotate(srcDef.pointer, dstDef.pointer, degrees);
          dstImage.yPlane.assignFromPtr(dstDef.pointer.ref.y);
          break;
      }
      _state.replace(format: format, width: dstWidth, height: dstHeight, planes: dstImage.planes);
    } finally {
      srcDef.dispose();
      dstDef.dispose();
    }

    return this;
  }

  @override
  YuvImage swapNv() {
    // A conversion to NV21 bumps the revision on its own. Snapshot it here so
    // one public swapNv() advances the counter exactly once, whatever path it
    // took to get there.
    final revisionBefore = _state.revision;
    final nvXX = format == YuvFileFormat.nv21 ? this : toYuvNv21();

    final def = YUVDefClass(nvXX);
    final YuvImage nvYY;
    final YUVDefClass defYY;
    try {
      // Keep both destination strides compatible with the source. The native
      // helper accepts one chroma stride for both buffers and only writes active
      // chroma pairs, so a tight destination is not safe for padded input.
      nvYY = YuvImageImpl.nv21(
        width,
        height,
        planes: [
          nvXX.yPlane,
          YuvPlane(
            nvXX.uPlane.height,
            nvXX.uPlane.rowStride,
            nvXX.uPlane.pixelStride,
          ),
        ],
      );
      defYY = YUVDefClass(nvYY);
    } catch (_) {
      def.dispose();
      rethrow;
    }
    try {
      ffiBingings.nvXX_to_nvYY(def.pointer.ref.u, defYY.pointer.ref.u, nvXX.width, nvYY.height, nvXX.uPlane.rowStride);

      nvYY.uPlane.assignFromPtr(defYY.pointer.ref.u);
    } finally {
      def.dispose();
      defYY.dispose();
    }

    _state.replaceFromRevision(
      format: nvYY.format,
      width: nvYY.width,
      height: nvYY.height,
      planes: nvYY.planes,
      revision: revisionBefore,
    );
    return this;
  }

  @override
  Uint8List toBgra8888() {
    final def = YUVDefClass(this);
    final bgraPlaneLength = width * height * 4;
    final Pointer<Uint8> bgraPlane;
    try {
      bgraPlane = NativeAllocator.instance.allocate<Uint8>(bgraPlaneLength);
    } catch (_) {
      def.dispose();
      rethrow;
    }
    try {
      switch (format) {
        case YuvFileFormat.nv21:
          ffiBingings.nv21_to_bgra8888(def.pointer, bgraPlane);
          return Uint8List.fromList(bgraPlane.asTypedList(bgraPlaneLength));
        case YuvFileFormat.i420:
          ffiBingings.yuv420_to_bgra8888(def.pointer, bgraPlane);
          return Uint8List.fromList(bgraPlane.asTypedList(bgraPlaneLength));
        case YuvFileFormat.bgra8888:
          return _state.packedBgraBytes();
      }
    } finally {
      NativeAllocator.instance.free(bgraPlane);
      def.dispose();
    }
  }

  @override
  Future<ui.Image> toImage() {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(toBgra8888(), width, height, ui.PixelFormat.bgra8888, completer.complete);
    return completer.future;
  }

  @override
  YuvImage toYuvBgra8888() {
    if (format == YuvFileFormat.bgra8888) {
      return this;
    }

    final bytes = toBgra8888();
    final image = YuvImageImpl(YuvFileFormat.bgra8888, width, height, planes: [YuvPlane(height, width * 4, 4, bytes)], yPixelStride: 4);
    _state.replace(
      format: image.format,
      width: image.width,
      height: image.height,
      planes: image.planes.map((p) => p.copy()).toList(growable: false),
    );
    return this;
  }

  @override
  YuvImage toYuvI420() {
    if (format == YuvFileFormat.i420) {
      return this;
    }

    final def = YUVDefClass(this);
    final YuvImage i420;
    final YUVDefClass def420;
    try {
      i420 = YuvImageImpl.i420(width, height);
      def420 = YUVDefClass(i420);
    } catch (_) {
      def.dispose();
      rethrow;
    }
    try {
      switch (format) {
        case YuvFileFormat.nv21:
          ffiBingings.nv21_to_i420(def.pointer, def420.pointer);
          break;
        case YuvFileFormat.bgra8888:
          ffiBingings.bgra8888_to_i420(def.pointer, def420.pointer);
          break;
        default:
          throw UnimplementedError();
      }

      i420.yPlane.assignFromPtr(def420.pointer.ref.y);
      i420.uPlane.assignFromPtr(def420.pointer.ref.u);
      i420.vPlane.assignFromPtr(def420.pointer.ref.v);
    } finally {
      def.dispose();
      def420.dispose();
    }
    _state.replace(
      format: i420.format,
      width: i420.width,
      height: i420.height,
      planes: i420.planes.map((p) => p.copy()).toList(growable: false),
    );
    return this;
  }

  @override
  YuvImage toYuvNv21() {
    if (format == YuvFileFormat.nv21) {
      return this;
    }

    final def = YUVDefClass(this);
    final YuvImage n21;
    final YUVDefClass def21;
    try {
      n21 = YuvImageImpl.nv21(width, height);
      def21 = YUVDefClass(n21);
    } catch (_) {
      def.dispose();
      rethrow;
    }
    try {
      switch (format) {
        case YuvFileFormat.i420:
          ffiBingings.yuv420_i420_to_nv21(def.pointer, def21.pointer);
          break;
        case YuvFileFormat.bgra8888:
          ffiBingings.bgra8888_to_nv21(def.pointer, def21.pointer);
          break;
        default:
          throw UnimplementedError();
      }

      n21.yPlane.assignFromPtr(def21.pointer.ref.y);
      n21.uPlane.assignFromPtr(def21.pointer.ref.u);
    } finally {
      def.dispose();
      def21.dispose();
    }

    _state.replace(
      format: n21.format,
      width: n21.width,
      height: n21.height,
      planes: n21.planes.map((p) => p.copy()).toList(growable: false),
    );
    return this;
  }
}

extension on YuvPlane {
  void assignFromPtr(Pointer<Uint8> ptr) => assignFrom(ptr.asTypedList(bytes.length));
}
