import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:yuv_ffi/src/loader/loader.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_file_format.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_image_rotation.dart';
import 'package:yuv_ffi/src/yuv/yuv.dart';

import 'defs/yuv_def.dart';

class YuvImageImpl implements YuvImage {
  late final List<YuvPlane> _planes;

  @override
  late final YuvFileFormat format;

  @override
  final int width;

  @override
  final int height;

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

  YuvImageImpl.bgra(this.width, this.height, {Iterable<YuvPlane>? planes}) : format = YuvFileFormat.bgra8888 {
    Uint8List? bytes;
    if (planes?.isNotEmpty == true) {
      var rawY = planes!.first;
      final WriteBuffer allBytes = WriteBuffer();
      for (int y = 0; y < height; y++) {
        allBytes.putUint8List(rawY.bytes.sublist(y * rawY.rowStride, y * rawY.rowStride + width * 4));
      }
      bytes = allBytes.done().buffer.asUint8List();
    }
    YuvPlane y = YuvPlaneImpl(height, width * 4, 4, bytes);

    _planes = [y];
  }

  YuvImageImpl(this.format, this.width, this.height, {int yPixelStride = 1, int uvPixelStride = 1, Iterable<YuvPlane>? planes}) {
    if (planes != null) {
      _planes = List.of(planes.map((e) => e.copy()));
      return;
    }

    final yplane = YuvPlaneImpl(height, width * yPixelStride, yPixelStride);
    final uvWidth = width ~/ 2;
    final uvHeight = height ~/ 2;
    switch (format) {
      case YuvFileFormat.nv21:
        final uvplane = YuvPlaneImpl(uvHeight, uvWidth * uvPixelStride, uvPixelStride);
        _planes = [yplane, uvplane];
        break;
      case YuvFileFormat.i420:
        final uplane = YuvPlaneImpl(uvHeight, uvWidth * uvPixelStride, uvPixelStride);
        final vplane = YuvPlaneImpl(uvHeight, uvWidth * uvPixelStride, uvPixelStride);
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
  String toJson({bool bytesAsBinary = true, bool bytesAsList = false}) {
    var json = {
      'format': format.name,
      'width': width,
      'height': height,
      'planes': planes.map((p) => p.toJson(bytesAsBinary: bytesAsBinary, bytesAsList: bytesAsList)).toList(),
    };
    var text = jsonEncode(json);
    return text;
  }

  factory YuvImageImpl.fromJson(Map<String, dynamic> json, {bool bytesAsBinary = true, bool bytesAsList = false}) {
    YuvFileFormat format = YuvFileFormat.values.byName(json['format']);
    final width = json['width'];
    final height = json['height'];
    final planes = (json['planes'] as Iterable).map((j) => YuvPlaneImpl.fromJson(j, bytesAsList: bytesAsList, bytesAsBinary: bytesAsBinary)).toList();
    return YuvImageImpl(format, width, height, planes: planes);
  }

  @override
  String toString() {
    return '$runtimeType($format;$width:$height)';
  }

  @override
  YuvImage blackwhite() {
    final def = YUVDefClass(this);
    try {
      switch (format) {
        case YuvFileFormat.i420:
          ffiBingings.yuv420_blackwhite(def.pointer);
          yPlane.assignFrom(def.pointer.ref.y);
          uPlane.assignFrom(def.pointer.ref.u);
          vPlane.assignFrom(def.pointer.ref.v);
          break;
        case YuvFileFormat.nv21:
          ffiBingings.nv21_blackwhite(def.pointer);
          yPlane.assignFrom(def.pointer.ref.y);
          uPlane.assignFrom(def.pointer.ref.u);
          break;
        case YuvFileFormat.bgra8888:
          ffiBingings.bgra8888_blackwhite(def.pointer);
          yPlane.assignFrom(def.pointer.ref.y);
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
    final rectPtr = rect == null ? nullptr : calloc.allocate<Uint32>(4 * 32);
    if (rect != null) {
      rectPtr.asTypedList(32)
        ..[0] = rect.left.toInt()
        ..[1] = rect.top.toInt()
        ..[2] = rect.right.toInt()
        ..[3] = rect.bottom.toInt();
    }
    try {
      switch (format) {
        case YuvFileFormat.i420:
          ffiBingings.yuv420_box_blur(def.pointer, radius, rectPtr);
          yPlane.assignFrom(def.pointer.ref.y);
          break;
        case YuvFileFormat.nv21:
          ffiBingings.nv21_box_blur(def.pointer, radius, rectPtr);
          yPlane.assignFrom(def.pointer.ref.y);
          uPlane.assignFrom(def.pointer.ref.u);
          break;
        case YuvFileFormat.bgra8888:
          ffiBingings.bgra8888_box_blur(def.pointer, radius, rectPtr);
          yPlane.assignFrom(def.pointer.ref.y);
          break;
      }
    } finally {
      def.dispose();
    }
    return this;
  }

  @override
  YuvImage crop(ui.Rect rect) {
    final YuvImage dst = YuvImageImpl(
      format,
      rect.width.floor(),
      rect.height.floor(),
      yPixelStride: y.pixelStride,
      uvPixelStride: u?.pixelStride ?? 1,
    );
    final srcDef = YUVDefClass(this);
    final dstDef = YUVDefClass(dst);
    try {
      switch (format) {
        case YuvFileFormat.i420:
          ffiBingings.yuv420_crop_rect(srcDef.pointer, dstDef.pointer, rect.left.floor(), rect.top.floor(), rect.width.floor(), rect.height.floor());
          dst.yPlane.assignFrom(dstDef.pointer.ref.y);
          dst.uPlane.assignFrom(dstDef.pointer.ref.u);
          dst.vPlane.assignFrom(dstDef.pointer.ref.v);

          break;
        case YuvFileFormat.nv21:
          ffiBingings.nv21_crop_rect(srcDef.pointer, dstDef.pointer, rect.left.floor(), rect.top.floor(), rect.width.floor(), rect.height.floor());
          dst.yPlane.assignFrom(dstDef.pointer.ref.y);
          dst.uPlane.assignFrom(dstDef.pointer.ref.u);
          break;
        case YuvFileFormat.bgra8888:
          ffiBingings.bgra8888_crop_rect(
              srcDef.pointer, dstDef.pointer, rect.left.floor(), rect.top.floor(), rect.width.floor(), rect.height.floor());
          dst.yPlane.assignFrom(dstDef.pointer.ref.y);
          break;
      }
    } finally {
      srcDef.dispose();
      dstDef.dispose();
    }

    return dst;
  }

  @override
  YuvImage flipHorizontally() {
    final def = YUVDefClass(this);
    try {
      switch (format) {
        case YuvFileFormat.i420:
          ffiBingings.yuv420_flip_horizontally(def.pointer);
          yPlane.assignFrom(def.pointer.ref.y);
          uPlane.assignFrom(def.pointer.ref.u);
          vPlane.assignFrom(def.pointer.ref.v);
          break;
        case YuvFileFormat.nv21:
          ffiBingings.nv21_flip_horizontally(def.pointer);
          yPlane.assignFrom(def.pointer.ref.y);
          uPlane.assignFrom(def.pointer.ref.u);
          break;
        case YuvFileFormat.bgra8888:
          ffiBingings.bgra8888_flip_horizontally(def.pointer);
          yPlane.assignFrom(def.pointer.ref.y);
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
          yPlane.assignFrom(def.pointer.ref.y);
          uPlane.assignFrom(def.pointer.ref.u);
          vPlane.assignFrom(def.pointer.ref.v);
          break;
        case YuvFileFormat.nv21:
          ffiBingings.nv21_flip_vertically(def.pointer);
          yPlane.assignFrom(def.pointer.ref.y);
          uPlane.assignFrom(def.pointer.ref.u);
          break;
        case YuvFileFormat.bgra8888:
          ffiBingings.bgra8888_flip_vertically(def.pointer);
          yPlane.assignFrom(def.pointer.ref.y);
          break;
      }
    } finally {
      def.dispose();
    }
    return this;
  }

  @override
  void fromRgba8888(Uint8List bytes) {
    final rgbaPlaneLength = bytes.length;
    final rgbaPtr = calloc.allocate<Uint8>(rgbaPlaneLength);
    rgbaPtr.asTypedList(bytes.length).setRange(0, bytes.length, bytes);
    final def = YUVDefClass.template(this);
    try {
      switch (format) {
        case YuvFileFormat.i420:
          ffiBingings.yuv420_from_rgba8888(rgbaPtr, def.pointer);
          yPlane.assignFrom(def.pointer.ref.y);
          uPlane.assignFrom(def.pointer.ref.u);
          vPlane.assignFrom(def.pointer.ref.v);
          break;
        case YuvFileFormat.nv21:
          ffiBingings.nv21_from_rgba8888(rgbaPtr, def.pointer);
          yPlane.assignFrom(def.pointer.ref.y);
          uPlane.assignFrom(def.pointer.ref.u);
          break;
        case YuvFileFormat.bgra8888:
          ffiBingings.bgra8888_from_rgba8888(rgbaPtr, def.pointer);
          yPlane.assignFrom(def.pointer.ref.y);
          break;
      }
    } finally {
      def.dispose();
      calloc.free(rgbaPtr);
    }
  }

  @override
  YuvImage gaussianBlur({int radius = 2, int sigma = 2}) {
    final def = YUVDefClass(this);
    try {
      switch (format) {
        case YuvFileFormat.i420:
          ffiBingings.yuv420_gaussblur(def.pointer, radius, sigma);
          yPlane.assignFrom(def.pointer.ref.y);
          uPlane.assignFrom(def.pointer.ref.u);
          vPlane.assignFrom(def.pointer.ref.v);
          break;
        case YuvFileFormat.nv21:
          ffiBingings.nv21_gaussian_blur(def.pointer, radius, sigma.toDouble());
          yPlane.assignFrom(def.pointer.ref.y);
          uPlane.assignFrom(def.pointer.ref.u);
          break;
        case YuvFileFormat.bgra8888:
          ffiBingings.bgra8888_gaussian_blur(def.pointer, radius, sigma.toDouble());
          yPlane.assignFrom(def.pointer.ref.y);
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
          uPlane.assignFrom(def.pointer.ref.u);
          vPlane.assignFrom(def.pointer.ref.v);
          break;
        case YuvFileFormat.nv21:
          ffiBingings.nv21_grayscale(def.pointer);
          uPlane.assignFrom(def.pointer.ref.u);
          break;
        case YuvFileFormat.bgra8888:
          ffiBingings.bgra8888_grayscale(def.pointer);
          yPlane.assignFrom(def.pointer.ref.y);
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
    final rectPtr = rect == null ? nullptr : calloc.allocate<Uint32>(4 * 32);
    if (rect != null) {
      rectPtr.asTypedList(32)
        ..[0] = rect.left.toInt()
        ..[1] = rect.top.toInt()
        ..[2] = rect.right.toInt()
        ..[3] = rect.bottom.toInt();
    }
    try {
      switch (format) {
        case YuvFileFormat.i420:
          ffiBingings.yuv420_mean_blur(def.pointer, radius, rectPtr);
          yPlane.assignFrom(def.pointer.ref.y);
          break;

        case YuvFileFormat.nv21:
          ffiBingings.nv21_mean_blur(def.pointer, radius, rectPtr);
          yPlane.assignFrom(def.pointer.ref.y);
          uPlane.assignFrom(def.pointer.ref.u);
          break;
        case YuvFileFormat.bgra8888:
          ffiBingings.bgra8888_mean_blur(def.pointer, radius, rectPtr);
          yPlane.assignFrom(def.pointer.ref.y);
          break;
      }
    } finally {
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
          yPlane.assignFrom(def.pointer.ref.y);
          uPlane.assignFrom(def.pointer.ref.u);
          vPlane.assignFrom(def.pointer.ref.v);
          break;
        case YuvFileFormat.nv21:
          ffiBingings.nv21_negate(def.pointer);
          yPlane.assignFrom(def.pointer.ref.y);
          uPlane.assignFrom(def.pointer.ref.u);
          break;
        case YuvFileFormat.bgra8888:
          ffiBingings.bgra8888_negate(def.pointer);
          yPlane.assignFrom(def.pointer.ref.y);
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
    final dstImage = YuvImageImpl(format, dstWidtn, dstHeight, yPixelStride: yPlane.pixelStride, uvPixelStride: u?.pixelStride ?? 1);
    final dstDef = YUVDefClass(dstImage);
    try {
      switch (format) {
        case YuvFileFormat.i420:
          ffiBingings.yuv420_rotate(srcDef.pointer, dstDef.pointer, degrees);
          dstImage.yPlane.assignFrom(dstDef.pointer.ref.y);
          dstImage.uPlane.assignFrom(dstDef.pointer.ref.u);
          dstImage.vPlane.assignFrom(dstDef.pointer.ref.v);
          break;
        case YuvFileFormat.nv21:
          ffiBingings.nv21_rotate(srcDef.pointer, dstDef.pointer, degrees);
          dstImage.yPlane.assignFrom(dstDef.pointer.ref.y);
          dstImage.uPlane.assignFrom(dstDef.pointer.ref.u);
          break;
        case YuvFileFormat.bgra8888:
          ffiBingings.bgra8888_rotate(srcDef.pointer, dstDef.pointer, degrees);
          dstImage.yPlane.assignFrom(dstDef.pointer.ref.y);
          break;
      }
    } finally {
      srcDef.dispose();
      dstDef.dispose();
    }

    return dstImage;
  }

  @override
  YuvImage swapNv() {
    var nvXX = format == YuvFileFormat.nv21 ? this : toYuvNv21();

    final def = YUVDefClass(nvXX);
    YuvImage nvYY = YuvImageImpl.nv21(width, height);
    final defYY = YUVDefClass(nvYY);
    try {
      ffiBingings.nvXX_to_nvYY(def.pointer.ref.u, defYY.pointer.ref.u, nvXX.width, nvYY.width, nvXX.uPlane.rowStride);

      nvYY.yPlane.assignFrom(defYY.pointer.ref.y);
      nvYY.uPlane.assignFrom(defYY.pointer.ref.u);
    } finally {
      def.dispose();
      defYY.dispose();
    }

    return nvYY;
  }

  @override
  Uint8List toBgra8888() {
    final def = YUVDefClass(this);
    final bgraPlaneLength = width * height * 4;
    final bgraPlane = calloc.allocate<Uint8>(bgraPlaneLength);
    try {
      switch (format) {
        case YuvFileFormat.nv21:
          ffiBingings.nv21_to_bgra8888(def.pointer, bgraPlane);
          return Uint8List.fromList(bgraPlane.asTypedList(bgraPlaneLength));
        case YuvFileFormat.i420:
          ffiBingings.yuv420_to_bgra8888(def.pointer, bgraPlane);
          return Uint8List.fromList(bgraPlane.asTypedList(bgraPlaneLength));
        case YuvFileFormat.bgra8888:
          return yPlane.bytes;
      }
    } finally {
      calloc.free(bgraPlane);
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

    var bytes = toBgra8888();
    var image = YuvImageImpl(YuvFileFormat.bgra8888, width, height, planes: [YuvPlaneImpl(height, width * 4, 4, bytes)], yPixelStride: 4);
    return image;
  }

  @override
  YuvImage toYuvI420() {
    if (format == YuvFileFormat.i420) {
      return this;
    }

    final def = YUVDefClass(this);
    YuvImage i420 = YuvImageImpl.i420(width, height);
    final def420 = YUVDefClass(i420);
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

      i420.yPlane.assignFrom(def420.pointer.ref.y);
      i420.uPlane.assignFrom(def420.pointer.ref.u);
      i420.vPlane.assignFrom(def420.pointer.ref.v);
    } finally {
      def.dispose();
      def420.dispose();
    }
    return i420;
  }

  @override
  YuvImage toYuvNv21() {
    if (format == YuvFileFormat.nv21) {
      return this;
    }

    final def = YUVDefClass(this);
    YuvImage n21 = YuvImageImpl.nv21(width, height);
    final def21 = YUVDefClass(n21);
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

      n21.yPlane.assignFrom(def21.pointer.ref.y);
      n21.uPlane.assignFrom(def21.pointer.ref.u);
    } finally {
      def.dispose();
      def21.dispose();
    }

    return n21;
  }
}
