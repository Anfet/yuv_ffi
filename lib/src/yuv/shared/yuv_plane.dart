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
  /// [height] is the number of rows in the plane.
  /// [rowStride] is the number of bytes per row.
  /// [pixelStride] is the byte step between neighboring pixels in a row.
  ///
  /// If [bytes] is omitted, the plane is initialized with zeros.
  ///
  /// Throws a [RangeError] if [bytes] has fewer than `height * rowStride`
  /// elements.
  YuvPlane(this._height, this.rowStride, [this.pixelStride = 1, Uint8List? bytes]) {
    _bytes = Uint8List(_height * rowStride);
    if (bytes == null) {
      _bytes.fillRange(0, _height * rowStride, 0);
    } else {
      _bytes.setAll(0, bytes);
    }
  }

  /// Returns a single byte value at pixel coordinate `[x, y]`.
  ///
  /// In debug mode, asserts when computed index is out of bounds.
  /// In release mode, out-of-bounds access throws at runtime.
  int getPixel(int x, int y) {
    final int index = _indexOf(x, y);
    assert(index >= 0 && index < _bytes.length, "bad index in plane; must be 0 <= '$index' < ${_bytes.length}");
    return _bytes[index];
  }

  /// Sets a single byte [value] at pixel coordinate `[x, y]`.
  ///
  /// In debug mode, asserts when computed index is out of bounds.
  /// In release mode, out-of-bounds access throws at runtime.
  void setPixel(int x, int y, int value) {
    final int index = _indexOf(x, y);
    assert(index >= 0 && index < _bytes.length, "bad index in plane; must be 0 <= '$index' < ${_bytes.length}");
    _bytes[index] = value;
  }

  int _indexOf(int x, int y) => (y * rowStride) + (x * pixelStride);

  /// Creates a deep copy of this plane.
  YuvPlane copy() => YuvPlane(_height, rowStride, pixelStride, _bytes);

  /// Replaces this plane content with [other].
  ///
  /// [other] must have at least [bytes.length] bytes.
  /// Throws a [RangeError] when [other] is shorter.
  void assignFrom(Uint8List other) => _bytes.setAll(0, other);

  @override
  String toString() {
    final estimatedWidth = pixelStride == 0 ? 0 : rowStride ~/ pixelStride;
    return 'YuvPlane(height: $height, rowStride: $rowStride, '
        'pixelStride: $pixelStride, estimatedWidth: $estimatedWidth, '
        'bytes: ${_bytes.length})';
  }
}
