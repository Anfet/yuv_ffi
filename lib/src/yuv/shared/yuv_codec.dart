import 'dart:convert';
import 'dart:typed_data';

import 'package:yuv_ffi/src/yuv/shared/yuv_file_format.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_geometry.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_plane.dart';

/// Fully parsed image payload, before it is applied to an image.
///
/// Decoding produces one of these rather than writing into the target image, so
/// a payload that turns out to be malformed halfway through cannot leave an
/// existing image partially overwritten.
class YuvImageDraft {
  YuvImageDraft({
    required this.format,
    required this.width,
    required this.height,
    required this.planes,
  });

  final YuvFileFormat format;
  final int width;
  final int height;
  final List<YuvPlane> planes;
}

/// Shared versioned serialization format for every backend.
///
/// The native (`io`) and Web (`wasm`) backends use this one codec, so a file
/// written on one platform reads back identically on the other and both apply
/// the same validation policy.
///
/// Layout, all integers little-endian:
///
/// ```text
/// uint32  header length
/// bytes   header, UTF-8 JSON {version, format, width, height}
/// uint8   plane count
/// repeated per plane:
///   uint32  height
///   uint32  rowStride
///   uint32  pixelStride
///   uint32  byte length
///   bytes   plane data
/// ```
///
/// Every malformed, truncated or unsupported payload throws a
/// [FormatException]. Nothing here relies on `assert`, which would disappear in
/// release builds and turn a rejected payload into an out-of-range read.
abstract final class YuvCodec {
  /// Format version written by [encode] and the only one [decode] accepts.
  static const int version = 1;

  /// Largest plane byte length accepted from a payload.
  ///
  /// This is not a picture-size limit: it exists so a corrupt length word
  /// cannot make the decoder try to allocate gigabytes before the geometry
  /// check runs. Real planes are validated against the declared geometry
  /// immediately afterwards.
  static const int maxPlaneBytes = 1 << 30;

  /// Largest whole payload accepted by [collect].
  ///
  /// Generous enough for any real frame this package produces, while keeping an
  /// endless or corrupt stream from being accumulated without limit.
  static const int maxPayloadBytes = 1 << 31;

  /// Encodes [format], [width], [height] and [planes] into one byte buffer.
  static Uint8List encode({
    required YuvFileFormat format,
    required int width,
    required int height,
    required List<YuvPlane> planes,
  }) {
    final header = utf8.encode(
      jsonEncode(<String, Object>{
        'version': version,
        'format': format.name,
        'width': width,
        'height': height,
      }),
    );

    int total = 4 + header.length + 1;
    for (final plane in planes) {
      total += 4 * 4 + plane.bytes.length;
    }

    final out = Uint8List(total);
    final view = ByteData.view(out.buffer);
    int offset = 0;

    view.setUint32(offset, header.length, Endian.little);
    offset += 4;
    out.setRange(offset, offset + header.length, header);
    offset += header.length;

    view.setUint8(offset, planes.length);
    offset += 1;

    for (final plane in planes) {
      view.setUint32(offset, plane.height, Endian.little);
      offset += 4;
      view.setUint32(offset, plane.rowStride, Endian.little);
      offset += 4;
      view.setUint32(offset, plane.pixelStride, Endian.little);
      offset += 4;
      view.setUint32(offset, plane.bytes.length, Endian.little);
      offset += 4;
      out.setRange(offset, offset + plane.bytes.length, plane.bytes);
      offset += plane.bytes.length;
    }

    return out;
  }

  /// Collects [stream] into one buffer for [decode].
  ///
  /// A chunked stream is joined here rather than in each backend, so both read
  /// the identical bytes regardless of how the source was fragmented. The
  /// payload is bounded by [maxPayloadBytes]: an endless or absurd stream is
  /// rejected instead of being accumulated until the process dies.
  static Future<Uint8List> collect(Stream<List<int>> stream) async {
    final chunks = <List<int>>[];
    int total = 0;
    await for (final chunk in stream) {
      total += chunk.length;
      if (total > maxPayloadBytes) {
        throw FormatException('Malformed yuv_ffi payload: exceeds the $maxPayloadBytes byte limit');
      }
      chunks.add(chunk);
    }

    final out = Uint8List(total);
    int offset = 0;
    for (final chunk in chunks) {
      out.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return out;
  }

  /// Decodes [bytes] into a validated draft.
  ///
  /// Throws a [FormatException] for a truncated payload, an unknown version or
  /// format, wrong field types, an implausible plane count or length, geometry
  /// the planes cannot satisfy, or unexpected trailing bytes.
  static YuvImageDraft decode(Uint8List bytes) {
    final cursor = _Cursor(bytes);

    final headerLength = cursor.readUint32('header length');
    final headerBytes = cursor.readBytes(headerLength, 'header');

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(headerBytes));
    } on FormatException catch (error) {
      throw FormatException('Malformed yuv_ffi payload: header is not valid UTF-8 JSON (${error.message})');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Malformed yuv_ffi payload: header is not a JSON object');
    }

    final payloadVersion = decoded['version'];
    if (payloadVersion is! int) {
      throw const FormatException('Malformed yuv_ffi payload: header version is missing or not an integer');
    }
    if (payloadVersion != version) {
      throw FormatException('Unsupported yuv_ffi payload version $payloadVersion; this build reads version $version');
    }

    final formatName = decoded['format'];
    if (formatName is! String) {
      throw const FormatException('Malformed yuv_ffi payload: header format is missing or not a string');
    }
    final YuvFileFormat format;
    try {
      format = YuvFileFormat.values.byName(formatName);
    } on ArgumentError {
      // byName throws ArgumentError, but an unknown format is a payload defect
      // and the public contract promises FormatException.
      throw FormatException('Malformed yuv_ffi payload: unknown format "$formatName"');
    }

    final width = decoded['width'];
    final height = decoded['height'];
    if (width is! int || height is! int) {
      throw const FormatException('Malformed yuv_ffi payload: width and height must be integers');
    }
    if (width <= 0 || height <= 0) {
      throw FormatException('Malformed yuv_ffi payload: dimensions must be positive, got ${width}x$height');
    }

    final planeCount = cursor.readUint8('plane count');
    final expectedPlaneCount = YuvGeometry.planeCountFor(format);
    if (planeCount != expectedPlaneCount) {
      throw FormatException(
        'Malformed yuv_ffi payload: format ${format.name} requires exactly $expectedPlaneCount plane(s), payload declares $planeCount',
      );
    }

    final planes = <YuvPlane>[];
    for (int i = 0; i < planeCount; i++) {
      final planeHeight = cursor.readUint32('plane $i height');
      final rowStride = cursor.readUint32('plane $i rowStride');
      final pixelStride = cursor.readUint32('plane $i pixelStride');
      final byteLength = cursor.readUint32('plane $i byte length');

      if (byteLength > maxPlaneBytes) {
        throw FormatException('Malformed yuv_ffi payload: plane $i declares an implausible length of $byteLength bytes');
      }
      // The declared length is checked against what is actually left before it
      // is trusted for anything.
      final planeBytes = cursor.readBytes(byteLength, 'plane $i data');

      if (planeHeight * rowStride != byteLength) {
        throw FormatException(
          'Malformed yuv_ffi payload: plane $i declares $byteLength bytes, '
          'which does not match height $planeHeight * rowStride $rowStride',
        );
      }

      try {
        planes.add(YuvPlane(planeHeight, rowStride, pixelStride, planeBytes));
      } on ArgumentError catch (error) {
        throw FormatException('Malformed yuv_ffi payload: plane $i geometry is invalid (${error.message})');
      }
    }

    if (!cursor.atEnd) {
      throw FormatException('Malformed yuv_ffi payload: ${cursor.remaining} unexpected trailing byte(s)');
    }

    try {
      YuvGeometry.validateImage(format: format, width: width, height: height, planes: planes);
    } on ArgumentError catch (error) {
      throw FormatException('Malformed yuv_ffi payload: ${error.message}');
    }

    return YuvImageDraft(format: format, width: width, height: height, planes: planes);
  }
}

/// Reads forward through a buffer, checking what remains rather than the total.
///
/// The previous reader compared against the whole buffer length, so a payload
/// truncated in the middle passed every check and then read out of range.
class _Cursor {
  _Cursor(this._bytes) : _view = ByteData.view(_bytes.buffer, _bytes.offsetInBytes, _bytes.lengthInBytes);

  final Uint8List _bytes;
  final ByteData _view;
  int _offset = 0;

  int get remaining => _bytes.lengthInBytes - _offset;

  bool get atEnd => remaining == 0;

  void _require(int count, String what) {
    if (count < 0) {
      throw FormatException('Malformed yuv_ffi payload: negative length for $what');
    }
    if (remaining < count) {
      throw FormatException('Truncated yuv_ffi payload: $what needs $count byte(s), only $remaining remain');
    }
  }

  int readUint8(String what) {
    _require(1, what);
    final value = _view.getUint8(_offset);
    _offset += 1;
    return value;
  }

  int readUint32(String what) {
    _require(4, what);
    final value = _view.getUint32(_offset, Endian.little);
    _offset += 4;
    return value;
  }

  Uint8List readBytes(int count, String what) {
    _require(count, what);
    // A copy, so the decoded image never aliases the caller's payload buffer.
    final value = Uint8List.fromList(Uint8List.sublistView(_bytes, _offset, _offset + count));
    _offset += count;
    return value;
  }
}
