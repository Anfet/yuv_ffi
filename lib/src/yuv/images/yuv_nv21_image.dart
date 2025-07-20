import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:yuv_ffi/src/loader/loader.dart';

import '../yuv_image.dart';
import '../yuv_planes.dart';

@immutable
class YuvNV21Image extends YuvImage {
  @override
  final YuvFileFormat format = YuvFileFormat.nv21;

  @override
  final int width;

  @override
  final int height;

  @override
  late final List<YuvPlane> planes;

  @override
  YuvPlane get uPlane => throw UnimplementedError();

  @override
  YuvPlane get vPlane => throw UnimplementedError();

  @override
  YuvPlane get yPlane => throw UnimplementedError();

  YuvNV21Image.fromPlanes(this.width, this.height, this.planes);

  YuvNV21Image(this.width, this.height) {
    final yplane = YuvPlane.empty(width, height, 1);
    final uvWidth = (width / 2).round();
    final uvHeight = (height / 2).round();
    final uvplane = YuvPlane.empty(uvWidth, uvHeight, 2);
    planes = List.unmodifiable([yplane, uvplane]);
  }

  YuvNV21Image._(this.width, this.height, this.planes);

  @override
  YuvNV21Image create(int width, int height) => YuvNV21Image(width, height);

  @override
  Uint8List toBgra8888() {
    final (_, yPtr) = yPlane.allocatePtr();
    final bgraBufferLength = width * height * 4;
    final bgraPtr = calloc.allocate<Uint8>(bgraBufferLength);
    try {
      ffiBingings.nv21_to_rgb(yPtr, bgraPtr, width, height);
      final result = Uint8List.fromList(bgraPtr.asTypedList(bgraBufferLength));
      return result;
    } finally {
      calloc.free(yPtr);
      calloc.free(bgraPtr);
    }
  }

  @override
  YuvImage copy() {
    var planes = this.planes.map((p) => p.copy());
    return YuvNV21Image.fromPlanes(width, height, List.of(planes));
  }

  @override
  void fromRgba8888(Uint8List bytes) {
    // TODO: implement loadRgbaBytes
  }

  @override
  Map<String, dynamic> toMap() {
    // TODO: implement toMap
    throw UnimplementedError();
  }
}
