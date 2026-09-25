import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

const _abiVersion = 1;
const _i420 = 1;
const _nv12 = 2;
const _bgra = 3;
const _bt601 = 1;
const _limited = 1;
const _sourceWidth = 1280;
const _sourceHeight = 720;
const _warmupRuns = 10;
const _measuredRuns = 100;
const _fnvOffsetBasis = 0xcbf29ce484222325;
const _fnvPrime = 0x100000001b3;
const _uint64Mask = 0xffffffffffffffff;

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

final class _CropOptions extends Struct {
  @Uint32()
  external int structSize;
  @Uint32()
  external int abiVersion;
  @Int32()
  external int left;
  @Int32()
  external int top;
  @Uint32()
  external int width;
  @Uint32()
  external int height;
  @Array.multi([1])
  external Array<Uint64> reserved;
}

typedef _NativeCrop =
    Int32 Function(
      Pointer<_ConstFrame>,
      Pointer<_MutableFrame>,
      Pointer<_CropOptions>,
    );
typedef _DartCrop =
    int Function(
      Pointer<_ConstFrame>,
      Pointer<_MutableFrame>,
      Pointer<_CropOptions>,
    );

const _scenarios = <_Scenario>[
  _Scenario('I420 aligned', _i420, 128, 90, 960, 540),
  _Scenario('I420 odd origin', _i420, 127, 89, 960, 540),
  _Scenario('I420 odd edge', _i420, 128, 90, 959, 539),
  _Scenario('NV12 aligned', _nv12, 128, 90, 960, 540),
  _Scenario('NV12 odd origin', _nv12, 127, 89, 960, 540),
  _Scenario('NV12 odd edge', _nv12, 128, 90, 959, 539),
  _Scenario('BGRA even origin', _bgra, 128, 90, 960, 540),
  _Scenario('BGRA odd origin', _bgra, 127, 89, 959, 539),
];

void main() {
  final path = Platform.environment['YUV_FFI_DLL'];
  if (path == null || !File(path).existsSync()) {
    throw StateError(
      'Set YUV_FFI_DLL to the existing Release yuv_ffi.dll under test.',
    );
  }
  final crop = DynamicLibrary.open(
    path,
  ).lookupFunction<_NativeCrop, _DartCrop>('yuv_crop_v1');
  for (final scenario in _scenarios) {
    test('yuv_crop_v1 ${scenario.name}', () {
      final fixture = _Fixture.create(scenario);
      addTearDown(fixture.dispose);
      for (var run = 0; run < _warmupRuns; run++) {
        expect(
          crop(fixture.source, fixture.destination, fixture.options),
          0,
          reason: 'warm-up $run',
        );
      }
      final timer = Stopwatch()..start();
      var failedRun = -1;
      var failedStatus = 0;
      for (var run = 0; run < _measuredRuns; run++) {
        final status = crop(
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
      final microseconds = timer.elapsedMicroseconds;
      _expectOutput(fixture);
      final checksum = _checksumActual(fixture);
      expect(checksum, _checksumOracle(fixture));
      print(
        'yuv_crop_v1 ${scenario.name}: $microseconds us / $_measuredRuns calls '
        '(${(microseconds / _measuredRuns).toStringAsFixed(2)} us/call), checksum=0x${_hex64(checksum)}',
      );
    });
  }

  test('yuv_crop_v1 I420 odd origin with padded source rows', () {
    final fixture = _Fixture.create(_scenarios[1])..padSourceRows();
    addTearDown(fixture.dispose);
    expect(crop(fixture.source, fixture.destination, fixture.options), 0);
    _expectOutput(fixture);
    expect(_checksumActual(fixture), _checksumOracle(fixture));
  });
}

final class _Scenario {
  const _Scenario(
    this.name,
    this.format,
    this.left,
    this.top,
    this.width,
    this.height,
  );
  final String name;
  final int format;
  final int left;
  final int top;
  final int width;
  final int height;
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
    this.sourceRowStrides,
    this.destinationBytes,
  );
  final _Scenario scenario;
  final Pointer<_ConstFrame> source;
  final Pointer<_MutableFrame> destination;
  final Pointer<_CropOptions> options;
  final List<_Plane> sourcePlanes;
  final List<_Plane> destinationPlanes;
  final List<Pointer<Uint8>> sourceBytes;
  final List<int> sourceRowStrides;
  final List<Pointer<Uint8>> destinationBytes;

  static _Fixture create(_Scenario scenario) {
    List<_Plane> planes(int width, int height) => switch (scenario.format) {
      _i420 => [
        _Plane(width, height, 1),
        _Plane((width + 1) ~/ 2, (height + 1) ~/ 2, 1),
        _Plane((width + 1) ~/ 2, (height + 1) ~/ 2, 1),
      ],
      _nv12 => [
        _Plane(width, height, 1),
        _Plane((width + 1) ~/ 2, (height + 1) ~/ 2, 2),
      ],
      _bgra => [_Plane(width, height, 4)],
      _ => throw ArgumentError.value(scenario.format),
    };
    final sourcePlanes = planes(_sourceWidth, _sourceHeight);
    final destinationPlanes = planes(scenario.width, scenario.height);
    final sourceBytes = [
      for (final plane in sourcePlanes) calloc<Uint8>(plane.length),
    ];
    final sourceRowStrides = [
      for (final plane in sourcePlanes) plane.width * plane.bytes,
    ];
    final destinationBytes = [
      for (final plane in destinationPlanes) calloc<Uint8>(plane.length),
    ];
    for (var plane = 0; plane < sourcePlanes.length; plane++) {
      for (var byte = 0; byte < sourcePlanes[plane].length; byte++) {
        sourceBytes[plane][byte] =
            (byte * 37 + plane * 71 + scenario.format * 19) & 0xff;
      }
    }
    final source = calloc<_ConstFrame>();
    final destination = calloc<_MutableFrame>();
    _writeConstPlanes(source.ref.planes, sourcePlanes, sourceBytes);
    _writeMutablePlanes(
      destination.ref.planes,
      destinationPlanes,
      destinationBytes,
    );
    final isBgra = scenario.format == _bgra;
    source.ref
      ..structSize = sizeOf<_ConstFrame>()
      ..abiVersion = _abiVersion
      ..format = scenario.format
      ..planeCount = sourcePlanes.length
      ..width = _sourceWidth
      ..height = _sourceHeight
      ..colorMatrix = isBgra ? 0 : _bt601
      ..colorRange = isBgra ? 0 : _limited;
    destination.ref
      ..structSize = sizeOf<_MutableFrame>()
      ..abiVersion = _abiVersion
      ..format = scenario.format
      ..planeCount = destinationPlanes.length
      ..width = scenario.width
      ..height = scenario.height
      ..colorMatrix = isBgra ? 0 : _bt601
      ..colorRange = isBgra ? 0 : _limited;
    final options = calloc<_CropOptions>()
      ..ref.structSize = sizeOf<_CropOptions>()
      ..ref.abiVersion = _abiVersion
      ..ref.left = scenario.left
      ..ref.top = scenario.top
      ..ref.width = scenario.width
      ..ref.height = scenario.height;
    return _Fixture._(
      scenario,
      source,
      destination,
      options,
      sourcePlanes,
      destinationPlanes,
      sourceBytes,
      sourceRowStrides,
      destinationBytes,
    );
  }

  void padSourceRows() {
    for (var planeIndex = 0; planeIndex < sourcePlanes.length; planeIndex++) {
      final plane = sourcePlanes[planeIndex];
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
    for (final bytes in sourceBytes) calloc.free(bytes);
    for (final bytes in destinationBytes) calloc.free(bytes);
  }
}

void _writeConstPlanes(
  Array<_ConstPlane> target,
  List<_Plane> planes,
  List<Pointer<Uint8>> bytes,
) {
  for (var index = 0; index < planes.length; index++) {
    final plane = planes[index];
    target[index]
      ..length = plane.length
      ..rowStride = plane.width * plane.bytes
      ..pixelStride = plane.bytes
      ..sampleBytes = plane.bytes
      ..data = bytes[index];
  }
}

void _writeMutablePlanes(
  Array<_MutablePlane> target,
  List<_Plane> planes,
  List<Pointer<Uint8>> bytes,
) {
  for (var index = 0; index < planes.length; index++) {
    final plane = planes[index];
    target[index]
      ..length = plane.length
      ..rowStride = plane.width * plane.bytes
      ..pixelStride = plane.bytes
      ..sampleBytes = plane.bytes
      ..data = bytes[index];
  }
}

void _expectOutput(_Fixture fixture) {
  for (var plane = 0; plane < fixture.destinationPlanes.length; plane++) {
    for (
      var index = 0;
      index < fixture.destinationPlanes[plane].length;
      index++
    ) {
      final actual = fixture.destinationBytes[plane][index];
      final expected = _oracleByte(fixture, plane, index);
      if (actual != expected) {
        fail(
          '${fixture.scenario.name} plane $plane byte $index: expected $expected, got $actual',
        );
      }
    }
  }
}

int _checksumActual(_Fixture fixture) {
  var hash = _fnvOffsetBasis;
  for (var plane = 0; plane < fixture.destinationPlanes.length; plane++) {
    for (
      var index = 0;
      index < fixture.destinationPlanes[plane].length;
      index++
    ) {
      hash =
          ((hash ^ fixture.destinationBytes[plane][index]) * _fnvPrime) &
          _uint64Mask;
    }
  }
  return hash.toUnsigned(64);
}

int _checksumOracle(_Fixture fixture) {
  var hash = _fnvOffsetBasis;
  for (var plane = 0; plane < fixture.destinationPlanes.length; plane++) {
    for (
      var index = 0;
      index < fixture.destinationPlanes[plane].length;
      index++
    ) {
      hash =
          ((hash ^ _oracleByte(fixture, plane, index)) * _fnvPrime) &
          _uint64Mask;
    }
  }
  return hash.toUnsigned(64);
}

int _oracleByte(_Fixture fixture, int plane, int byteIndex) {
  final layout = fixture.destinationPlanes[plane];
  final sample = byteIndex ~/ layout.bytes;
  final byte = byteIndex % layout.bytes;
  final x = sample % layout.width;
  final y = sample ~/ layout.width;
  if (fixture.scenario.format == _bgra) {
    return _sourceByte(
      fixture,
      0,
      fixture.scenario.left + x,
      fixture.scenario.top + y,
      byte,
    );
  }
  if (plane == 0) {
    return _sourceByte(
      fixture,
      0,
      fixture.scenario.left + x,
      fixture.scenario.top + y,
      0,
    );
  }
  if (_blockAligned(fixture)) {
    final sourceX = fixture.scenario.left ~/ 2 + x;
    final sourceY = fixture.scenario.top ~/ 2 + y;
    return _sourceByte(fixture, plane, sourceX, sourceY, byte);
  }
  final uv = _reencodedChroma(fixture, x, y);
  if (fixture.scenario.format == _i420) {
    return plane == 1 ? uv.$1 : uv.$2;
  }
  return byte == 0 ? uv.$1 : uv.$2;
}

bool _blockAligned(_Fixture fixture) {
  final scenario = fixture.scenario;
  final right = scenario.left + scenario.width;
  final bottom = scenario.top + scenario.height;
  return scenario.left.isEven &&
      scenario.top.isEven &&
      (scenario.width.isEven || right == _sourceWidth) &&
      (scenario.height.isEven || bottom == _sourceHeight);
}

(int, int) _reencodedChroma(_Fixture fixture, int blockX, int blockY) {
  var red = 0;
  var green = 0;
  var blue = 0;
  var count = 0;
  for (var offsetY = 0; offsetY < 2; offsetY++) {
    final destinationY = blockY * 2 + offsetY;
    if (destinationY >= fixture.scenario.height) continue;
    for (var offsetX = 0; offsetX < 2; offsetX++) {
      final destinationX = blockX * 2 + offsetX;
      if (destinationX >= fixture.scenario.width) continue;
      final sourceX = fixture.scenario.left + destinationX;
      final sourceY = fixture.scenario.top + destinationY;
      final y = _sourceByte(fixture, 0, sourceX, sourceY, 0);
      final chromaX = sourceX ~/ 2;
      final chromaY = sourceY ~/ 2;
      final u = _sourceByte(fixture, 1, chromaX, chromaY, 0);
      final v = fixture.scenario.format == _i420
          ? _sourceByte(fixture, 2, chromaX, chromaY, 0)
          : _sourceByte(fixture, 1, chromaX, chromaY, 1);
      final pixel = _decode(y, u, v);
      red += pixel.$1;
      green += pixel.$2;
      blue += pixel.$3;
      count++;
    }
  }
  return (
    _rgbToU(red ~/ count, green ~/ count, blue ~/ count),
    _rgbToV(red ~/ count, green ~/ count, blue ~/ count),
  );
}

int _sourceByte(_Fixture fixture, int plane, int x, int y, int byte) {
  final layout = fixture.sourcePlanes[plane];
  return fixture.sourceBytes[plane][y * fixture.sourceRowStrides[plane] +
      x * layout.bytes +
      byte];
}

(int, int, int) _decode(int y, int u, int v) {
  final c = y - 16;
  final d = u - 128;
  final e = v - 128;
  return (
    _clip((298 * c + 409 * e + 128) >> 8),
    _clip((298 * c - 100 * d - 208 * e + 128) >> 8),
    _clip((298 * c + 516 * d + 128) >> 8),
  );
}

int _rgbToU(int r, int g, int b) =>
    _clip(((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128);
int _rgbToV(int r, int g, int b) =>
    _clip(((112 * r - 94 * g - 18 * b + 128) >> 8) + 128);
int _clip(int value) => value.clamp(0, 255);

String _hex64(int value) {
  final high = (value >> 32) & 0xffffffff;
  final low = value & 0xffffffff;
  return '${high.toRadixString(16).padLeft(8, '0')}${low.toRadixString(16).padLeft(8, '0')}';
}
