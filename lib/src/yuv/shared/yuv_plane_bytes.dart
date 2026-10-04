import 'dart:typed_data';

import 'package:yuv_ffi/src/yuv/shared/yuv_plane.dart';

/// Shared plane-buffer concatenation for every backend.
///
/// Both the native (`io`) and the Web (`wasm`) implementations expose the same
/// public `getBytes()` contract: all planes concatenated into a single byte
/// buffer, in format order, with nothing after the last byte of the last plane.
abstract final class YuvPlaneBytes {
  /// Concatenates the bytes of [planes] in the order they are given.
  ///
  /// The result is exactly `sum(plane.bytes.length)` bytes long. A previous
  /// implementation built this through a [WriteBuffer], whose backing
  /// `ByteBuffer` grows in powers of two, so `buffer.asUint8List()` exposed an
  /// alignment tail of zeros that belonged to no plane at all.
  ///
  /// The returned buffer is an independent copy: writing to it does not change
  /// any plane, and mutating a plane afterwards does not change a buffer that
  /// was already returned.
  static Uint8List concat(Iterable<YuvPlane> planes) {
    final sources = <Uint8List>[for (final plane in planes) plane.bytes];

    int totalLength = 0;
    for (final source in sources) {
      totalLength += source.length;
    }

    final result = Uint8List(totalLength);
    int offset = 0;
    for (final source in sources) {
      result.setRange(offset, offset + source.length, source);
      offset += source.length;
    }
    return result;
  }
}
