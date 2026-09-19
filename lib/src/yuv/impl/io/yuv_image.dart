import 'dart:async';
import 'dart:ffi';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:yuv_ffi/src/loader/loader.dart';
import 'package:yuv_ffi/src/yuv/impl/io/defs/native_allocator.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_codec.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_file_format.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_geometry.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_image_rotation.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_plane.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_plane_bytes.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_revision.dart';
import 'package:yuv_ffi/src/yuv/yuv.dart';

import 'defs/yuv_def.dart';

class YuvImageImpl implements YuvImage, YuvRevisionAware {
  List<YuvPlane> _planes = const [];
  YuvFileFormat _format;
  int _width;
  int _height;
  int _revision = 0;

  @override
  int get internalRevision => _revision;

  @override
  void bumpInternalRevision() => _revision++;

  @override
  YuvFileFormat get format => _format;

  @override
  int get width => _width;

  @override
  int get height => _height;

  @override
  List<YuvPlane> get planes => List.unmodifiable(_planes);

  @override
  YuvPlane get yPlane => _planes[0];

  @override
  YuvPlane get uPlane => _planes[1];

  @override
  YuvPlane get vPlane => _planes[2];

  @override
  YuvPlane get y => _planes[0];

  @override
  YuvPlane? get u => _planes.length > 1 ? _planes[1] : null;

  @override
  YuvPlane? get v => _planes.length > 2 ? _planes[2] : null;

  @override
  ui.Size get size => ui.Size(width.toDouble(), height.toDouble());

  YuvImageImpl.i420(int width, int height, {int yPixelStride = 1, int uvPixelStride = 2, Iterable<YuvPlane>? planes})
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

  YuvImageImpl(this._format, this._width, this._height, {int yPixelStride = 1, int uvPixelStride = 1, Iterable<YuvPlane>? planes}) {
    YuvGeometry.validateDimensions(_width, _height);

    if (planes != null) {
      final copied = List.of(planes.map((e) => e.copy()));
      YuvGeometry.validateImage(format: _format, width: _width, height: _height, planes: copied);
      _planes = copied;
      return;
    }

    // BGRA stores four bytes per pixel, so its packed plane never uses the
    // generic single-byte luma default.
    final lumaPixelStride = format == YuvFileFormat.bgra8888 ? 4 : yPixelStride;
    final yplane = YuvPlane(height, width * lumaPixelStride, lumaPixelStride);
    final uvWidth = YuvGeometry.chromaWidth(width);
    final uvHeight = YuvGeometry.chromaHeight(height);
    switch (format) {
      case YuvFileFormat.nv21:
        // Interleaved chroma always stores a (U, V) pair per sample, so a
        // pixelStride below 2 cannot hold what native code writes.
        final nvPixelStride = uvPixelStride < 2 ? 2 : uvPixelStride;
        final uvplane = YuvPlane(uvHeight, uvWidth * nvPixelStride, nvPixelStride);
        _planes = [yplane, uvplane];
        break;
      case YuvFileFormat.i420:
        final uplane = YuvPlane(uvHeight, uvWidth * uvPixelStride, uvPixelStride);
        final vplane = YuvPlane(uvHeight, uvWidth * uvPixelStride, uvPixelStride);
        _planes = [yplane, uplane, vplane];
        break;
      case YuvFileFormat.bgra8888:
        _planes = [yplane];
        break;
    }

    // Validate the geometry we just allocated as well: a caller-supplied zero
    // or negative stride would otherwise produce a degenerate plane and still
    // reach a backend call.
    YuvGeometry.validateImage(format: _format, width: _width, height: _height, planes: _planes);
  }

  @override
  Uint8List getBytes() => YuvPlaneBytes.concat(_planes);

  @override
  YuvImage copy({bool blank = false}) =>
      YuvImageImpl(format, width, height, planes: _copiedPlanes(blank: blank), yPixelStride: y.pixelStride, uvPixelStride: u?.pixelStride ?? 1);

  /// Planes for [copy].
  ///
  /// A blank copy keeps every plane's declared geometry and zeroes the whole
  /// allocation, so padded metadata survives. Passing `null` instead would fall
  /// back to the allocating path, which rebuilds tight planes and silently
  /// drops the padding.
  List<YuvPlane> _copiedPlanes({required bool blank}) =>
      [for (final plane in _planes) blank ? YuvPlane(plane.height, plane.rowStride, plane.pixelStride) : plane.copy()];

  @override
  Future save(Sink<List<int>> sink) async {
    sink.add(YuvCodec.encode(format: format, width: width, height: height, planes: _planes));
  }

  @override
  Future<void> load(Stream<List<int>> stream) async {
    // Decode into a draft first: state is replaced only once the whole payload
    // has been read and validated, so a malformed frame cannot leave this image
    // half-updated. A rejected payload therefore also leaves the revision alone.
    final draft = await YuvCodec.decodeStream(stream);

    _width = draft.width;
    _height = draft.height;
    _format = draft.format;
    _planes = draft.planes;
    _revision++;
  }

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

    _revision++;
    return this;
  }

  @override
  YuvImage boxBlur({int radius = 10, ui.Rect? rect}) {
    _requireTightBgraFor('boxBlur');
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
    _revision++;
    return this;
  }

  @override
  YuvImage crop(ui.Rect rect) {
    final left = rect.left.floor().clamp(0, _width).toInt();
    final top = rect.top.floor().clamp(0, _height).toInt();
    final right = rect.right.ceil().clamp(left, _width).toInt();
    final bottom = rect.bottom.ceil().clamp(top, _height).toInt();
    final cropWidth = right - left;
    final cropHeight = bottom - top;
    if (cropWidth <= 0 || cropHeight <= 0) {
      return this;
    }

    final YuvImage dst = YuvImageImpl(format, cropWidth, cropHeight, yPixelStride: y.pixelStride, uvPixelStride: u?.pixelStride ?? 1);
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
          ffiBingings.yuv420_crop_rect(srcDef.pointer, dstDef.pointer, left, top, cropWidth, cropHeight);
          dst.yPlane.assignFromPtr(dstDef.pointer.ref.y);
          dst.uPlane.assignFromPtr(dstDef.pointer.ref.u);
          dst.vPlane.assignFromPtr(dstDef.pointer.ref.v);

          break;
        case YuvFileFormat.nv21:
          ffiBingings.nv21_crop_rect(srcDef.pointer, dstDef.pointer, left, top, cropWidth, cropHeight);
          dst.yPlane.assignFromPtr(dstDef.pointer.ref.y);
          dst.uPlane.assignFromPtr(dstDef.pointer.ref.u);
          break;
        case YuvFileFormat.bgra8888:
          ffiBingings.bgra8888_crop_rect(srcDef.pointer, dstDef.pointer, left, top, cropWidth, cropHeight);
          dst.yPlane.assignFromPtr(dstDef.pointer.ref.y);
          break;
      }

      _width = dst.width;
      _height = dst.height;
      _planes = dst.planes;
    } finally {
      srcDef.dispose();
      dstDef.dispose();
    }

    _revision++;
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

    _revision++;
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
    _revision++;
    return this;
  }

  @override
  void fromRgba8888(Uint8List bytes) {
    final expectedLength = width * height * 4;
    if (bytes.length != expectedLength) {
      throw ArgumentError.value(bytes.length, 'bytes.length', 'Expected $expectedLength bytes for RGBA8888 frame ${width}x$height');
    }
    if (format == YuvFileFormat.bgra8888 && !YuvGeometry.isTightBgra(yPlane, width)) {
      // The BGRA C converter addresses its destination as a tight buffer. Use
      // a tight staging image, then copy only logical four-byte samples into
      // the caller's layout so row/pixel padding remains untouched.
      final tight = YuvImageImpl.bgra(width, height);
      tight.fromRgba8888(bytes);
      for (int row = 0; row < height; row++) {
        for (int column = 0; column < width; column++) {
          final source = row * tight.yPlane.rowStride + column * 4;
          final destination = row * yPlane.rowStride + column * yPlane.pixelStride;
          yPlane.bytes.setRange(destination, destination + 4, tight.yPlane.bytes, source);
        }
      }
      // This branch writes the planes directly and returns early, so it has to
      // bump the revision itself.
      _revision++;
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
    _revision++;
  }

  /// Rejects a padded BGRA plane before an operation that cannot handle it.
  ///
  /// Several native BGRA effects allocate a tight `width * height * 4` scratch
  /// buffer but address it through the source row stride, so a padded plane
  /// makes them write past the allocation. Until those implementations are
  /// fixed (YUV-23), such a layout is refused here rather than passed to FFI.
  void _requireTightBgraFor(String operation) {
    if (format != YuvFileFormat.bgra8888) {
      return;
    }
    if (!YuvGeometry.isTightBgra(yPlane, width)) {
      throw ArgumentError.value(
        yPlane.rowStride,
        'yPlane.rowStride',
        '$operation does not support a padded BGRA plane yet; expected a tight '
            'row stride of ${width * 4}. Repack the plane before calling it.',
      );
    }
  }

  @override
  YuvImage gaussianBlur({int radius = 2, int sigma = 2}) {
    _requireTightBgraFor('gaussianBlur');
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

    _revision++;
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
    _revision++;
    return this;
  }

  @override
  YuvImage meanBlur({int radius = 2, ui.Rect? rect}) {
    _requireTightBgraFor('meanBlur');
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

    _revision++;
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

    _revision++;
    return this;
  }

  @override
  YuvImage rotate(YuvImageRotation rotation) {
    // No multiple-of-90 assert: YuvImageRotation is an enum whose only values
    // are 0, 90, 180 and 270, so the check could never fail. Web never had it.
    final int degrees = (rotation.degrees < 0 ? 360 - rotation.degrees.abs() : rotation.degrees) % 360;

    if (degrees == 0) {
      return this;
    }

    final srcDef = YUVDefClass(this);
    final dstWidth = (rotation.swapSize ? height : width).toInt();
    final dstHeight = (rotation.swapSize ? width : height).toInt();
    final YuvImageImpl dstImage;
    final YUVDefClass dstDef;
    try {
      dstImage = YuvImageImpl(format, dstWidth, dstHeight, yPixelStride: yPlane.pixelStride, uvPixelStride: u?.pixelStride ?? 1);
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
      _width = dstWidth;
      _height = dstHeight;
      _planes = dstImage.planes;
    } finally {
      srcDef.dispose();
      dstDef.dispose();
    }

    _revision++;
    return this;
  }

  @override
  YuvImage swapNv() {
    // A conversion to NV21 bumps the revision on its own. Snapshot it here so
    // one public swapNv() advances the counter exactly once, whatever path it
    // took to get there.
    final revisionBefore = _revision;
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

    _format = nvYY.format;
    _width = nvYY.width;
    _height = nvYY.height;
    _planes = nvYY.planes;
    _revision = revisionBefore + 1;
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
          final expectedRowStride = width * 4;
          if (yPlane.rowStride == expectedRowStride) {
            return Uint8List.fromList(yPlane.bytes);
          }

          // Repack BGRA rows when source plane has padding bytes per row.
          final packed = Uint8List(bgraPlaneLength);
          for (int y = 0; y < height; y++) {
            final srcStart = y * yPlane.rowStride;
            final dstStart = y * expectedRowStride;
            packed.setRange(dstStart, dstStart + expectedRowStride, yPlane.bytes, srcStart);
          }
          return packed;
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
    _format = image.format;
    _width = image.width;
    _height = image.height;
    _planes = image.planes.map((p) => p.copy()).toList(growable: false);
    _revision++;
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
    _format = i420.format;
    _width = i420.width;
    _height = i420.height;
    _planes = i420.planes.map((p) => p.copy()).toList(growable: false);
    _revision++;
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

    _format = n21.format;
    _width = n21.width;
    _height = n21.height;
    _planes = n21.planes.map((p) => p.copy()).toList(growable: false);
    _revision++;
    return this;
  }
}

extension on YuvPlane {
  void assignFromPtr(Pointer<Uint8> ptr) => assignFrom(ptr.asTypedList(bytes.length));
}
