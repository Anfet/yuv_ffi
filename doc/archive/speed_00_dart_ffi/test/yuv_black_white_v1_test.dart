import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

const _abi = 1;
const _i420 = 1;
const _nv12 = 2;
const _bgra = 3;
const _width = 1280;
const _height = 720;
const _warmup = 10;
const _runs = 20;
const _offset = 0xcbf29ce484222325;
const _prime = 0x100000001b3;
const _mask = 0xffffffffffffffff;

final class _ConstPlane extends Struct {
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

final class _MutablePlane extends Struct {
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
  external Array<_ConstPlane> planes;
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
  external Array<_MutablePlane> planes;
  @Array.multi([4])
  external Array<Uint64> reserved;
}

final class _RegionOptions extends Struct {
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

final class _EffectOptions extends Struct {
  @Uint32()
  external int structSize;
  @Uint32()
  external int abiVersion;
  external _RegionOptions region;
  @Array.multi([2])
  external Array<Uint64> reserved;
}

typedef _NativeBlackWhite =
    Int32 Function(
      Pointer<_ConstFrame>,
      Pointer<_MutableFrame>,
      Pointer<_EffectOptions>,
    );
typedef _DartBlackWhite =
    int Function(
      Pointer<_ConstFrame>,
      Pointer<_MutableFrame>,
      Pointer<_EffectOptions>,
    );

const _scenarios = <_Scenario>[
  _Scenario('I420 full-frame', _i420),
  _Scenario('I420 ROI', _i420, true),
  _Scenario('NV12 full-frame', _nv12),
  _Scenario('NV12 ROI', _nv12, true),
  _Scenario('BGRA full-frame', _bgra),
  _Scenario('BGRA ROI', _bgra, true),
];

void main() {
  final path = Platform.environment['YUV_FFI_DLL'];
  if (path == null || !File(path).existsSync()) {
    throw StateError('Set YUV_FFI_DLL to the Release yuv_ffi.dll under test.');
  }
  final blackWhite = DynamicLibrary.open(
    path,
  ).lookupFunction<_NativeBlackWhite, _DartBlackWhite>('yuv_black_white_v1');
  for (final scenario in _scenarios) {
    test('yuv_black_white_v1 ${scenario.name}', () {
      final fixture = _Fixture.create(scenario);
      addTearDown(fixture.dispose);
      for (var run = 0; run < _warmup; run++) {
        expect(
          blackWhite(fixture.source, fixture.destination, fixture.options),
          0,
        );
      }
      final timer = Stopwatch()..start();
      var failedRun = -1;
      var failedStatus = 0;
      for (var run = 0; run < _runs; run++) {
        final status = blackWhite(
          fixture.source,
          fixture.destination,
          fixture.options,
        );
        if (status != 0 && failedRun == -1) {
          failedRun = run;
          failedStatus = status;
        }
      }
      timer.stop();
      if (failedRun != -1) {
        fail('measured run $failedRun returned ABI status $failedStatus');
      }
      _expectOutput(fixture);
      final checksum = _checksumActual(fixture);
      expect(checksum, _checksumOracle(fixture));
      print(
        'yuv_black_white_v1 ${scenario.name}: ${timer.elapsedMicroseconds} us / $_runs calls '
        '(${(timer.elapsedMicroseconds / _runs).toStringAsFixed(2)} us/call), '
        'checksum=0x${_hex64(checksum)}',
      );
    });
  }
  test('yuv_black_white_v1 I420 ROI with padded source rows', () {
    final fixture = _Fixture.create(_scenarios[1])..padSourceRows();
    addTearDown(fixture.dispose);
    expect(blackWhite(fixture.source, fixture.destination, fixture.options), 0);
    _expectOutput(fixture);
    expect(_checksumActual(fixture), _checksumOracle(fixture));
  });
}

final class _Scenario {
  const _Scenario(this.name, this.format, [this.regionEnabled = false]);
  final String name;
  final int format;
  final bool regionEnabled;
}

final class _Plane {
  const _Plane(this.width, this.height, this.bytes);
  final int width;
  final int height;
  final int bytes;
  int get length => width * height * bytes;
}

final class _Fixture {
  _Fixture._(
    this.scenario,
    this.source,
    this.destination,
    this.options,
    this.planes,
    this.sourceBytes,
    this.sourceRowStrides,
    this.destinationBytes,
  );
  final _Scenario scenario;
  final Pointer<_ConstFrame> source;
  final Pointer<_MutableFrame> destination;
  final Pointer<_EffectOptions> options;
  final List<_Plane> planes;
  final List<Pointer<Uint8>> sourceBytes;
  final List<int> sourceRowStrides;
  final List<Pointer<Uint8>> destinationBytes;

  static _Fixture create(_Scenario scenario) {
    final planes = switch (scenario.format) {
      _i420 => const [
        _Plane(_width, _height, 1),
        _Plane(_width ~/ 2, _height ~/ 2, 1),
        _Plane(_width ~/ 2, _height ~/ 2, 1),
      ],
      _nv12 => const [
        _Plane(_width, _height, 1),
        _Plane(_width ~/ 2, _height ~/ 2, 2),
      ],
      _bgra => const [_Plane(_width, _height, 4)],
      _ => throw ArgumentError.value(scenario.format),
    };
    final sourceBytes = [
      for (final plane in planes) calloc<Uint8>(plane.length),
    ];
    final destinationBytes = [
      for (final plane in planes) calloc<Uint8>(plane.length),
    ];
    _fillSource(scenario, planes, sourceBytes);
    final source = calloc<_ConstFrame>();
    final destination = calloc<_MutableFrame>();
    _setConstPlanes(source.ref.planes, planes, sourceBytes);
    _setMutablePlanes(destination.ref.planes, planes, destinationBytes);
    final isBgra = scenario.format == _bgra;
    source.ref
      ..structSize = sizeOf<_ConstFrame>()
      ..abiVersion = _abi
      ..format = scenario.format
      ..planeCount = planes.length
      ..width = _width
      ..height = _height
      ..colorMatrix = isBgra ? 0 : 1
      ..colorRange = isBgra ? 0 : 1;
    destination.ref
      ..structSize = sizeOf<_MutableFrame>()
      ..abiVersion = _abi
      ..format = scenario.format
      ..planeCount = planes.length
      ..width = _width
      ..height = _height
      ..colorMatrix = isBgra ? 0 : 1
      ..colorRange = isBgra ? 0 : 1;
    final options = calloc<_EffectOptions>()
      ..ref.structSize = sizeOf<_EffectOptions>()
      ..ref.abiVersion = _abi
      ..ref.region.structSize = sizeOf<_RegionOptions>()
      ..ref.region.abiVersion = _abi
      ..ref.region.enabled = scenario.regionEnabled ? 1 : 0;
    if (scenario.regionEnabled) {
      options.ref.region
        ..left = 127
        ..top = 89
        ..right = 1087
        ..bottom = 631;
    }
    return _Fixture._(
      scenario,
      source,
      destination,
      options,
      planes,
      sourceBytes,
      [for (final plane in planes) plane.width * plane.bytes],
      destinationBytes,
    );
  }

  bool contains(int x, int y) =>
      !scenario.regionEnabled || (x >= 127 && x < 1087 && y >= 89 && y < 631);

  void padSourceRows() {
    for (var planeIndex = 0; planeIndex < planes.length; planeIndex++) {
      final plane = planes[planeIndex];
      final rowStride = plane.width * plane.bytes + 7 + planeIndex;
      final padded = calloc<Uint8>(rowStride * plane.height);
      for (var y = 0; y < plane.height; y++) {
        for (var byte = 0; byte < plane.width * plane.bytes; byte++) {
          padded[y * rowStride + byte] =
              sourceBytes[planeIndex][y * plane.width * plane.bytes + byte];
        }
      }
      calloc.free(sourceBytes[planeIndex]);
      sourceBytes[planeIndex] = padded;
      sourceRowStrides[planeIndex] = rowStride;
      source.ref.planes[planeIndex]
        ..length = rowStride * plane.height
        ..rowStride = rowStride
        ..data = padded;
    }
  }

  void dispose() {
    calloc.free(source);
    calloc.free(destination);
    calloc.free(options);
    for (final bytes in sourceBytes) {
      calloc.free(bytes);
    }
    for (final bytes in destinationBytes) {
      calloc.free(bytes);
    }
  }
}

void _setConstPlanes(
  Array<_ConstPlane> target,
  List<_Plane> planes,
  List<Pointer<Uint8>> bytes,
) {
  for (var i = 0; i < planes.length; i++) {
    final p = planes[i];
    target[i]
      ..length = p.length
      ..rowStride = p.width * p.bytes
      ..pixelStride = p.bytes
      ..sampleBytes = p.bytes
      ..data = bytes[i];
  }
}

void _setMutablePlanes(
  Array<_MutablePlane> target,
  List<_Plane> planes,
  List<Pointer<Uint8>> bytes,
) {
  for (var i = 0; i < planes.length; i++) {
    final p = planes[i];
    target[i]
      ..length = p.length
      ..rowStride = p.width * p.bytes
      ..pixelStride = p.bytes
      ..sampleBytes = p.bytes
      ..data = bytes[i];
  }
}

void _fillSource(
  _Scenario scenario,
  List<_Plane> planes,
  List<Pointer<Uint8>> bytes,
) {
  if (scenario.format == _bgra) {
    final data = bytes.single;
    for (var y = 0; y < _height; y++) {
      for (var x = 0; x < _width; x++) {
        final i = (y * _width + x) * 4;
        data[i] = (x * 17 + y * 29 + 3) & 0xff;
        data[i + 1] = (x * 31 + y * 11 + 71) & 0xff;
        data[i + 2] = (x * 7 + y * 23 + 149) & 0xff;
        data[i + 3] = (x * 13 + y * 19 + 211) & 0xff;
      }
    }
    for (final (pixel, value) in [(0, 127), (1, 128), (2, 129)]) {
      final i = pixel * 4;
      data[i] = value;
      data[i + 1] = value;
      data[i + 2] = value;
    }
    return;
  }
  final luma = bytes[0];
  for (var y = 0; y < _height; y++) {
    for (var x = 0; x < _width; x++) {
      luma[y * _width + x] = 16 + ((x * 17 + y * 29 + 3) % 220);
    }
  }
  final chroma = bytes[1];
  for (var y = 0; y < _height ~/ 2; y++) {
    for (var x = 0; x < _width ~/ 2; x++) {
      final u = 16 + ((x * 11 + y * 37 + 5) % 225);
      final v = 16 + ((x * 43 + y * 13 + 97) % 225);
      if (scenario.format == _i420) {
        chroma[y * (_width ~/ 2) + x] = u;
        bytes[2][y * (_width ~/ 2) + x] = v;
      } else {
        final i = (y * (_width ~/ 2) + x) * 2;
        chroma[i] = u;
        chroma[i + 1] = v;
      }
    }
  }
  luma[0] = 125;
  luma[1] = 126;
  luma[2] = 127;
  if (scenario.format == _i420) {
    bytes[1][0] = 128;
    bytes[2][0] = 128;
  } else {
    bytes[1][0] = 128;
    bytes[1][1] = 128;
  }
}

({int r, int g, int b}) _sourceRgb(_Fixture f, int x, int y) {
  if (f.scenario.format == _bgra) {
    final i = y * f.sourceRowStrides[0] + x * 4;
    return (
      r: f.sourceBytes[0][i + 2],
      g: f.sourceBytes[0][i + 1],
      b: f.sourceBytes[0][i],
    );
  }
  final yValue = f.sourceBytes[0][y * f.sourceRowStrides[0] + x];
  final block = (y ~/ 2) * f.sourceRowStrides[1] + (x ~/ 2) * f.planes[1].bytes;
  final u = f.scenario.format == _i420
      ? f.sourceBytes[1][block]
      : f.sourceBytes[1][block];
  final v = f.scenario.format == _i420
      ? f.sourceBytes[2][(y ~/ 2) * f.sourceRowStrides[2] + x ~/ 2]
      : f.sourceBytes[1][block + 1];
  final c = yValue - 16;
  final d = u - 128;
  final e = v - 128;
  return (
    r: _clip((298 * c + 409 * e + 128) >> 8),
    g: _clip((298 * c - 100 * d - 208 * e + 128) >> 8),
    b: _clip((298 * c + 516 * d + 128) >> 8),
  );
}

int _gray(({int r, int g, int b}) rgb) =>
    _clip((299 * rgb.r + 587 * rgb.g + 114 * rgb.b + 500) ~/ 1000);

int _blackWhite(({int r, int g, int b}) rgb) => _gray(rgb) >= 128 ? 255 : 0;

int _rgbToY(int r, int g, int b) =>
    _clip(((66 * r + 129 * g + 25 * b + 128) >> 8) + 16);

int _rgbToU(int r, int g, int b) =>
    _clip(((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128);

int _rgbToV(int r, int g, int b) =>
    _clip(((112 * r - 94 * g - 18 * b + 128) >> 8) + 128);

int _clip(int value) => value < 0 ? 0 : (value > 255 ? 255 : value);

int _oracleByte(_Fixture f, int plane, int index) {
  if (f.scenario.format == _bgra) {
    final pixel = index ~/ 4;
    final byte = index % 4;
    final x = pixel % _width;
    final y = pixel ~/ _width;
    if (!f.contains(x, y) || byte == 3) return _sourceByte(f, 0, index);
    return _blackWhite(_sourceRgb(f, x, y));
  }
  if (plane == 0) {
    final x = index % _width;
    final y = index ~/ _width;
    if (!f.contains(x, y)) return _sourceByte(f, 0, index);
    final value = _blackWhite(_sourceRgb(f, x, y));
    return _rgbToY(value, value, value);
  }
  final sample = index ~/ f.planes[plane].bytes;
  final byte = index % f.planes[plane].bytes;
  final blockX = sample % (_width ~/ 2);
  final blockY = sample ~/ (_width ~/ 2);
  var red = 0;
  var green = 0;
  var blue = 0;
  var intersects = false;
  for (var dy = 0; dy < 2; dy++) {
    for (var dx = 0; dx < 2; dx++) {
      final x = blockX * 2 + dx;
      final y = blockY * 2 + dy;
      final rgb = _sourceRgb(f, x, y);
      if (f.contains(x, y)) {
        final value = _blackWhite(rgb);
        red += value;
        green += value;
        blue += value;
        intersects = true;
      } else {
        red += rgb.r;
        green += rgb.g;
        blue += rgb.b;
      }
    }
  }
  if (!intersects) return _sourceByte(f, plane, index);
  final r = red ~/ 4;
  final g = green ~/ 4;
  final b = blue ~/ 4;
  return switch ((f.scenario.format, plane, byte)) {
    (_i420, 1, _) => _rgbToU(r, g, b),
    (_i420, 2, _) => _rgbToV(r, g, b),
    (_nv12, 1, 0) => _rgbToU(r, g, b),
    (_nv12, 1, 1) => _rgbToV(r, g, b),
    _ => throw StateError('Unexpected plane $plane byte $byte'),
  };
}

int _sourceByte(_Fixture f, int plane, int index) {
  final sample = index ~/ f.planes[plane].bytes;
  final byte = index % f.planes[plane].bytes;
  final x = sample % f.planes[plane].width;
  final y = sample ~/ f.planes[plane].width;
  return f.sourceBytes[plane][y * f.sourceRowStrides[plane] +
      x * f.planes[plane].bytes +
      byte];
}

void _expectOutput(_Fixture f) {
  for (var p = 0; p < f.planes.length; p++) {
    for (var i = 0; i < f.planes[p].length; i++) {
      if (f.destinationBytes[p][i] != _oracleByte(f, p, i)) {
        fail('${f.scenario.name} plane $p byte $i differs');
      }
    }
  }
}

int _checksumActual(_Fixture f) {
  var h = _offset;
  for (var p = 0; p < f.planes.length; p++) {
    for (var i = 0; i < f.planes[p].length; i++) {
      h = ((h ^ f.destinationBytes[p][i]) * _prime) & _mask;
    }
  }
  return h.toUnsigned(64);
}

int _checksumOracle(_Fixture f) {
  var h = _offset;
  for (var p = 0; p < f.planes.length; p++) {
    for (var i = 0; i < f.planes[p].length; i++) {
      h = ((h ^ _oracleByte(f, p, i)) * _prime) & _mask;
    }
  }
  return h.toUnsigned(64);
}

String _hex64(int value) {
  final high = (value >> 32) & 0xffffffff;
  final low = value & 0xffffffff;
  return '${high.toRadixString(16).padLeft(8, '0')}${low.toRadixString(16).padLeft(8, '0')}';
}
