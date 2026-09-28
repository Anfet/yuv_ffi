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
const _runs = 100;
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

final class _RotateOptions extends Struct {
  @Uint32()
  external int structSize;
  @Uint32()
  external int abiVersion;
  @Uint32()
  external int rotationDegrees;
  @Uint32()
  external int reserved0;
  @Array.multi([2])
  external Array<Uint64> reserved;
}

typedef _NativeRotate =
    Int32 Function(
      Pointer<_ConstFrame>,
      Pointer<_MutableFrame>,
      Pointer<_RotateOptions>,
    );
typedef _DartRotate =
    int Function(
      Pointer<_ConstFrame>,
      Pointer<_MutableFrame>,
      Pointer<_RotateOptions>,
    );

const _scenarios = <_Scenario>[
  _Scenario('I420 90', _i420, 90),
  _Scenario('I420 180', _i420, 180),
  _Scenario('I420 270', _i420, 270),
  _Scenario('NV12 90', _nv12, 90),
  _Scenario('NV12 180', _nv12, 180),
  _Scenario('NV12 270', _nv12, 270),
  _Scenario('BGRA 90', _bgra, 90),
  _Scenario('BGRA 180', _bgra, 180),
  _Scenario('BGRA 270', _bgra, 270),
];

void main() {
  final path = Platform.environment['YUV_FFI_DLL'];
  if (path == null || !File(path).existsSync())
    throw StateError('Set YUV_FFI_DLL to the Release yuv_ffi.dll under test.');
  final rotate = DynamicLibrary.open(
    path,
  ).lookupFunction<_NativeRotate, _DartRotate>('yuv_rotate_v1');
  for (final scenario in _scenarios) {
    test('yuv_rotate_v1 ${scenario.name}', () {
      final fixture = _Fixture.create(scenario);
      addTearDown(fixture.dispose);
      for (var run = 0; run < _warmup; run++)
        expect(rotate(fixture.source, fixture.destination, fixture.options), 0);
      final timer = Stopwatch()..start();
      var failedRun = -1;
      var failedStatus = 0;
      for (var run = 0; run < _runs; run++) {
        final status = rotate(
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
      if (failedRun != -1)
        fail('measured run $failedRun returned ABI status $failedStatus');
      _expectOutput(fixture);
      final checksum = _checksumActual(fixture);
      expect(checksum, _checksumOracle(fixture));
      print(
        'yuv_rotate_v1 ${scenario.name}: ${timer.elapsedMicroseconds} us / $_runs calls '
        '(${(timer.elapsedMicroseconds / _runs).toStringAsFixed(2)} us/call), checksum=0x${_hex64(checksum)}',
      );
    });
  }
}

final class _Scenario {
  const _Scenario(this.name, this.format, this.degrees);
  final String name;
  final int format;
  final int degrees;
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
    this.sourcePlanes,
    this.destinationPlanes,
    this.sourceBytes,
    this.destinationBytes,
  );
  final _Scenario scenario;
  final Pointer<_ConstFrame> source;
  final Pointer<_MutableFrame> destination;
  final Pointer<_RotateOptions> options;
  final List<_Plane> sourcePlanes;
  final List<_Plane> destinationPlanes;
  final List<Pointer<Uint8>> sourceBytes;
  final List<Pointer<Uint8>> destinationBytes;
  static _Fixture create(_Scenario scenario) {
    List<_Plane> planes(int width, int height) => switch (scenario.format) {
      _i420 => [
        _Plane(width, height, 1),
        _Plane(width ~/ 2, height ~/ 2, 1),
        _Plane(width ~/ 2, height ~/ 2, 1),
      ],
      _nv12 => [_Plane(width, height, 1), _Plane(width ~/ 2, height ~/ 2, 2)],
      _bgra => [_Plane(width, height, 4)],
      _ => throw ArgumentError.value(scenario.format),
    };
    final transposed = scenario.degrees == 90 || scenario.degrees == 270;
    final sourcePlanes = planes(_width, _height);
    final destinationPlanes = planes(
      transposed ? _height : _width,
      transposed ? _width : _height,
    );
    final sourceBytes = [
      for (final plane in sourcePlanes) calloc<Uint8>(plane.length),
    ];
    final destinationBytes = [
      for (final plane in destinationPlanes) calloc<Uint8>(plane.length),
    ];
    for (var plane = 0; plane < sourcePlanes.length; plane++) {
      for (var index = 0; index < sourcePlanes[plane].length; index++)
        sourceBytes[plane][index] =
            (index * 37 + plane * 71 + scenario.format * 19) & 0xff;
    }
    final source = calloc<_ConstFrame>();
    final destination = calloc<_MutableFrame>();
    _setConstPlanes(source.ref.planes, sourcePlanes, sourceBytes);
    _setMutablePlanes(
      destination.ref.planes,
      destinationPlanes,
      destinationBytes,
    );
    final isBgra = scenario.format == _bgra;
    source.ref
      ..structSize = sizeOf<_ConstFrame>()
      ..abiVersion = _abi
      ..format = scenario.format
      ..planeCount = sourcePlanes.length
      ..width = _width
      ..height = _height
      ..colorMatrix = isBgra ? 0 : 1
      ..colorRange = isBgra ? 0 : 1;
    destination.ref
      ..structSize = sizeOf<_MutableFrame>()
      ..abiVersion = _abi
      ..format = scenario.format
      ..planeCount = destinationPlanes.length
      ..width = (transposed ? _height : _width)
      ..height = (transposed ? _width : _height)
      ..colorMatrix = isBgra ? 0 : 1
      ..colorRange = isBgra ? 0 : 1;
    final options = calloc<_RotateOptions>()
      ..ref.structSize = sizeOf<_RotateOptions>()
      ..ref.abiVersion = _abi
      ..ref.rotationDegrees = scenario.degrees;
    return _Fixture._(
      scenario,
      source,
      destination,
      options,
      sourcePlanes,
      destinationPlanes,
      sourceBytes,
      destinationBytes,
    );
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

int _oracleByte(_Fixture f, int plane, int index) {
  final destination = f.destinationPlanes[plane];
  final sample = index ~/ destination.bytes;
  final byte = index % destination.bytes;
  final x = sample % destination.width;
  final y = sample ~/ destination.width;
  final source = f.sourcePlanes[plane];
  final (sx, sy) = switch (f.scenario.degrees) {
    90 => (y, source.height - 1 - x),
    180 => (source.width - 1 - x, source.height - 1 - y),
    270 => (source.width - 1 - y, x),
    _ => (x, y),
  };
  return f.sourceBytes[plane][(sy * source.width + sx) * source.bytes + byte];
}

void _expectOutput(_Fixture f) {
  for (var p = 0; p < f.destinationPlanes.length; p++) {
    for (var i = 0; i < f.destinationPlanes[p].length; i++) {
      if (f.destinationBytes[p][i] != _oracleByte(f, p, i))
        fail('${f.scenario.name} plane $p byte $i differs');
    }
  }
}

int _checksumActual(_Fixture f) {
  var h = _offset;
  for (var p = 0; p < f.destinationPlanes.length; p++) {
    for (var i = 0; i < f.destinationPlanes[p].length; i++) {
      h = ((h ^ f.destinationBytes[p][i]) * _prime) & _mask;
    }
  }
  return h.toUnsigned(64);
}

int _checksumOracle(_Fixture f) {
  var h = _offset;
  for (var p = 0; p < f.destinationPlanes.length; p++) {
    for (var i = 0; i < f.destinationPlanes[p].length; i++) {
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
