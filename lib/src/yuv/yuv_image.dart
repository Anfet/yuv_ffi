import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:yuv_ffi/src/functions/from_rgba8888.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

enum YuvFileFormat {
  nv21,
  i420,
  bgra8888,
  ;
}

class YuvImage {
  late final YuvFileFormat format;
  final int width;
  final int height;

  List<YuvPlane> get planes => List.unmodifiable(_planes);

  late final List<YuvPlane> _planes;

  YuvPlane get yPlane => _planes[0];

  YuvPlane get uPlane => _planes[1];

  YuvPlane get vPlane => _planes[2];

  YuvPlane get y => _planes[0];

  YuvPlane? get u => _planes.length > 1 ? _planes[1] : null;

  YuvPlane? get v => _planes.length > 2 ? _planes[2] : null;

  Size get size => Size(width.toDouble(), height.toDouble());

  YuvImage.i420(int width, int height, {int yPixelStride = 1, int uvPixelStride = 2, Iterable<YuvPlane>? planes})
      : this(YuvFileFormat.i420, width, height, yPixelStride: yPixelStride, uvPixelStride: uvPixelStride, planes: planes);

  YuvImage.nv21(int width, int height, {int yPixelStride = 1, int uvPixelStride = 2, Iterable<YuvPlane>? planes})
      : this(YuvFileFormat.nv21, width, height, yPixelStride: yPixelStride, uvPixelStride: uvPixelStride, planes: planes);

  YuvImage.bgra(int width, int height, {Iterable<YuvPlane>? planes})
      : this(YuvFileFormat.bgra8888, width, height, yPixelStride: 4, planes: planes);

  YuvImage(this.format, this.width, this.height, {int yPixelStride = 1, int uvPixelStride = 1, Iterable<YuvPlane>? planes}) {
    if (planes != null) {
      _planes = List.of(planes);
      return;
    }

    final yplane = YuvPlane(height, this.width * yPixelStride, yPixelStride);
    final uvWidth = width ~/ 2;
    final uvHeight = height ~/ 2;
    switch (format) {
      case YuvFileFormat.nv21:
        final uvplane = YuvPlane(uvHeight, uvWidth * uvPixelStride, uvPixelStride);
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

  Uint8List getBytes() {
    final WriteBuffer allBytes = WriteBuffer();
    for (final plane in planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();
    return bytes;
  }

  YuvImage copy({bool blank = false}) => YuvImage(
        format,
        width,
        height,
        planes: blank ? null : _planes,
        yPixelStride: y.pixelStride,
        uvPixelStride: u?.pixelStride ?? 1,
      );

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

  factory YuvImage.fromJson(Map<String, dynamic> json, {bool bytesAsBinary = true, bool bytesAsList = false}) {
    YuvFileFormat format = YuvFileFormat.values.byName(json['format']);
    final width = json['width'];
    final height = json['height'];
    final planes = (json['planes'] as Iterable).map((j) => YuvPlane.fromJson(j, bytesAsList: bytesAsList, bytesAsBinary: bytesAsBinary)).toList();
    return YuvImage(format, width, height, planes: planes);
  }

  @override
  String toString() {
    return '$runtimeType($format;$width:$height)';
  }
}
