import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:yuv_ffi/src/yuv/shared/yuv_file_format.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_geometry.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_pixel_format.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_plane.dart';

/// A fully read and validated payload, before it is applied to an image.
///
/// Decoding produces one of these rather than writing into the target image, so
/// a payload that turns out to be malformed partway through cannot leave an
/// existing image partially overwritten.
///
/// The guarantee is structural: [planes] is unmodifiable, so the list cannot be
/// swapped or resized between validation and commit. Individual [YuvPlane]
/// objects stay mutable — that is the package's public model — but each one here
/// was freshly built by the decoder and is not shared with any caller.
class YuvValidatedImageDraft {
  YuvValidatedImageDraft({required this.format, required this.width, required this.height, required List<YuvPlane> planes})
    : planes = List<YuvPlane>.unmodifiable(planes);

  // ignore: deprecated_member_use_from_same_package
  final YuvFileFormat format;
  final int width;
  final int height;

  /// Decoded planes, in format order. Unmodifiable.
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
/// bytes   header, UTF-8 JSON {version: 2, formatId, width, height}
/// uint8   plane count
/// repeated per plane:
///   uint32  height
///   uint32  rowStride
///   uint32  pixelStride
///   uint32  byte length
///   bytes   plane data
/// ```
///
/// `formatId` is [YuvPixelFormat.wireId] (section 6 of
/// `doc/api-abi-0.4-design.md`), never a Dart enum index and never the legacy
/// string `format` name v1 wrote: index and name both reflect declaration
/// order and would silently renumber or rename a value already on disk.
///
/// Version 1 (the wire shape published in 0.2.4: string `format`, no `formatId`) is
/// read only far enough to recognize and reject it -- there is no v1 writer
/// and no automatic migration. An application holding 0.2.4-era serialized
/// frames must first be read by a 0.2.4 app into an application-owned
/// intermediate representation (format, dimensions, plane strides, and bytes).
/// After upgrading, recreate the image from that representation and encode v2.
///
/// Every malformed, truncated or unsupported payload throws a
/// [FormatException]. Nothing here relies on `assert`, which would disappear in
/// release builds and turn a rejected payload into an out-of-range read.
abstract final class YuvCodec {
  /// Format version written by [encode] and the only one [decode] accepts.
  static const int version = 2;

  /// Largest header block accepted before the JSON is even parsed.
  ///
  /// The header is a handful of scalar fields, so anything larger is a corrupt
  /// or hostile length word rather than a real payload.
  static const int maxHeaderBytes = 64 * 1024;

  /// Largest plane byte length accepted from a payload.
  ///
  /// Checked against the declared geometry before a single byte is buffered, so
  /// a corrupt length word cannot drive an allocation.
  static const int maxPlaneBytes = 1 << 30;

  /// Reverse lookup from the stable wire identity to the enum value, built
  /// once from [YuvPixelFormat.wireId] rather than hand-duplicated so an
  /// added format value is picked up automatically.
  static final Map<int, YuvPixelFormat> _pixelFormatByWireId = <int, YuvPixelFormat>{for (final value in YuvPixelFormat.values) value.wireId: value};

  /// Encodes [format], [width], [height] and [planes] into one byte buffer.
  // ignore: deprecated_member_use_from_same_package
  static Uint8List encode({required YuvFileFormat format, required int width, required int height, required List<YuvPlane> planes}) {
    final header = utf8.encode(
      jsonEncode(<String, Object>{'version': version, 'formatId': format.pixelFormat.wireId, 'width': width, 'height': height}),
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

  /// Reads [stream] sequentially and returns a validated draft.
  ///
  /// The payload is consumed in order — header, then metadata, then one plane at
  /// a time — and never held twice: the reader keeps only the bytes it has not
  /// consumed yet, and hands each finished plane straight to its [YuvPlane].
  /// Metadata is fully validated before the plane it describes is buffered, so a
  /// corrupt length or an impossible geometry is rejected without allocating for
  /// it and without waiting for the stream to close.
  ///
  /// Throws a [FormatException] for a truncated payload, an unknown version or
  /// format, wrong field types, an implausible plane count or length, geometry
  /// the planes cannot satisfy, or unexpected trailing bytes.
  ///
  /// Only version 2 is accepted. A version-1 payload -- the published 0.2.4 wire
  /// shape, keyed by a string `format` name instead of a stable `formatId` --
  /// is rejected with [FormatException] rather than transparently migrated;
  /// there is no v1 writer. A 0.2.4 app must first preserve the decoded frame
  /// in an application-owned intermediate representation; a 0.4.0 app then
  /// recreates it and writes v2.
  static Future<YuvValidatedImageDraft> decodeStream(Stream<List<int>> stream) async {
    final reader = _StreamReader(stream);
    try {
      return await _decodeFrom(reader);
    } finally {
      await reader.cancel();
    }
  }

  /// Decodes a payload already held in memory.
  ///
  /// Shares every check with [decodeStream]; this is the convenience entry for
  /// callers that genuinely have the whole buffer already.
  static Future<YuvValidatedImageDraft> decode(Uint8List bytes) {
    return decodeStream(Stream<List<int>>.value(bytes));
  }

  static Future<YuvValidatedImageDraft> _decodeFrom(_StreamReader reader) async {
    final headerLength = await reader.readUint32('header length');
    if (headerLength > maxHeaderBytes) {
      throw FormatException('Malformed yuv_ffi payload: header declares an implausible length of $headerLength bytes');
    }
    final headerBytes = await reader.readBytes(headerLength, 'header');

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

    final formatId = decoded['formatId'];
    if (formatId is! int) {
      throw const FormatException('Malformed yuv_ffi payload: header formatId is missing or not an integer');
    }
    final pixelFormat = _pixelFormatByWireId[formatId];
    if (pixelFormat == null) {
      throw FormatException('Malformed yuv_ffi payload: unknown formatId $formatId');
    }
    final format = pixelFormat.legacy;

    final width = decoded['width'];
    final height = decoded['height'];
    if (width is! int || height is! int) {
      throw const FormatException('Malformed yuv_ffi payload: width and height must be integers');
    }
    if (width <= 0 || height <= 0) {
      throw FormatException('Malformed yuv_ffi payload: dimensions must be positive, got ${width}x$height');
    }

    final planeCount = await reader.readUint8('plane count');
    final expectedPlaneCount = YuvGeometry.planeCountFor(format);
    if (planeCount != expectedPlaneCount) {
      throw FormatException(
        'Malformed yuv_ffi payload: format ${format.name} requires exactly $expectedPlaneCount plane(s), payload declares $planeCount',
      );
    }

    final planes = <YuvPlane>[];
    // I420 addresses both chroma planes through one shared stride pair, so the
    // second must repeat the first. Remembering it here keeps that cross-plane
    // rule checkable from metadata, before the second body is buffered.
    int? chromaRowStride;
    int? chromaPixelStride;
    for (int i = 0; i < planeCount; i++) {
      final planeHeight = await reader.readUint32('plane $i height');
      final rowStride = await reader.readUint32('plane $i rowStride');
      final pixelStride = await reader.readUint32('plane $i pixelStride');
      final byteLength = await reader.readUint32('plane $i byte length');

      // Everything that can be judged from metadata alone is judged here, before
      // a single byte of this plane is buffered.
      if (byteLength > maxPlaneBytes) {
        throw FormatException('Malformed yuv_ffi payload: plane $i declares an implausible length of $byteLength bytes');
      }
      if (planeHeight * rowStride != byteLength) {
        throw FormatException(
          'Malformed yuv_ffi payload: plane $i declares $byteLength bytes, '
          'which does not match height $planeHeight * rowStride $rowStride',
        );
      }
      if (pixelStride <= 0 || rowStride <= 0) {
        throw FormatException('Malformed yuv_ffi payload: plane $i declares a non-positive stride (rowStride $rowStride, pixelStride $pixelStride)');
      }

      // The header already fixes the format and the image dimensions, so the
      // geometry this plane must have is known now. Checking it here rejects an
      // impossible plane on its metadata instead of first buffering up to
      // maxPlaneBytes and building a YuvPlane only to discard it.
      final expected = YuvGeometry.expectedPlaneMetadata(format: format, width: width, height: height, planeIndex: i, pixelStride: pixelStride);
      if (expected == null) {
        throw FormatException('Malformed yuv_ffi payload: plane $i is not a plane of format ${format.name}');
      }
      if (planeHeight != expected.height) {
        throw FormatException(
          'Malformed yuv_ffi payload: plane $i declares $planeHeight row(s), '
          'but ${format.name} at ${width}x$height requires ${expected.height}',
        );
      }
      if (rowStride < expected.minRowStride) {
        throw FormatException(
          'Malformed yuv_ffi payload: plane $i declares a rowStride of $rowStride, '
          'but ${format.name} at ${width}x$height requires at least ${expected.minRowStride} '
          '(pixelStride $pixelStride)',
        );
      }
      // ignore: deprecated_member_use_from_same_package
      if (format == YuvFileFormat.nv21 && i == 1 && pixelStride < YuvGeometry.nvChromaPixelStride) {
        throw FormatException(
          'Malformed yuv_ffi payload: interleaved NV chroma requires a pixel stride of at least '
          '${YuvGeometry.nvChromaPixelStride}, plane $i declares $pixelStride',
        );
      }
      // ignore: deprecated_member_use_from_same_package
      if (format == YuvFileFormat.i420 && i > 0) {
        // Native code walks both I420 chroma planes with one shared stride pair,
        // so a mismatch would make one of them be read with the other's
        // geometry. The first chroma plane fixes the pair the second must repeat.
        if (chromaRowStride == null) {
          chromaRowStride = rowStride;
          chromaPixelStride = pixelStride;
        } else if (rowStride != chromaRowStride || pixelStride != chromaPixelStride) {
          throw FormatException(
            'Malformed yuv_ffi payload: I420 U and V planes must share the same rowStride and pixelStride, '
            'plane $i declares $rowStride/$pixelStride against $chromaRowStride/$chromaPixelStride',
          );
        }
      }

      final planeBytes = await reader.readBytes(byteLength, 'plane $i data');
      try {
        planes.add(YuvPlane(planeHeight, rowStride, pixelStride, planeBytes));
      } on ArgumentError catch (error) {
        throw FormatException('Malformed yuv_ffi payload: plane $i geometry is invalid (${error.message})');
      }
    }

    // EOF is the frame boundary. A version-1 payload carries no outer length, so
    // the only thing that can prove nothing follows the last plane is the end of
    // the stream itself. Waiting for it is what makes the rejection of trailing
    // bytes a guarantee rather than a race against the scheduler.
    if (!await reader.atEnd()) {
      throw const FormatException('Malformed yuv_ffi payload: unexpected trailing byte(s)');
    }

    try {
      // Codec v2 preserves caller-declared strides. A semi-planar payload with
      // a chroma pixel stride above two is the public nv12 layout with a real
      // gap, not malformed legacy nv21 data.
      YuvGeometry.validateImage(
        format: format,
        width: width,
        height: height,
        planes: planes,
        // ignore: deprecated_member_use_from_same_package
        allowLargerNvChromaStride: format == YuvFileFormat.nv21,
      );
    } on ArgumentError catch (error) {
      throw FormatException('Malformed yuv_ffi payload: ${error.message}');
    }

    return YuvValidatedImageDraft(format: format, width: width, height: height, planes: planes);
  }
}

/// Pulls bytes from a chunked stream in order, buffering only what is pending.
///
/// Consumed bytes are dropped as soon as a read completes, so the payload is
/// never held in full alongside a second copy of itself. A read that needs more
/// bytes than have arrived waits for the next chunk; a stream that ends first is
/// a truncated payload.
class _StreamReader {
  _StreamReader(Stream<List<int>> stream) : _subscription = StreamIterator<List<int>>(stream);

  final StreamIterator<List<int>> _subscription;

  /// Chunks received but not yet fully consumed.
  final List<Uint8List> _pending = <Uint8List>[];

  /// Offset into `_pending.first` of the next unread byte.
  int _offset = 0;

  /// Unread bytes currently buffered.
  int _available = 0;

  bool _exhausted = false;

  Future<void> cancel() => _subscription.cancel();

  /// Pulls one more chunk. Returns false when the stream is finished.
  Future<bool> _pull() async {
    if (_exhausted) {
      return false;
    }
    final moved = await _subscription.moveNext();
    if (!moved) {
      _exhausted = true;
      return false;
    }
    final chunk = _subscription.current;
    if (chunk.isEmpty) {
      return _pull();
    }
    final bytes = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
    _pending.add(bytes);
    _available += bytes.length;
    return true;
  }

  Future<void> _require(int count, String what) async {
    if (count < 0) {
      throw FormatException('Malformed yuv_ffi payload: negative length for $what');
    }
    while (_available < count) {
      if (!await _pull()) {
        throw FormatException('Truncated yuv_ffi payload: $what needs $count byte(s), only $_available remain');
      }
    }
  }

  /// Copies [count] pending bytes out, releasing every chunk it drains.
  Uint8List _take(int count) {
    final out = Uint8List(count);
    int written = 0;
    while (written < count) {
      final chunk = _pending.first;
      final fromChunk = chunk.length - _offset;
      final needed = count - written;
      final take = fromChunk < needed ? fromChunk : needed;
      out.setRange(written, written + take, chunk, _offset);
      written += take;
      _offset += take;
      if (_offset == chunk.length) {
        // Drop the chunk as soon as it is spent, so consumed bytes are not
        // retained for the life of the read.
        _pending.removeAt(0);
        _offset = 0;
      }
    }
    _available -= count;
    return out;
  }

  Future<int> readUint8(String what) async {
    await _require(1, what);
    return _take(1)[0];
  }

  Future<int> readUint32(String what) async {
    await _require(4, what);
    final bytes = _take(4);
    return ByteData.view(bytes.buffer, bytes.offsetInBytes, 4).getUint32(0, Endian.little);
  }

  Future<Uint8List> readBytes(int count, String what) async {
    await _require(count, what);
    return _take(count);
  }

  /// Whether the stream is genuinely finished, with no byte left over.
  ///
  /// Waits for the end of the stream rather than sampling what happens to be
  /// buffered. A file delivers a trailer in a later chunk as readily as in the
  /// same one, so a decoder that only inspected the current buffer would accept
  /// or reject the same payload depending on how it was chunked and on when the
  /// scheduler ran — the format contract would then hold only by luck.
  ///
  /// The cost is that a source which never closes never finishes decoding. That
  /// is inherent to a version-1 payload: it carries no outer frame length, so
  /// EOF is the only boundary there is. Decoding a frame from a stream that
  /// stays open needs a framed protocol, not a timeout guessing at one.
  Future<bool> atEnd() async {
    if (_available > 0) {
      return false;
    }
    while (!_exhausted) {
      if (await _pull()) {
        return false;
      }
    }
    return true;
  }
}
