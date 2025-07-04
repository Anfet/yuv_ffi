import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'package:flutter/foundation.dart';

class YuvPlane {
  final String? name;

  final Uint8List bytes;

  //number of bytes per row
  final int rowStride;

  int get bytesPerRow => rowStride;

  //number of bytes per pixel
  final int pixelStride;

  int get bytesPerPixes => pixelStride;

  int get width => (rowStride / pixelStride).round();

  int get height => (bytes.length / rowStride).round();

  YuvPlane.fromBytes(Uint8List bytes, this.pixelStride, this.rowStride, {this.name}) : bytes = Uint8List.fromList(bytes);

  YuvPlane.empty(int width, int height, this.pixelStride, {this.name})
      : rowStride = pixelStride * width,
        bytes = Uint8List(height * pixelStride * width)..fillRange(0, height * pixelStride * width, 0);

  YuvPlane.fromJson(Map<String, dynamic> json)
      : name = json['name'],
        rowStride = json['rowStride'],
        pixelStride = json['pixelStride'],
        bytes = base64Decode(json['bytes']);

  int getPixel(int x, int y) {
    assert(x >= 0 && x < width, "bad x in plane '$name'; 0 <= '$x' < $width");
    assert(y >= 0 && y < height, "bad y in plane '$name'; 0 <= '$y' < $height");

    final int index = _indexOf(x, y);
    assert(index >= 0 && index < bytes.length, "bad index in plane '$name'; must be 0 <= '$index' < ${bytes.length}");
    return bytes[index];
  }

  void setPixel(int x, int y, int value) {
    assert(x >= 0 && x < width, "bad x in plane '$name'; 0 <= '$x' < $width");
    assert(y >= 0 && y < height, "bad y in plane '$name'; 0 <= '$y' < $height");

    final int index = _indexOf(x, y);
    assert(index >= 0 && index < bytes.length, "bad index in plane '$name'; must be 0 <= '$index' < ${bytes.length}");
    bytes[index] = value;
  }

  YuvPlane copy() => YuvPlane.fromBytes(Uint8List.fromList(bytes), pixelStride, rowStride);

  Uint8List copyBytes(int row, int start, int numberOfPixels) => bytes.sublist(_indexOf(start, row), _indexOf(start + numberOfPixels, row));

  void pasteBytes(int row, int start, Uint8List bytes) {
    final int index = _indexOf(start, row);
    this.bytes.setRange(index, index + bytes.length, bytes);
  }

  int _indexOf(int x, int y) => (y * rowStride) + (x * pixelStride);

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'rowStride': rowStride,
      'pixelStride': pixelStride,
      'bytes': base64Encode(bytes),
    };
  }

  static (int, Pointer<Uint8>) allocate(int size) {
    final ptr = calloc.allocate<Uint8>(size);
    ptr.asTypedList(size).fillRange(0, size, 0);
    return (size, ptr);
  }

  (int, Pointer<Uint8>) allocatePtr() {
    final size = width * height * pixelStride;
    final ptr = calloc.allocate<Uint8>(size);
    ptr.asTypedList(size).setAll(0, bytes);
    return (size, ptr);
  }
}
