import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:yuv_ffi/src/functions/rgba8888.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

enum YuvFileFormat {
  nv21,
  i420,
  ;
}

abstract class YuvImage {
  YuvFileFormat get format;

  int get width;

  int get height;

  List<YuvPlane> get planes;

  YuvPlane get yPlane;

  YuvPlane get uPlane;

  YuvPlane get vPlane;

  Size get size => Size(width.toDouble(), height.toDouble());

  Uint8List getBytes() {
    final WriteBuffer allBytes = WriteBuffer();
    for (final plane in planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();
    return bytes;
  }

  YuvImage create(int width, int height);

  YuvImage copy();

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

  static YuvImage fromJson(Map<String, dynamic> json, {bool bytesAsBinary = true, bool bytesAsList = false}) {
    YuvFileFormat format = YuvFileFormat.values.byName(json['format']);
    final width = json['width'];
    final height = json['height'];
    final planes = (json['planes'] as Iterable).map((j) => YuvPlane.fromJson(j, bytesAsList: bytesAsList, bytesAsBinary: bytesAsBinary)).toList();
    return switch (format) {
      YuvFileFormat.nv21 => YuvNV21Image.fromPlanes(width, height, planes),
      YuvFileFormat.i420 => Yuv420Image.fromPlanes(width, height, planes),
    };
  }

  @override
  String toString() {
    return '$runtimeType($width:$height)';
  }
}
