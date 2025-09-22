import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
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

  YuvPlane(this._height, this.rowStride, [this.pixelStride = 1, Uint8List? bytes]) {
    _bytes = Uint8List(_height * rowStride * pixelStride);
    if (bytes == null) {
      _bytes.fillRange(0, _height * rowStride * pixelStride, 0);
    } else {
      _bytes.setAll(0, bytes);
    }
  }

  YuvPlane.fromJson(Map<String, dynamic> json, {bool bytesAsBinary = true, bool bytesAsList = false})
      : _height = json['height'],
        rowStride = json['rowStride'],
        pixelStride = json['pixelStride'],
        _bytes = bytesAsBinary
            ? base64Decode(json['bytes'])
            : bytesAsList
                ? json['bytes']
                : throw UnsupportedError('bytesAsBinary or bytesAsList should be set');

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

  Map<String, dynamic> toJson({bool bytesAsBinary = true, bool bytesAsList = false}) {
    assert(bytesAsBinary || bytesAsList, 'bytesAsBinary or bytesAsList should be set');
    return {
      'height': _height,
      'rowStride': rowStride,
      'pixelStride': pixelStride,
      if (bytesAsBinary) 'bytes': base64Encode(_bytes),
      if (bytesAsList) 'bytes': _bytes,
    };
  }

  @Deprecated('message')
  static (int, Pointer<Uint8>) allocate(int size) {
    final ptr = calloc.allocate<Uint8>(size);
    ptr.asTypedList(size).fillRange(0, size, 0);
    return (size, ptr);
  }

  @Deprecated('message')
  (int, Pointer<Uint8>) allocatePtr() {
    final size = _bytes.length;
    final ptr = calloc.allocate<Uint8>(size);
    ptr.asTypedList(size).setAll(0, _bytes);
    return (size, ptr);
  }

  YuvPlane copy() => YuvPlane(_height, rowStride, pixelStride, _bytes);
}

extension YuvPlaneLoaderExt on YuvPlane {
  void assignFromPtr(Pointer<Uint8> ptr) => _bytes.setAll(0, ptr.asTypedList(_bytes.length));
}
