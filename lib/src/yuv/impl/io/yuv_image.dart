import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:yuv_ffi/src/loader/data_io.dart';
import 'package:yuv_ffi/src/loader/loader.dart';
import 'package:yuv_ffi/src/yuv/impl/io/defs/native_allocator.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_file_format.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_geometry.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_image_rotation.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_plane.dart';
import 'package:yuv_ffi/src/yuv/yuv.dart';

import 'defs/yuv_def.dart';

class YuvImageImpl implements YuvImage {
  List<YuvPlane> _planes = const [];
  YuvFileFormat _format;
  int _width;
  int _height;

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

  YuvImageImpl.bgra(this._width, this._height, {Iterable<YuvPlane>? planes}) : _format = YuvFileFormat.bgra8888 {
    YuvGeometry.validateDimensions(_width, _height);

    final int tightRowStride = width * 4;
    Uint8List? bytes;
    if (planes?.isNotEmpty == true) {
      final rawY = planes!.first;
      YuvGeometry.validatePlane(
        plane: rawY,
        label: 'yPlane',
        expectedHeight: height,
        expectedWidth: width,
        sampleBytes: 4,
      );

      // Repack into tightly packed rows. A WriteBuffer's backing ByteBuffer is
      // grown in powers of two, so its length is not the written length; build
      // the exact-size buffer directly instead.
      bytes = Uint8List(height * tightRowStride);
      for (int y = 0; y < height; y++) {
        bytes.setRange(y * tightRowStride, (y + 1) * tightRowStride, rawY.bytes, y * rawY.rowStride);
      }
    }

    _planes = [YuvPlane(height, tightRowStride, 4, bytes)];
  }

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
  }

  @override
  Uint8List getBytes() {
    final WriteBuffer allBytes = WriteBuffer();
    for (final plane in planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();
    return bytes;
  }

  @override
  YuvImage copy({bool blank = false}) =>
      YuvImageImpl(format, width, height, planes: blank ? null : _planes, yPixelStride: y.pixelStride, uvPixelStride: u?.pixelStride ?? 1);

  @override
  Future save(Sink<List<int>> sink) async {
    var json = {'version': 1, 'format': format.name, 'width': width, 'height': height};

    var writer = DataWriter(sink);
    writer.writeString(jsonEncode(json));
    writer.writeUint8(planes.length);
    for (final plane in planes) {
      writer.writeUint32(plane.height);
      writer.writeUint32(plane.rowStride);
      writer.writeUint32(plane.pixelStride);
      writer.writeBytes(plane.bytes);
    }
    writer.write();
  }

  @override
  Future<void> load(Stream<List<int>> stream) async {
    var reader = DataReader(stream);
    await reader.done();

    var headerText = reader.readString();
    var header = jsonDecode(headerText);

    _width = header['width'];
    _height = header['height'];
    _format = YuvFileFormat.values.byName(header['format']);
    var planesCount = reader.readUint8();
    _planes = <YuvPlane>[];
    for (var i = 0; i < planesCount; i++) {
      var planeHeight = reader.readUint32();
      var rowStride = reader.readUint32();
      var pixelStride = reader.readUint32();
      var planeBytes = reader.readBytes();
      var plane = YuvPlane(planeHeight, rowStride, pixelStride, planeBytes);
      _planes.add(plane);
    }
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

    return this;
  }

  @override
  YuvImage boxBlur({int radius = 10, ui.Rect? rect}) {
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
    return this;
  }

  @override
  void fromRgba8888(Uint8List bytes) {
    final expectedLength = width * height * 4;
    if (bytes.length != expectedLength) {
      throw ArgumentError.value(bytes.length, 'bytes.length', 'Expected $expectedLength bytes for RGBA8888 frame ${width}x$height');
    }
    final rgbaPlaneLength = bytes.length;
    final rgbaPtr = NativeAllocator.instance.allocate<Uint8>(rgbaPlaneLength);
    final YUVDefClass def;
    try {
      rgbaPtr.asTypedList(bytes.length).setRange(0, bytes.length, bytes);
      def = YUVDefClass.template(this);
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
  }

  @override
  YuvImage gaussianBlur({int radius = 2, int sigma = 2}) {
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
    return this;
  }

  @override
  YuvImage meanBlur({int radius = 2, ui.Rect? rect}) {
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

    return this;
  }

  @override
  YuvImage rotate(YuvImageRotation rotation) {
    assert(rotation.degrees % 90 == 0, 'Can rotate only to 0, 90, 180, 270 degrees');
    final int degrees = (rotation.degrees < 0 ? 360 - rotation.degrees.abs() : rotation.degrees) % 360;

    if (degrees == 0) {
      return this;
    }

    final srcDef = YUVDefClass(this);
    final dstWidtn = (rotation.swapSize ? height : width).toInt();
    final dstHeight = (rotation.swapSize ? width : height).toInt();
    final YuvImageImpl dstImage;
    final YUVDefClass dstDef;
    try {
      dstImage = YuvImageImpl(format, dstWidtn, dstHeight, yPixelStride: yPlane.pixelStride, uvPixelStride: u?.pixelStride ?? 1);
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
      _width = dstWidtn;
      _height = dstHeight;
      _planes = dstImage.planes;
    } finally {
      srcDef.dispose();
      dstDef.dispose();
    }

    return this;
  }

  @override
  YuvImage swapNv() {
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
    return this;
  }
}

extension on YuvPlane {
  void assignFromPtr(Pointer<Uint8> ptr) => assignFrom(ptr.asTypedList(bytes.length));
}
