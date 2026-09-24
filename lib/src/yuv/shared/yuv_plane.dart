import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// Describes a single image plane.
///
/// Plane bytes are stored row-by-row with [rowStride] and [pixelStride].
class YuvPlane {
  /// Underlying mutable bytes.
  ///
  /// Writes through this buffer cannot be intercepted, so they do not bump the
  /// owning image's revision. Call `YuvImage.markDirty()` afterwards, otherwise
  /// a widget may keep rendering the previous frame from the image cache.
  Uint8List get bytes => _bytes;

  late Uint8List _bytes;

  /// Number of bytes per row.
  final int rowStride;

  /// Alias for [rowStride].
  int get bytesPerRow => rowStride;

  /// Number of bytes per pixel element in this plane.
  final int pixelStride;

  /// Alias for [pixelStride].
  int get bytesPerPixel => pixelStride;

  /// Alias for [pixelStride].
  ///
  /// The name is a typo kept as a forwarding alias so a patch update does not
  /// break existing callers. Use [bytesPerPixel].
  @Deprecated('Use bytesPerPixel instead. This misspelled alias will be removed in a future major release.')
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
  /// Throws an [ArgumentError] when [height], [rowStride] or [pixelStride] is
  /// negative, or when [bytes] does not hold exactly `height * rowStride`
  /// elements. A short buffer is rejected rather than silently zero-padded,
  /// because native code walks the plane by its declared geometry.
  YuvPlane(this._height, this.rowStride, [this.pixelStride = 1, Uint8List? bytes]) {
    if (_height < 0) {
      throw ArgumentError.value(_height, 'height', 'Plane height must not be negative');
    }
    if (rowStride < 0) {
      throw ArgumentError.value(rowStride, 'rowStride', 'Row stride must not be negative');
    }
    if (pixelStride < 0) {
      throw ArgumentError.value(pixelStride, 'pixelStride', 'Pixel stride must not be negative');
    }

    final expectedLength = _height * rowStride;
    if (bytes != null && bytes.length != expectedLength) {
      throw ArgumentError.value(bytes.length, 'bytes.length', 'Expected exactly $expectedLength bytes (height $_height * rowStride $rowStride)');
    }

    _bytes = Uint8List(expectedLength);
    if (bytes != null) {
      _bytes.setAll(0, bytes);
    }
  }

  /// Returns a single byte value at pixel coordinate `[x, y]`.
  ///
  /// Throws an [ArgumentError] for an out-of-range coordinate or a zero
  /// [pixelStride], identically in debug and release builds.
  int getPixel(int x, int y) {
    final int index = _checkedIndexOf(x, y);
    return _bytes[index];
  }

  /// Sets a single byte [value] at pixel coordinate `[x, y]`.
  ///
  /// Throws an [ArgumentError] for an out-of-range coordinate or a zero
  /// [pixelStride], identically in debug and release builds.
  ///
  /// A plane does not know which image owns it, so this does not bump that
  /// image's revision. Call `YuvImage.markDirty()` after a batch of writes.
  void setPixel(int x, int y, int value) {
    final int index = _checkedIndexOf(x, y);
    _bytes[index] = value;
  }

  /// Validates [x] and [y] before they ever combine into a flat buffer index.
  ///
  /// `x` is bound-checked via `(rowStride - 1) ~/ pixelStride` rather than by
  /// computing `x * pixelStride` and comparing it against `rowStride`: for a
  /// huge `x` that multiplication can overflow the 64-bit `int` range and wrap
  /// into a value that a naive comparison would accept. Dividing the other way
  /// keeps every intermediate value within the legal coordinate range.
  int _checkedIndexOf(int x, int y) {
    if (y < 0 || y >= _height) {
      throw ArgumentError.value(y, 'y', 'Must satisfy 0 <= y < $_height');
    }
    if (x < 0) {
      throw ArgumentError.value(x, 'x', 'Must not be negative');
    }
    if (pixelStride == 0) {
      throw ArgumentError.value(pixelStride, 'pixelStride', 'Pixel stride must not be zero');
    }
    final int maxX = (rowStride - 1) ~/ pixelStride;
    if (x > maxX) {
      throw ArgumentError.value(x, 'x', 'Must not exceed $maxX for rowStride $rowStride and pixelStride $pixelStride');
    }

    final int index = (y * rowStride) + (x * pixelStride);
    assert(index >= 0 && index < _bytes.length, "bad index in plane; must be 0 <= '$index' < ${_bytes.length}");
    return index;
  }

  /// Creates a deep copy of this plane.
  YuvPlane copy() => YuvPlane(_height, rowStride, pixelStride, _bytes);

  /// Replaces this plane content with [other].
  ///
  /// [other] must hold exactly `bytes.length` bytes, so the documented full
  /// overwrite really happens. A shorter input would leave a stale tail and a
  /// longer one would not fit.
  ///
  /// Throws an [ArgumentError] when [other] has a different length.
  ///
  /// A plane does not know which image owns it, so this does not bump that
  /// image's revision. Call `YuvImage.markDirty()` when writing planes
  /// directly. The backends bump the revision themselves around their own
  /// internal use of this method.
  void assignFrom(Uint8List other) {
    if (other.length != _bytes.length) {
      throw ArgumentError.value(other.length, 'other.length', 'Expected exactly ${_bytes.length} bytes to fully overwrite this plane');
    }
    _bytes.setAll(0, other);
  }

  @override
  String toString() {
    final estimatedWidth = pixelStride == 0 ? 0 : rowStride ~/ pixelStride;
    return 'YuvPlane(height: $height, rowStride: $rowStride, '
        'pixelStride: $pixelStride, estimatedWidth: $estimatedWidth, '
        'bytes: ${_bytes.length})';
  }
}
