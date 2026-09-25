import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

const _abiVersion = 1;
const _nv12 = 2;
const _bt601 = 1;
const _limited = 1;
const _width = 1280;
const _height = 720;
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
  external _Region region;
  @Array.multi([2])
  external Array<Uint64> reserved;
}

typedef _NativeSwap =
    Int32 Function(
      Pointer<_ConstFrame>,
      Pointer<_MutableFrame>,
      Pointer<_Options>,
    );
typedef _DartSwap =
    int Function(
      Pointer<_ConstFrame>,
      Pointer<_MutableFrame>,
      Pointer<_Options>,
    );

void main() {
  final path = Platform.environment['YUV_FFI_DLL'];
  if (path == null || !File(path).existsSync()) {
    throw StateError('Set YUV_FFI_DLL to the Release yuv_ffi.dll under test.');
  }
  final swap = DynamicLibrary.open(
    path,
  ).lookupFunction<_NativeSwap, _DartSwap>('yuv_chroma_swap_v1');

  for (final padded in [false, true]) {
    final label = padded ? 'NV12 padded and gapped fallback' : 'NV12 tight';
    test('yuv_chroma_swap_v1 $label', () {
      final fixture = _Fixture.create(padded: padded);
      addTearDown(fixture.dispose);
      for (var run = 0; run < _warmupRuns; run++) {
        expect(swap(fixture.source, fixture.destination, fixture.options), 0);
      }
      final timer = Stopwatch()..start();
      var failedRun = -1;
      var failedStatus = 0;
      for (var run = 0; run < _measuredRuns; run++) {
        final status = swap(
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
        fail('run $failedRun returned ABI status $failedStatus');
      }
      _expectSwapped(fixture);
      final checksum = _checksumActual(fixture);
      expect(checksum, _checksumOracle(fixture));
      print(
        'yuv_chroma_swap_v1 $label: ${timer.elapsedMicroseconds} us / '
        '$_measuredRuns calls '
        '(${(timer.elapsedMicroseconds / _measuredRuns).toStringAsFixed(2)} us/call), '
        'checksum=0x${_hex64(checksum)}',
      );
    });
  }

  test('yuv_chroma_swap_v1 rejects enabled ROI without writes', () {
    final fixture = _Fixture.create(padded: false);
    addTearDown(fixture.dispose);
    fixture.options.ref.region
      ..left = 8
      ..top = 10
      ..right = 128
      ..bottom = 130
      ..enabled = 1;
    final before = _snapshot(fixture);
    expect(swap(fixture.source, fixture.destination, fixture.options), 1);
    expect(_snapshot(fixture), before);
  });
}

final class _Fixture {
  _Fixture._(
    this.source,
    this.destination,
    this.options,
    this.sourceBytes,
    this.destinationBytes,
    this.sourceLayouts,
    this.destinationLayouts,
    this.padded,
  );

  final Pointer<_ConstFrame> source;
  final Pointer<_MutableFrame> destination;
  final Pointer<_Options> options;
  final List<Pointer<Uint8>> sourceBytes;
  final List<Pointer<Uint8>> destinationBytes;
  final List<_Layout> sourceLayouts;
  final List<_Layout> destinationLayouts;
  final bool padded;

  static _Fixture create({required bool padded}) {
    final yRow = _width + (padded ? 19 : 0);
    final uvRow = _width + (padded ? _width + 34 : 0);
    final uvPixel = padded ? 4 : 2;
    final layouts = [
      _Layout(_width, _height, yRow, 1, 1),
      _Layout((_width + 1) ~/ 2, (_height + 1) ~/ 2, uvRow, uvPixel, 2),
    ];
    final sources = [
      for (final layout in layouts) calloc<Uint8>(layout.length),
    ];
    final destinations = [
      for (final layout in layouts) calloc<Uint8>(layout.length),
    ];
    for (var plane = 0; plane < layouts.length; plane++) {
      final length = layouts[plane].length;
      for (var byte = 0; byte < length; byte++) {
        sources[plane][byte] = (byte * 37 + plane * 71 + 23) & 0xff;
        destinations[plane][byte] = (byte * 11 + plane * 43 + 7) & 0xff;
      }
    }
    final source = calloc<_ConstFrame>();
    final destination = calloc<_MutableFrame>();
    final options = calloc<_Options>()
      ..ref.structSize = sizeOf<_Options>()
      ..ref.abiVersion = _abiVersion;
    options.ref.region
      ..structSize = sizeOf<_Region>()
      ..abiVersion = _abiVersion;
    for (var i = 0; i < layouts.length; i++) {
      final layout = layouts[i];
      source.ref.planes[i]
        ..length = layout.length
        ..rowStride = layout.rowStride
        ..pixelStride = layout.pixelStride
        ..sampleBytes = layout.sampleBytes
        ..data = sources[i];
      destination.ref.planes[i]
        ..length = layout.length
        ..rowStride = layout.rowStride
        ..pixelStride = layout.pixelStride
        ..sampleBytes = layout.sampleBytes
        ..data = destinations[i];
    }
    source.ref
      ..structSize = sizeOf<_ConstFrame>()
      ..abiVersion = _abiVersion
      ..format = _nv12
      ..planeCount = 2
      ..width = _width
      ..height = _height
      ..colorMatrix = _bt601
      ..colorRange = _limited;
    destination.ref
      ..structSize = sizeOf<_MutableFrame>()
      ..abiVersion = _abiVersion
      ..format = _nv12
      ..planeCount = 2
      ..width = _width
      ..height = _height
      ..colorMatrix = _bt601
      ..colorRange = _limited;
    return _Fixture._(
      source,
      destination,
      options,
      sources,
      destinations,
      layouts,
      layouts,
      padded,
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

final class _Layout {
  const _Layout(
    this.width,
    this.height,
    this.rowStride,
    this.pixelStride,
    this.sampleBytes,
  );
  final int width;
  final int height;
  final int rowStride;
  final int pixelStride;
  final int sampleBytes;
  int get length => height * rowStride;
}

void _expectSwapped(_Fixture fixture) {
  final ySource = fixture.sourceBytes[0];
  final yDestination = fixture.destinationBytes[0];
  final yLayout = fixture.sourceLayouts[0];
  for (var y = 0; y < yLayout.height; y++) {
    for (var x = 0; x < yLayout.width; x++) {
      expect(
        yDestination[y * yLayout.rowStride + x * yLayout.pixelStride],
        ySource[y * yLayout.rowStride + x * yLayout.pixelStride],
        reason: 'Y sample ($x,$y)',
      );
    }
  }
  final uvSource = fixture.sourceBytes[1];
  final uvDestination = fixture.destinationBytes[1];
  final uv = fixture.sourceLayouts[1];
  for (var y = 0; y < uv.height; y++) {
    for (var x = 0; x < uv.width; x++) {
      final offset = y * uv.rowStride + x * uv.pixelStride;
      expect(uvDestination[offset], uvSource[offset + 1], reason: 'U ($x,$y)');
      expect(uvDestination[offset + 1], uvSource[offset], reason: 'V ($x,$y)');
    }
  }
  if (fixture.padded) {
    for (var plane = 0; plane < 2; plane++) {
      final layout = fixture.destinationLayouts[plane];
      for (var offset = 0; offset < layout.length; offset++) {
        final row = offset ~/ layout.rowStride;
        final inRow = offset % layout.rowStride;
        final sampleX = inRow ~/ layout.pixelStride;
        final inSample = inRow % layout.pixelStride;
        final active =
            row < layout.height &&
            sampleX < layout.width &&
            inSample < layout.sampleBytes;
        if (!active) {
          expect(
            fixture.destinationBytes[plane][offset],
            _initialDestination(plane, offset),
            reason: 'padding byte plane $plane offset $offset',
          );
        }
      }
    }
  }
}

int _initialDestination(int plane, int byte) =>
    (byte * 11 + plane * 43 + 7) & 0xff;

int _checksumActual(_Fixture fixture) {
  var hash = _fnvOffsetBasis;
  for (var plane = 0; plane < 2; plane++) {
    final layout = fixture.destinationLayouts[plane];
    for (var y = 0; y < layout.height; y++) {
      for (var x = 0; x < layout.width; x++) {
        final offset = y * layout.rowStride + x * layout.pixelStride;
        for (var byte = 0; byte < layout.sampleBytes; byte++) {
          hash =
              ((hash ^ fixture.destinationBytes[plane][offset + byte]) *
                  _fnvPrime) &
              _uint64Mask;
        }
      }
    }
  }
  return hash.toUnsigned(64);
}

int _checksumOracle(_Fixture fixture) {
  var hash = _fnvOffsetBasis;
  for (var plane = 0; plane < 2; plane++) {
    final layout = fixture.sourceLayouts[plane];
    for (var y = 0; y < layout.height; y++) {
      for (var x = 0; x < layout.width; x++) {
        final offset = y * layout.rowStride + x * layout.pixelStride;
        for (var byte = 0; byte < layout.sampleBytes; byte++) {
          final value = plane == 1 && byte == 0
              ? fixture.sourceBytes[plane][offset + 1]
              : plane == 1 && byte == 1
              ? fixture.sourceBytes[plane][offset]
              : fixture.sourceBytes[plane][offset + byte];
          hash = ((hash ^ value) * _fnvPrime) & _uint64Mask;
        }
      }
    }
  }
  return hash.toUnsigned(64);
}

List<List<int>> _snapshot(_Fixture fixture) => [
  for (var plane = 0; plane < fixture.destinationBytes.length; plane++)
    [
      for (var i = 0; i < fixture.destinationLayouts[plane].length; i++)
        fixture.destinationBytes[plane][i],
    ],
];

String _hex64(int value) {
  final high = (value >> 32) & 0xffffffff;
  final low = value & 0xffffffff;
  return '${high.toRadixString(16).padLeft(8, '0')}'
      '${low.toRadixString(16).padLeft(8, '0')}';
}
