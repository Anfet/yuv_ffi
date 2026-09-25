import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

const _abiVersion = 1;
const _formatI420 = 1;
const _colorMatrixBt601 = 1;
const _colorRangeLimited = 1;
const _flipHorizontal = 1;
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

void main() {
  test(
    'yuv_flip_v1 flips a fixed I420 frame and reports native-call timing',
    () {
      final dllPath = Platform.environment['YUV_FFI_DLL'];
      expect(
        dllPath,
        isNotNull,
        reason: 'Set YUV_FFI_DLL to the Release yuv_ffi.dll under test.',
      );
      expect(
        File(dllPath!).existsSync(),
        isTrue,
        reason: 'Release DLL does not exist: $dllPath',
      );

      final library = DynamicLibrary.open(dllPath);
      final flip = library.lookupFunction<_NativeFlip, _DartFlip>(
        'yuv_flip_v1',
      );
      final fixture = _I420Fixture.create();
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

      _expectHorizontalI420(fixture);
      final checksum = _fnv1a(fixture.destinationBytes);
      print(
        'yuv_flip_v1 I420 ${_width}x$_height: '
        '$elapsedMicroseconds us / $_measuredRuns calls '
        '(${(elapsedMicroseconds / _measuredRuns).toStringAsFixed(2)} us/call), '
        'checksum=0x${_hex64(checksum)}',
      );
      expect(checksum, equals(_expectedHorizontalI420Checksum));
    },
  );
}

const _expectedHorizontalI420Checksum = -1208091124080640731;

void _expectHorizontalI420(_I420Fixture fixture) {
  for (var plane = 0; plane < fixture.sourceBytes.length; plane++) {
    final planeWidth = plane == 0 ? _width : _width ~/ 2;
    final planeHeight = plane == 0 ? _height : _height ~/ 2;
    final source = fixture.sourceBytes[plane];
    final destination = fixture.destinationBytes[plane];
    for (var y = 0; y < planeHeight; y++) {
      for (var x = 0; x < planeWidth; x++) {
        final expected = source[y * planeWidth + (planeWidth - 1 - x)];
        final actual = destination[y * planeWidth + x];
        if (actual != expected) {
          fail(
            'I420 plane $plane sample ($x, $y): expected $expected, got $actual',
          );
        }
      }
    }
  }
}

String _hex64(int value) {
  final high = (value >> 32) & 0xffffffff;
  final low = value & 0xffffffff;
  return '${high.toRadixString(16).padLeft(8, '0')}${low.toRadixString(16).padLeft(8, '0')}';
}

int _fnv1a(List<Pointer<Uint8>> planes) {
  var hash = _fnvOffsetBasis;
  final lengths = <int>[
    _width * _height,
    (_width ~/ 2) * (_height ~/ 2),
    (_width ~/ 2) * (_height ~/ 2),
  ];
  for (var planeIndex = 0; planeIndex < planes.length; planeIndex++) {
    final plane = planes[planeIndex];
    for (var index = 0; index < lengths[planeIndex]; index++) {
      hash = ((hash ^ plane[index]) * _fnvPrime) & _uint64Mask;
    }
  }
  return hash.toUnsigned(64);
}

final class _I420Fixture {
  _I420Fixture._(
    this.source,
    this.destination,
    this.options,
    this.sourceBytes,
    this.destinationBytes,
  );

  final Pointer<_ConstFrame> source;
  final Pointer<_MutableFrame> destination;
  final Pointer<_FlipOptions> options;
  final List<Pointer<Uint8>> sourceBytes;
  final List<Pointer<Uint8>> destinationBytes;

  static _I420Fixture create() {
    final sourceBytes = <Pointer<Uint8>>[
      calloc<Uint8>(_width * _height),
      calloc<Uint8>((_width ~/ 2) * (_height ~/ 2)),
      calloc<Uint8>((_width ~/ 2) * (_height ~/ 2)),
    ];
    final destinationBytes = <Pointer<Uint8>>[
      calloc<Uint8>(_width * _height),
      calloc<Uint8>((_width ~/ 2) * (_height ~/ 2)),
      calloc<Uint8>((_width ~/ 2) * (_height ~/ 2)),
    ];
    final source = calloc<_ConstFrame>();
    final destination = calloc<_MutableFrame>();
    final options = calloc<_FlipOptions>();

    for (var plane = 0; plane < sourceBytes.length; plane++) {
      final planeWidth = plane == 0 ? _width : _width ~/ 2;
      final planeHeight = plane == 0 ? _height : _height ~/ 2;
      final data = sourceBytes[plane];
      for (var y = 0; y < planeHeight; y++) {
        for (var x = 0; x < planeWidth; x++) {
          data[y * planeWidth + x] = (x * 17 + y * 31 + plane * 53) & 0xff;
        }
      }
      source.ref.planes[plane]
        ..length = planeWidth * planeHeight
        ..rowStride = planeWidth
        ..pixelStride = 1
        ..sampleBytes = 1
        ..data = data;
      destination.ref.planes[plane]
        ..length = planeWidth * planeHeight
        ..rowStride = planeWidth
        ..pixelStride = 1
        ..sampleBytes = 1
        ..data = destinationBytes[plane];
    }

    source.ref
      ..structSize = sizeOf<_ConstFrame>()
      ..abiVersion = _abiVersion
      ..format = _formatI420
      ..planeCount = 3
      ..width = _width
      ..height = _height
      ..colorMatrix = _colorMatrixBt601
      ..colorRange = _colorRangeLimited;
    destination.ref
      ..structSize = sizeOf<_MutableFrame>()
      ..abiVersion = _abiVersion
      ..format = _formatI420
      ..planeCount = 3
      ..width = _width
      ..height = _height
      ..colorMatrix = _colorMatrixBt601
      ..colorRange = _colorRangeLimited;
    options.ref
      ..structSize = sizeOf<_FlipOptions>()
      ..abiVersion = _abiVersion
      ..direction = _flipHorizontal;

    return _I420Fixture._(
      source,
      destination,
      options,
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
