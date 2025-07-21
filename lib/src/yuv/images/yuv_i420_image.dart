import 'package:flutter/foundation.dart';
import 'package:yuv_ffi/src/functions/rgba8888.dart';

import '../yuv_image.dart';
import '../yuv_planes.dart';

class Yuv420Image extends YuvImage {
  @override
  final YuvFileFormat format = YuvFileFormat.i420;

  @override
  int get width => _width;

  int _width;

  @override
  int get height => _height;

  int _height;

  @override
  List<YuvPlane> get planes => List.unmodifiable(_planes);

  late List<YuvPlane> _planes;

  @override
  YuvPlane get yPlane => _planes[0];

  @override
  YuvPlane get uPlane => _planes[1];

  @override
  YuvPlane get vPlane => _planes[2];

  Yuv420Image._(this._width, this._height, this._planes);

  Yuv420Image(this._width, this._height, [int yPixelStride = 1, int uvPixelStride = 1]) {
    final yplane = YuvPlane(_height, this._width * yPixelStride, yPixelStride);
    final uvWidth = width ~/ 2;
    final uvHeight = height ~/ 2;
    final uplane = YuvPlane(uvHeight, uvWidth * uvPixelStride, uvPixelStride);
    final vplane = YuvPlane(uvHeight, uvWidth * uvPixelStride, uvPixelStride);
    _planes = [yplane, uplane, vplane];
  }

  Yuv420Image.fromPlanes(this._width, this._height, this._planes);

  @override
  Yuv420Image create(int width, int height) => Yuv420Image(width, height);

  @override
  YuvImage copy() {
    var planes = this._planes.map((p) => p.copy());
    return Yuv420Image.fromPlanes(width, height, List.of(planes));
  }

  static YuvImage fromRGBA(Uint8List rgbaBuffer, int width, int height) {
    final image = Yuv420Image(width, height);
    image.fromRgba8888(rgbaBuffer);
    return image;
  }
}
