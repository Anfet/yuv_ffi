import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

const _width = 1281;
const _height = 721;
const _warmup = 5;
const _runs = 30;
const _fnvBasis = 0xcbf29ce484222325;
const _fnvPrime = 0x100000001b3;
const _mask64 = 0xffffffffffffffff;

final class _Plane extends Struct {
  @Uint64()
  external int length;
  @Uint64()
  external int rowStride;
  @Uint32()
  external int pixelStride;
  @Uint32()
  external int sampleBytes;
  external Pointer<Uint8> data;
}

final class _Frame extends Struct {
  @Uint32()
  external int structSize;
  @Uint32()
  external int abiVersion;
  @Uint32()
  external int format;
  @Uint32()
  external int planeCount;
  @Uint32()
  external int width;
  @Uint32()
  external int height;
  @Uint32()
  external int colorMatrix;
  @Uint32()
  external int colorRange;
  @Array.multi([3])
  external Array<_Plane> planes;
  @Array.multi([4])
  external Array<Uint64> reserved;
}

final class _Options extends Struct {
  @Uint32()
  external int structSize;
  @Uint32()
  external int abiVersion;
  @Array.multi([3])
  external Array<Uint64> reserved;
}

typedef _NativeConvert =
    Int32 Function(Pointer<_Frame>, Pointer<_Frame>, Pointer<_Options>);
typedef _DartConvert =
    int Function(Pointer<_Frame>, Pointer<_Frame>, Pointer<_Options>);

const _formats = [1, 2, 3, 4];
const _destinations = [1, 2, 3];
const _names = ['unused', 'I420', 'NV12', 'BGRA', 'RGBA'];

void main() {
  final path = Platform.environment['YUV_FFI_DLL'];
  if (!Platform.isWindows || path == null || !File(path).existsSync()) {
    throw StateError('Set YUV_FFI_DLL to the Windows Release yuv_ffi.dll');
  }
  final convert = DynamicLibrary.open(
    path,
  ).lookupFunction<_NativeConvert, _DartConvert>('yuv_convert_v1');
  for (final sourceFormat in _formats) {
    for (final destinationFormat in _destinations) {
      final name = '${_names[sourceFormat]}->${_names[destinationFormat]}';
      test('yuv_convert_v1 $name', () {
        final fixture = _Fixture(sourceFormat, destinationFormat);
        addTearDown(fixture.dispose);
        for (var i = 0; i < _warmup; i++) {
          expect(
            convert(fixture.source, fixture.destination, fixture.options),
            0,
          );
        }
        final stopwatch = Stopwatch();
        stopwatch.start();
        for (var i = 0; i < _runs; i++) {
          final status = convert(
            fixture.source,
            fixture.destination,
            fixture.options,
          );
          if (status != 0) fail('$name run $i returned $status');
        }
        stopwatch.stop();
        final expected = _oracle(fixture);
        final actualHash = _checkEverySample(fixture, expected);
        final expectedHash = _checksum(expected);
        expect(actualHash, expectedHash);
        final micros =
            stopwatch.elapsedTicks * 1000000 / stopwatch.frequency / _runs;
        print(
          'CVT $name ${_width}x$_height: ${micros.toStringAsFixed(2)} us/call '
          'checksum=0x${_hex64(actualHash)}',
        );
      });
    }
  }
}

List<int> _sizes(int format) {
  final cw = (_width + 1) ~/ 2;
  final ch = (_height + 1) ~/ 2;
  return switch (format) {
    1 => [_width * _height, cw * ch, cw * ch],
    2 => [_width * _height, cw * ch * 2],
    _ => [_width * _height * 4],
  };
}

final class _Fixture {
  _Fixture(this.sourceFormat, this.destinationFormat) {
    source = calloc<_Frame>();
    destination = calloc<_Frame>();
    options = calloc<_Options>();
    sourceBytes = [
      for (final size in _sizes(sourceFormat)) calloc<Uint8>(size),
    ];
    destinationBytes = [
      for (final size in _sizes(destinationFormat)) calloc<Uint8>(size),
    ];
    for (var p = 0; p < sourceBytes.length; p++) {
      final bytes = sourceBytes[p];
      for (var i = 0; i < _sizes(sourceFormat)[p]; i++) {
        bytes[i] =
            (i * 37 + (i ~/ 251) * 23 + p * 67 + sourceFormat * 19) & 255;
      }
    }
    _initialize(source, sourceFormat, sourceBytes);
    _initialize(destination, destinationFormat, destinationBytes);
    options.ref
      ..structSize = sizeOf<_Options>()
      ..abiVersion = 1;
  }

  final int sourceFormat;
  final int destinationFormat;
  late final Pointer<_Frame> source;
  late final Pointer<_Frame> destination;
  late final Pointer<_Options> options;
  late final List<Pointer<Uint8>> sourceBytes;
  late final List<Pointer<Uint8>> destinationBytes;

  void _initialize(
    Pointer<_Frame> frame,
    int format,
    List<Pointer<Uint8>> bytes,
  ) {
    final cw = (_width + 1) ~/ 2;
    frame.ref
      ..structSize = sizeOf<_Frame>()
      ..abiVersion = 1
      ..format = format
      ..planeCount = bytes.length
      ..width = _width
      ..height = _height
      ..colorMatrix = format <= 2 ? 1 : 0
      ..colorRange = format <= 2 ? 1 : 0;
    for (var p = 0; p < bytes.length; p++) {
      final stride = format >= 3 ? 4 : (format == 2 && p == 1 ? 2 : 1);
      final planeWidth = p == 0 ? _width : cw;
      frame.ref.planes[p]
        ..length = _sizes(format)[p]
        ..rowStride = planeWidth * stride
        ..pixelStride = stride
        ..sampleBytes = stride
        ..data = bytes[p];
    }
  }

  void dispose() {
    calloc.free(source);
    calloc.free(destination);
    calloc.free(options);
    for (final p in sourceBytes) {
      calloc.free(p);
    }
    for (final p in destinationBytes) {
      calloc.free(p);
    }
  }
}

int _clip(int v) => v < 0 ? 0 : (v > 255 ? 255 : v);
int _y(int r, int g, int b) =>
    _clip(((66 * r + 129 * g + 25 * b + 128) >> 8) + 16);
int _u(int r, int g, int b) =>
    _clip(((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128);
int _v(int r, int g, int b) =>
    _clip(((112 * r - 94 * g - 18 * b + 128) >> 8) + 128);

List<int> _pixel(_Fixture f, int x, int y) {
  final src = f.sourceBytes;
  if (f.sourceFormat >= 3) {
    final offset = (y * _width + x) * 4;
    final p = src[0];
    return f.sourceFormat == 3
        ? [p[offset + 2], p[offset + 1], p[offset], p[offset + 3]]
        : [p[offset], p[offset + 1], p[offset + 2], p[offset + 3]];
  }
  final yy = src[0][y * _width + x];
  final cw = (_width + 1) ~/ 2;
  final co = (y ~/ 2) * cw + x ~/ 2;
  final uu = f.sourceFormat == 1 ? src[1][co] : src[1][co * 2];
  final vv = f.sourceFormat == 1 ? src[2][co] : src[1][co * 2 + 1];
  final c = yy - 16, d = uu - 128, e = vv - 128;
  return [
    _clip((298 * c + 409 * e + 128) >> 8),
    _clip((298 * c - 100 * d - 208 * e + 128) >> 8),
    _clip((298 * c + 516 * d + 128) >> 8),
    255,
  ];
}

List<List<int>> _oracle(_Fixture f) {
  final src = f.sourceBytes;
  final dst = [
    for (final size in _sizes(f.destinationFormat)) List<int>.filled(size, 0),
  ];
  if (f.sourceFormat == f.destinationFormat) {
    for (var p = 0; p < dst.length; p++) {
      for (var i = 0; i < dst[p].length; i++) {
        dst[p][i] = src[p][i];
      }
    }
    return dst;
  }
  if (f.sourceFormat <= 2 && f.destinationFormat <= 2) {
    for (var i = 0; i < dst[0].length; i++) {
      dst[0][i] = src[0][i];
    }
    final count = ((_width + 1) ~/ 2) * ((_height + 1) ~/ 2);
    for (var i = 0; i < count; i++) {
      if (f.sourceFormat == 1) {
        dst[1][i * 2] = src[1][i];
        dst[1][i * 2 + 1] = src[2][i];
      } else {
        dst[1][i] = src[1][i * 2];
        dst[2][i] = src[1][i * 2 + 1];
      }
    }
    return dst;
  }
  for (var y = 0; y < _height; y++) {
    for (var x = 0; x < _width; x++) {
      final pixel = _pixel(f, x, y);
      if (f.destinationFormat == 3) {
        final offset = (y * _width + x) * 4;
        dst[0][offset] = pixel[2];
        dst[0][offset + 1] = pixel[1];
        dst[0][offset + 2] = pixel[0];
        dst[0][offset + 3] = pixel[3];
      } else {
        dst[0][y * _width + x] = _y(pixel[0], pixel[1], pixel[2]);
      }
    }
  }
  if (f.destinationFormat == 3) return dst;
  final cw = (_width + 1) ~/ 2;
  for (var by = 0; by < (_height + 1) ~/ 2; by++) {
    for (var bx = 0; bx < cw; bx++) {
      var r = 0, g = 0, b = 0, count = 0;
      for (var dy = 0; dy < 2; dy++) {
        for (var dx = 0; dx < 2; dx++) {
          final x = bx * 2 + dx, y = by * 2 + dy;
          if (x >= _width || y >= _height) continue;
          final p = _pixel(f, x, y);
          r += p[0];
          g += p[1];
          b += p[2];
          count++;
        }
      }
      final u = _u(r ~/ count, g ~/ count, b ~/ count);
      final v = _v(r ~/ count, g ~/ count, b ~/ count);
      final offset = by * cw + bx;
      if (f.destinationFormat == 1) {
        dst[1][offset] = u;
        dst[2][offset] = v;
      } else {
        dst[1][offset * 2] = u;
        dst[1][offset * 2 + 1] = v;
      }
    }
  }
  return dst;
}

int _checksum(List<List<int>> planes) {
  var hash = _fnvBasis;
  for (final plane in planes) {
    for (final value in plane) {
      hash = ((hash ^ value) * _fnvPrime) & _mask64;
    }
  }
  return hash;
}

String _hex64(int value) {
  final high = (value >> 32) & 0xffffffff;
  final low = value & 0xffffffff;
  return '${high.toRadixString(16).padLeft(8, '0')}'
      '${low.toRadixString(16).padLeft(8, '0')}';
}

int _checkEverySample(_Fixture fixture, List<List<int>> expected) {
  var hash = _fnvBasis;
  for (var p = 0; p < expected.length; p++) {
    for (var i = 0; i < expected[p].length; i++) {
      final actual = fixture.destinationBytes[p][i];
      if (actual != expected[p][i]) {
        fail(
          '${_names[fixture.sourceFormat]}->${_names[fixture.destinationFormat]} '
          'plane $p byte $i: expected ${expected[p][i]}, got $actual',
        );
      }
      hash = ((hash ^ actual) * _fnvPrime) & _mask64;
    }
  }
  return hash;
}
