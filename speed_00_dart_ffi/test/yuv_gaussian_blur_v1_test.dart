import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

const _width = 321;
const _height = 241;
const _warmup = 3;
const _runs = 8;
const _i420 = 1;
const _nv12 = 2;
const _bgra = 3;
const _offset = 0xcbf29ce484222325;
const _prime = 0x100000001b3;
const _mask = 0xffffffffffffffff;

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

final class _ConstFrame extends Struct {
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

final class _MutableFrame extends Struct {
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

final class _Region extends Struct {
  @Uint32()
  external int structSize;
  @Uint32()
  external int abiVersion;
  @Int32()
  external int left;
  @Int32()
  external int top;
  @Int32()
  external int right;
  @Int32()
  external int bottom;
  @Uint32()
  external int enabled;
  @Uint32()
  external int reserved0;
}

final class _Options extends Struct {
  @Uint32()
  external int structSize;
  @Uint32()
  external int abiVersion;
  @Uint32()
  external int radius;
  @Uint32()
  external int borderMode;
  @Double()
  external double sigma;
  external _Region region;
  @Array.multi([2])
  external Array<Uint64> reserved;
}

typedef _Native =
    Int32 Function(
      Pointer<_ConstFrame>,
      Pointer<_MutableFrame>,
      Pointer<_Options>,
    );
typedef _Dart =
    int Function(
      Pointer<_ConstFrame>,
      Pointer<_MutableFrame>,
      Pointer<_Options>,
    );

void main() {
  final path = Platform.environment['YUV_FFI_DLL'];
  if (path == null || !File(path).existsSync()) {
    throw StateError('Set YUV_FFI_DLL to the Release yuv_ffi.dll.');
  }
  final blur = DynamicLibrary.open(
    path,
  ).lookupFunction<_Native, _Dart>('yuv_gaussian_blur_v1');
  for (final format in [_i420, _nv12, _bgra]) {
    for (final radius in [1, 3]) {
      for (final roi in [false, true]) {
        final name =
            '${_formatName(format)} radius=$radius sigma=${radius == 1 ? 1.0 : 1.5} ${roi ? 'ROI' : 'full'}';
        test(name, () {
          final f = _Fixture(format, radius, roi);
          addTearDown(f.dispose);
          final expected = _oracle(f);
          for (var i = 0; i < _warmup; i++) {
            expect(blur(f.source, f.destination, f.options), 0);
          }
          final timer = Stopwatch()..start();
          var failedStatus = 0;
          for (var i = 0; i < _runs; i++) {
            final status = blur(f.source, f.destination, f.options);
            if (status != 0) failedStatus = status;
          }
          timer.stop();
          expect(failedStatus, 0);
          final actualHash = _checkBytes(f, expected);
          final expectedHash = _hash(expected.expand((p) => p));
          expect(actualHash, expectedHash);
          print(
            '$name: ${timer.elapsedMicroseconds} us / $_runs calls '
            '(${(timer.elapsedMicroseconds / _runs).toStringAsFixed(2)} us/call), '
            'checksum=0x${BigInt.from(actualHash).toUnsigned(64).toRadixString(16).padLeft(16, '0')}',
          );
        });
      }
    }
  }
  test('radius zero preserves visible pixels with ROI encoding', () {
    for (final format in [_i420, _nv12, _bgra]) {
      final f = _Fixture(format, 0, true);
      try {
        expect(blur(f.source, f.destination, f.options), 0);
        _checkBytes(f, _oracle(f));
      } finally {
        f.dispose();
      }
    }
  });
  test('padded row and pixel strides preserve samples and padding', () {
    for (final size in [(w: _width, h: _height, r: 3), (w: 7, h: 5, r: 7)]) {
      for (final format in [_i420, _nv12, _bgra]) {
        final reference = _Fixture(
          format,
          size.r,
          true,
          width: size.w,
          height: size.h,
        );
        final padded = _Fixture(
          format,
          size.r,
          true,
          width: size.w,
          height: size.h,
        );
        try {
          final expected = _oracle(reference);
          padded.padPlanes();
          expect(blur(padded.source, padded.destination, padded.options), 0);
          final specs = _specs(format, size.w, size.h);
          for (var p = 0; p < specs.length; p++) {
            final s = specs[p];
            final plane = padded.destination.ref.planes[p];
            final bytes = plane.data.asTypedList(plane.length);
            final active = List<bool>.filled(bytes.length, false);
            for (var y = 0; y < s.h; y++) {
              for (var x = 0; x < s.w; x++) {
                for (var b = 0; b < s.b; b++) {
                  final offset =
                      y * plane.rowStride + x * plane.pixelStride + b;
                  expect(bytes[offset], expected[p][(y * s.w + x) * s.b + b]);
                  active[offset] = true;
                }
              }
            }
            for (var i = 0; i < bytes.length; i++) {
              if (!active[i]) expect(bytes[i], 0xa5);
            }
          }
        } finally {
          reference.dispose();
          padded.dispose();
        }
      }
    }
  });
  test('edge replication on short and odd frames', () {
    for (final dimensions in [
      (w: 7, h: 5, r: 3, roi: false),
      (w: 7, h: 5, r: 7, roi: true),
      (w: 3, h: 1, r: 3, roi: false),
      (w: 1, h: 1, r: 256, roi: false),
    ]) {
      for (final format in [_i420, _nv12, _bgra]) {
        final f = _Fixture(
          format,
          dimensions.r,
          dimensions.roi,
          width: dimensions.w,
          height: dimensions.h,
        );
        try {
          final expected = _oracle(f);
          expect(blur(f.source, f.destination, f.options), 0);
          expect(_checkBytes(f, expected), _hash(expected.expand((p) => p)));
        } finally {
          f.dispose();
        }
      }
    }
  });
  test('invalid options and descriptors leave destination untouched', () {
    final f = _Fixture(_i420, 1, true);
    addTearDown(f.dispose);
    void rejected(int status) {
      expect(blur(f.source, f.destination, f.options), status);
      for (final plane in f.outputs) {
        for (final byte in plane) {
          expect(byte, 0xa5);
        }
      }
    }

    f.options.ref.radius = 257;
    rejected(1);
    f.options.ref.radius = 1;
    f.options.ref.borderMode = 2;
    rejected(1);
    f.options.ref.borderMode = 1;
    f.options.ref.sigma = 0;
    rejected(1);
    f.options.ref.sigma = -1;
    rejected(1);
    f.options.ref.sigma = double.nan;
    rejected(1);
    f.options.ref.sigma = double.infinity;
    rejected(1);
    f.options.ref.sigma = 1;
    f.options.ref.reserved[0] = 1;
    rejected(1);
    f.options.ref.reserved[0] = 0;
    f.options.ref.region.left = -1;
    rejected(1);
    f.options.ref.region.left = 31;
    f.source.ref.abiVersion = 2;
    rejected(1);
    f.source.ref.abiVersion = 1;
    f.destination.ref.format = _bgra;
    rejected(1);
  });
  test('unsupported format pair leaves destination untouched', () {
    final f = _Fixture(_bgra, 1, false);
    addTearDown(f.dispose);
    f.destination.ref.format =
        4; // Valid RGBA descriptor, unsupported BGRA pair.
    expect(blur(f.source, f.destination, f.options), 2);
    for (final byte in f.outputs.single) {
      expect(byte, 0xa5);
    }
  });
}

String _formatName(int format) => switch (format) {
  _i420 => 'I420',
  _nv12 => 'NV12',
  _bgra => 'BGRA',
  _ => throw ArgumentError.value(format),
};

List<({int w, int h, int b})> _specs(
  int format, [
  int width = _width,
  int height = _height,
]) {
  final cw = (width + 1) ~/ 2;
  final ch = (height + 1) ~/ 2;
  return switch (format) {
    _i420 => [
      (w: width, h: height, b: 1),
      (w: cw, h: ch, b: 1),
      (w: cw, h: ch, b: 1),
    ],
    _nv12 => [(w: width, h: height, b: 1), (w: cw, h: ch, b: 2)],
    _bgra => [(w: width, h: height, b: 4)],
    _ => throw ArgumentError.value(format),
  };
}

final class _Fixture {
  _Fixture(
    this.format,
    int radius,
    this.roi, {
    this.width = _width,
    this.height = _height,
  }) : source = calloc<_ConstFrame>(),
       destination = calloc<_MutableFrame>(),
       options = calloc<_Options>(),
       inputs = [],
       outputs = [] {
    final specs = _specs(format, width, height);
    for (var p = 0; p < specs.length; p++) {
      final s = specs[p];
      final input = calloc<Uint8>(s.w * s.h * s.b);
      final output = calloc<Uint8>(s.w * s.h * s.b);
      for (var i = 0; i < s.w * s.h * s.b; i++) {
        input[i] =
            (i * (13 + 2 * p) + (i ~/ (s.w * s.b)) * 37 + 17 * p + 51) & 255;
        output[i] = 0xa5;
      }
      inputs.add(input.asTypedList(s.w * s.h * s.b));
      outputs.add(output.asTypedList(s.w * s.h * s.b));
      source.ref.planes[p]
        ..length = s.w * s.h * s.b
        ..rowStride = s.w * s.b
        ..pixelStride = s.b
        ..sampleBytes = s.b
        ..data = input;
      destination.ref.planes[p]
        ..length = s.w * s.h * s.b
        ..rowStride = s.w * s.b
        ..pixelStride = s.b
        ..sampleBytes = s.b
        ..data = output;
    }
    final isBgra = format == _bgra;
    source.ref
      ..structSize = sizeOf<_ConstFrame>()
      ..abiVersion = 1
      ..format = format
      ..planeCount = specs.length
      ..width = width
      ..height = height
      ..colorMatrix = isBgra ? 0 : 1
      ..colorRange = isBgra ? 0 : 1;
    destination.ref
      ..structSize = sizeOf<_MutableFrame>()
      ..abiVersion = 1
      ..format = format
      ..planeCount = specs.length
      ..width = width
      ..height = height
      ..colorMatrix = isBgra ? 0 : 1
      ..colorRange = isBgra ? 0 : 1;
    options.ref
      ..structSize = sizeOf<_Options>()
      ..abiVersion = 1
      ..radius = radius
      ..borderMode = 1
      ..sigma = radius == 3 ? 1.5 : 1.0;
    options.ref.region
      ..structSize = sizeOf<_Region>()
      ..abiVersion = 1
      ..enabled = roi ? 1 : 0
      ..left = roi ? (width == _width ? 31 : 1) : 0
      ..top = roi ? (height == _height ? 19 : 1) : 0
      ..right = roi ? (width == _width ? 290 : width - 2) : 0
      ..bottom = roi ? (height == _height ? 210 : height - 2) : 0;
  }

  final int format;
  final bool roi;
  final int width;
  final int height;
  final Pointer<_ConstFrame> source;
  final Pointer<_MutableFrame> destination;
  final Pointer<_Options> options;
  final List<List<int>> inputs;
  final List<List<int>> outputs;

  bool contains(int x, int y) =>
      !roi ||
      (x >= options.ref.region.left &&
          x < options.ref.region.right &&
          y >= options.ref.region.top &&
          y < options.ref.region.bottom);

  void padPlanes() {
    final specs = _specs(format, width, height);
    for (var p = 0; p < specs.length; p++) {
      final s = specs[p];
      final pixelStride = s.b + 1;
      final rowStride = s.w * pixelStride + 7;
      final length = rowStride * s.h;
      final sourceData = calloc<Uint8>(length);
      final destinationData = calloc<Uint8>(length);
      for (var i = 0; i < length; i++) {
        sourceData[i] = 0x6d;
        destinationData[i] = 0xa5;
      }
      for (var y = 0; y < s.h; y++) {
        for (var x = 0; x < s.w; x++) {
          for (var b = 0; b < s.b; b++) {
            sourceData[y * rowStride + x * pixelStride + b] =
                inputs[p][(y * s.w + x) * s.b + b];
          }
        }
      }
      calloc.free(source.ref.planes[p].data);
      calloc.free(destination.ref.planes[p].data);
      source.ref.planes[p]
        ..length = length
        ..rowStride = rowStride
        ..pixelStride = pixelStride
        ..data = sourceData;
      destination.ref.planes[p]
        ..length = length
        ..rowStride = rowStride
        ..pixelStride = pixelStride
        ..data = destinationData;
    }
  }

  void dispose() {
    for (var p = 0; p < inputs.length; p++) {
      calloc.free(source.ref.planes[p].data);
      calloc.free(destination.ref.planes[p].data);
    }
    calloc.free(source);
    calloc.free(destination);
    calloc.free(options);
  }
}

int _clip(int v) => v < 0 ? 0 : (v > 255 ? 255 : v);
int _clamp(int x, int size) => x < 0 ? 0 : (x >= size ? size - 1 : x);
int _y(int r, int g, int b) =>
    _clip(((66 * r + 129 * g + 25 * b + 128) >> 8) + 16);
int _u(int r, int g, int b) =>
    _clip(((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128);
int _v(int r, int g, int b) =>
    _clip(((112 * r - 94 * g - 18 * b + 128) >> 8) + 128);

List<int> _sourceRgb(_Fixture f, int x, int y) {
  if (f.format == _bgra) {
    final i = (y * f.width + x) * 4;
    return [f.inputs[0][i + 2], f.inputs[0][i + 1], f.inputs[0][i]];
  }
  final yv = f.inputs[0][y * f.width + x];
  final ci = (y ~/ 2) * ((f.width + 1) ~/ 2) + x ~/ 2;
  final u = f.format == _i420 ? f.inputs[1][ci] : f.inputs[1][ci * 2];
  final v = f.format == _i420 ? f.inputs[2][ci] : f.inputs[1][ci * 2 + 1];
  final c = yv - 16;
  final d = u - 128;
  final e = v - 128;
  return [
    _clip((298 * c + 409 * e + 128) >> 8),
    _clip((298 * c - 100 * d - 208 * e + 128) >> 8),
    _clip((298 * c + 516 * d + 128) >> 8),
  ];
}

List<List<int>> _oracle(_Fixture f) {
  final source = List.generate(
    f.width * f.height,
    (i) => _sourceRgb(f, i % f.width, i ~/ f.width),
  );
  final visible = List<List<int>>.of(source);
  final radius = f.options.ref.radius;
  final side = radius * 2 + 1;
  final sigma = f.options.ref.sigma;
  final denominator = 2.0 * sigma * sigma;
  final weights = [
    for (var dy = -radius; dy <= radius; dy++)
      for (var dx = -radius; dx <= radius; dx++)
        math.exp(-(dx * dx + dy * dy) / denominator),
  ];
  for (var y = 0; y < f.height; y++) {
    for (var x = 0; x < f.width; x++) {
      if (!f.contains(x, y)) continue;
      var red = 0.0;
      var green = 0.0;
      var blue = 0.0;
      var total = 0.0;
      for (var dy = -radius; dy <= radius; dy++) {
        for (var dx = -radius; dx <= radius; dx++) {
          final pixel =
              source[_clamp(y + dy, f.height) * f.width +
                  _clamp(x + dx, f.width)];
          final weight = weights[(dy + radius) * side + dx + radius];
          red += weight * pixel[0];
          green += weight * pixel[1];
          blue += weight * pixel[2];
          total += weight;
        }
      }
      visible[y * f.width + x] = [
        _clip((red / total + 0.5).toInt()),
        _clip((green / total + 0.5).toInt()),
        _clip((blue / total + 0.5).toInt()),
      ];
    }
  }
  final expected = [for (final plane in f.inputs) List<int>.of(plane)];
  if (f.format == _bgra) {
    for (var y = 0; y < f.height; y++) {
      for (var x = 0; x < f.width; x++) {
        if (!f.contains(x, y)) continue;
        final i = (y * f.width + x) * 4;
        final rgb = visible[y * f.width + x];
        expected[0][i] = rgb[2];
        expected[0][i + 1] = rgb[1];
        expected[0][i + 2] = rgb[0];
      }
    }
    return expected;
  }
  for (var y = 0; y < f.height; y++) {
    for (var x = 0; x < f.width; x++) {
      if (!f.contains(x, y)) continue;
      final rgb = visible[y * f.width + x];
      expected[0][y * f.width + x] = _y(rgb[0], rgb[1], rgb[2]);
    }
  }
  final cw = (f.width + 1) ~/ 2;
  final ch = (f.height + 1) ~/ 2;
  for (var by = 0; by < ch; by++) {
    for (var bx = 0; bx < cw; bx++) {
      final sums = [0, 0, 0];
      var count = 0;
      var intersects = false;
      for (var dy = 0; dy < 2; dy++) {
        for (var dx = 0; dx < 2; dx++) {
          final x = bx * 2 + dx;
          final y = by * 2 + dy;
          if (x >= f.width || y >= f.height) continue;
          intersects |= f.contains(x, y);
          final rgb = visible[y * f.width + x];
          for (var c = 0; c < 3; c++) {
            sums[c] += rgb[c];
          }
          count++;
        }
      }
      if (!intersects) continue;
      final r = sums[0] ~/ count;
      final g = sums[1] ~/ count;
      final b = sums[2] ~/ count;
      final i = by * cw + bx;
      if (f.format == _i420) {
        expected[1][i] = _u(r, g, b);
        expected[2][i] = _v(r, g, b);
      } else {
        expected[1][i * 2] = _u(r, g, b);
        expected[1][i * 2 + 1] = _v(r, g, b);
      }
    }
  }
  return expected;
}

int _hash(Iterable<int> bytes) {
  var hash = _offset;
  for (final byte in bytes) {
    hash = ((hash ^ byte) * _prime) & _mask;
  }
  return hash;
}

int _checkBytes(_Fixture f, List<List<int>> expected) {
  var hash = _offset;
  for (var p = 0; p < expected.length; p++) {
    final actual = f.outputs[p];
    for (var i = 0; i < expected[p].length; i++) {
      if (actual[i] != expected[p][i]) {
        fail('plane $p byte $i: expected ${expected[p][i]}, got ${actual[i]}');
      }
      hash = ((hash ^ actual[i]) * _prime) & _mask;
    }
  }
  return hash;
}
