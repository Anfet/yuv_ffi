import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

class YuvPlane {
  Uint8List get bytes => _bytes;

  late Uint8List _bytes;

  //number of bytes per row
  final int rowStride;

  int get bytesPerRow => rowStride;

  //number of bytes per pixel

  final int pixelStride;

  int get bytesPerPixes => pixelStride;

  final int _height;

  int get height => _height;

  YuvPlane(this._height, this.rowStride, [this.pixelStride = 1, Uint8List? bytes]) {
    _bytes = Uint8List(_height * rowStride);
    if (bytes == null) {
      _bytes.fillRange(0, _height * rowStride, 0);
    } else {
      _bytes.setAll(0, bytes);
    }
  }

  int getPixel(int x, int y) {
    final int index = _indexOf(x, y);
    assert(index >= 0 && index < _bytes.length, "bad index in plane; must be 0 <= '$index' < ${_bytes.length}");
    return _bytes[index];
  }

  void setPixel(int x, int y, int value) {
    final int index = _indexOf(x, y);
    assert(index >= 0 && index < _bytes.length, "bad index in plane; must be 0 <= '$index' < ${_bytes.length}");
    _bytes[index] = value;
  }

  int _indexOf(int x, int y) => (y * rowStride) + (x * pixelStride);

  YuvPlane copy() => YuvPlane(_height, rowStride, pixelStride, _bytes);

  void assignFrom(Uint8List other) => _bytes.setAll(0, other);
}
