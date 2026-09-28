import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

const _abiVersion = 1;
const _formatI420 = 1;
const _formatNv12 = 2;
const _formatBgra8888 = 3;
const _colorMatrixBt601 = 1;
const _colorRangeLimited = 1;
const _flipHorizontal = 1;
const _flipVertical = 2;
const _width = 1280;
const _height = 720;
const _warmupRuns = 20;
const _measuredRuns = 200;
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

final class _FlipOptions extends Struct {
  @Uint32()
  external int structSize;
  @Uint32()
  external int abiVersion;
  @Uint32()
  external int direction;
  @Uint32()
  external int reserved0;
  @Array.multi([2])
  external Array<Uint64> reserved;
}

typedef _NativeFlip =
    Int32 Function(
      Pointer<_ConstFrame> source,
      Pointer<_MutableFrame> destination,
      Pointer<_FlipOptions> options,
    );
typedef _DartFlip =
    int Function(
      Pointer<_ConstFrame> source,
      Pointer<_MutableFrame> destination,
      Pointer<_FlipOptions> options,
    );

const _scenarios = <_Scenario>[
  _Scenario('I420 horizontal', _formatI420, _flipHorizontal),
  _Scenario('I420 vertical', _formatI420, _flipVertical),
  _Scenario('NV12 horizontal', _formatNv12, _flipHorizontal),
  _Scenario('NV12 vertical', _formatNv12, _flipVertical),
  _Scenario('BGRA horizontal', _formatBgra8888, _flipHorizontal),
  _Scenario('BGRA vertical', _formatBgra8888, _flipVertical),
];

void main() {
  final dllPath = Platform.environment['YUV_FFI_DLL'];
  if (dllPath == null || !File(dllPath).existsSync()) {
    throw StateError(
      'Set YUV_FFI_DLL to the existing Release yuv_ffi.dll under test.',
    );
  }
  final library = DynamicLibrary.open(dllPath);
  final flip = library.lookupFunction<_NativeFlip, _DartFlip>('yuv_flip_v1');

  for (final scenario in _scenarios) {
    test('yuv_flip_v1 ${scenario.name}', () {
      final fixture = _FrameFixture.create(scenario);
      addTearDown(fixture.dispose);

      for (var run = 0; run < _warmupRuns; run++) {
        expect(
          flip(fixture.source, fixture.destination, fixture.options),
          0,
          reason: 'warm-up run $run',
        );
      }

      final callTimer = Stopwatch();
      var elapsedTicks = 0;
      for (var run = 0; run < _measuredRuns; run++) {
        callTimer
          ..reset()
          ..start();
        final status = flip(
          fixture.source,
          fixture.destination,
          fixture.options,
        );
        callTimer.stop();
        elapsedTicks += callTimer.elapsedTicks;
        if (status != 0) {
          fail('measured run $run returned ABI status $status');
        }
      }
      final elapsedMicroseconds =
          elapsedTicks * Duration.microsecondsPerSecond ~/ callTimer.frequency;

      _expectFlippedPixels(fixture);
      final checksum = _fnv1a(fixture.destinationBytes, fixture.planes);
      expect(checksum, equals(_oracleChecksum(fixture)));
      print(
        'yuv_flip_v1 ${scenario.name} ${_width}x$_height: '
        '$elapsedMicroseconds us / $_measuredRuns calls '
        '(${(elapsedMicroseconds / _measuredRuns).toStringAsFixed(2)} us/call), '
        'checksum=0x${_hex64(checksum)}',
      );
    });
  }
}

final class _Scenario {
  const _Scenario(this.name, this.format, this.direction);
  final String name;
  final int format;
  final int direction;
}

final class _PlaneLayout {
  const _PlaneLayout(this.width, this.height, this.sampleBytes);
  final int width;
  final int height;
  final int sampleBytes;
  int get length => width * height * sampleBytes;
}

final class _FrameFixture {
  _FrameFixture._(
    this.scenario,
    this.source,
    this.destination,
    this.options,
    this.planes,
    this.sourceBytes,
    this.destinationBytes,
  );

  final _Scenario scenario;
  final Pointer<_ConstFrame> source;
  final Pointer<_MutableFrame> destination;
  final Pointer<_FlipOptions> options;
  final List<_PlaneLayout> planes;
  final List<Pointer<Uint8>> sourceBytes;
  final List<Pointer<Uint8>> destinationBytes;

  static _FrameFixture create(_Scenario scenario) {
    final planes = switch (scenario.format) {
      _formatI420 => const [
        _PlaneLayout(_width, _height, 1),
        _PlaneLayout(_width ~/ 2, _height ~/ 2, 1),
        _PlaneLayout(_width ~/ 2, _height ~/ 2, 1),
      ],
      _formatNv12 => const [
        _PlaneLayout(_width, _height, 1),
        _PlaneLayout(_width ~/ 2, _height ~/ 2, 2),
      ],
      _formatBgra8888 => const [_PlaneLayout(_width, _height, 4)],
      _ => throw ArgumentError.value(scenario.format, 'format'),
    };
    final sourceBytes = [
      for (final plane in planes) calloc<Uint8>(plane.length),
    ];
    final destinationBytes = [
      for (final plane in planes) calloc<Uint8>(plane.length),
    ];
    final source = calloc<_ConstFrame>();
    final destination = calloc<_MutableFrame>();
    final options = calloc<_FlipOptions>();

    for (var planeIndex = 0; planeIndex < planes.length; planeIndex++) {
      final plane = planes[planeIndex];
      final bytes = sourceBytes[planeIndex];
      for (var index = 0; index < plane.length; index++) {
        bytes[index] =
            (index * 17 + planeIndex * 53 + scenario.format * 29) & 0xff;
      }
      source.ref.planes[planeIndex]
        ..length = plane.length
        ..rowStride = plane.width * plane.sampleBytes
        ..pixelStride = plane.sampleBytes
        ..sampleBytes = plane.sampleBytes
        ..data = bytes;
      destination.ref.planes[planeIndex]
        ..length = plane.length
        ..rowStride = plane.width * plane.sampleBytes
        ..pixelStride = plane.sampleBytes
        ..sampleBytes = plane.sampleBytes
        ..data = destinationBytes[planeIndex];
    }

    final isBgra = scenario.format == _formatBgra8888;
    source.ref
      ..structSize = sizeOf<_ConstFrame>()
      ..abiVersion = _abiVersion
      ..format = scenario.format
      ..planeCount = planes.length
      ..width = _width
      ..height = _height
      ..colorMatrix = isBgra ? 0 : _colorMatrixBt601
      ..colorRange = isBgra ? 0 : _colorRangeLimited;
    destination.ref
      ..structSize = sizeOf<_MutableFrame>()
      ..abiVersion = _abiVersion
      ..format = scenario.format
      ..planeCount = planes.length
      ..width = _width
      ..height = _height
      ..colorMatrix = isBgra ? 0 : _colorMatrixBt601
      ..colorRange = isBgra ? 0 : _colorRangeLimited;
    options.ref
      ..structSize = sizeOf<_FlipOptions>()
      ..abiVersion = _abiVersion
      ..direction = scenario.direction;

    return _FrameFixture._(
      scenario,
      source,
      destination,
      options,
      planes,
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

void _expectFlippedPixels(_FrameFixture fixture) {
  for (var planeIndex = 0; planeIndex < fixture.planes.length; planeIndex++) {
    final plane = fixture.planes[planeIndex];
    final source = fixture.sourceBytes[planeIndex];
    final destination = fixture.destinationBytes[planeIndex];
    for (var y = 0; y < plane.height; y++) {
      for (var x = 0; x < plane.width; x++) {
        final sourceX = fixture.scenario.direction == _flipHorizontal
            ? plane.width - 1 - x
            : x;
        final sourceY = fixture.scenario.direction == _flipVertical
            ? plane.height - 1 - y
            : y;
        final sourceOffset =
            (sourceY * plane.width + sourceX) * plane.sampleBytes;
        final destinationOffset = (y * plane.width + x) * plane.sampleBytes;
        for (var byte = 0; byte < plane.sampleBytes; byte++) {
          if (destination[destinationOffset + byte] !=
              source[sourceOffset + byte]) {
            fail(
              '${fixture.scenario.name} plane $planeIndex sample ($x, $y) differs at byte $byte',
            );
          }
        }
      }
    }
  }
}

int _oracleChecksum(_FrameFixture fixture) {
  var hash = _fnvOffsetBasis;
  for (var planeIndex = 0; planeIndex < fixture.planes.length; planeIndex++) {
    final plane = fixture.planes[planeIndex];
    final source = fixture.sourceBytes[planeIndex];
    for (var y = 0; y < plane.height; y++) {
      for (var x = 0; x < plane.width; x++) {
        final sourceX = fixture.scenario.direction == _flipHorizontal
            ? plane.width - 1 - x
            : x;
        final sourceY = fixture.scenario.direction == _flipVertical
            ? plane.height - 1 - y
            : y;
        final sourceOffset =
            (sourceY * plane.width + sourceX) * plane.sampleBytes;
        for (var byte = 0; byte < plane.sampleBytes; byte++) {
          hash =
              ((hash ^ source[sourceOffset + byte]) * _fnvPrime) & _uint64Mask;
        }
      }
    }
  }
  return hash.toUnsigned(64);
}

int _fnv1a(List<Pointer<Uint8>> planes, List<_PlaneLayout> layouts) {
  var hash = _fnvOffsetBasis;
  for (var planeIndex = 0; planeIndex < planes.length; planeIndex++) {
    for (var index = 0; index < layouts[planeIndex].length; index++) {
      hash = ((hash ^ planes[planeIndex][index]) * _fnvPrime) & _uint64Mask;
    }
  }
  return hash.toUnsigned(64);
}

String _hex64(int value) {
  final high = (value >> 32) & 0xffffffff;
  final low = value & 0xffffffff;
  return '${high.toRadixString(16).padLeft(8, '0')}${low.toRadixString(16).padLeft(8, '0')}';
}
