import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// Describes a single image plane.
///
/// Plane bytes are stored row-by-row with [rowStride] and [pixelStride].
class YuvPlane {
  /// Underlying mutable bytes.
  Uint8List get bytes => _bytes;

  late Uint8List _bytes;

  /// Number of bytes per row.
  final int rowStride;

  /// Alias for [rowStride].
  int get bytesPerRow => rowStride;

  /// Number of bytes per pixel element in this plane.
  final int pixelStride;

  /// Alias for [pixelStride].
  int get bytesPerPixes => pixelStride;

  final int _height;

  /// Plane height in rows.
  int get height => _height;

  /// Creates a plane.
  ///
  /// If [bytes] is omitted, the plane is initialized with zeros.
  YuvPlane(this._height, this.rowStride, [this.pixelStride = 1, Uint8List? bytes]) {
    _bytes = Uint8List(_height * rowStride);
    if (bytes == null) {
      _bytes.fillRange(0, _height * rowStride, 0);
    } else {
      _bytes.setAll(0, bytes);
    }
  }

  /// Returns value at pixel coordinate.
  int getPixel(int x, int y) {
    final int index = _indexOf(x, y);
    assert(index >= 0 && index < _bytes.length, "bad index in plane; must be 0 <= '$index' < ${_bytes.length}");
    return _bytes[index];
  }

  /// Sets value at pixel coordinate.
  void setPixel(int x, int y, int value) {
    final int index = _indexOf(x, y);
    assert(index >= 0 && index < _bytes.length, "bad index in plane; must be 0 <= '$index' < ${_bytes.length}");
    _bytes[index] = value;
  }

  int _indexOf(int x, int y) => (y * rowStride) + (x * pixelStride);

  /// Creates a deep copy of this plane.
  YuvPlane copy() => YuvPlane(_height, rowStride, pixelStride, _bytes);

  /// Replaces this plane content with [other].
  void assignFrom(Uint8List other) => _bytes.setAll(0, other);
}
