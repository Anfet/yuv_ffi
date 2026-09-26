import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

// BGRA-03: isolates the one stage BGRA-00 flagged as the second-largest
// share of the full toBgraBytes()/toBgra() call (dest_alloc_zero, ~33%) and
// measures the candidate directly: allocate the destination with `malloc`
// (uninitialized) instead of `calloc` (zero-filled), for the full-frame
// convert destination only. This mirrors
// yuv_convert_v1_bgra_stages_test.dart's structure and inputs so the two
// reports are directly comparable; it does not touch native C.
const _width = 1920;
const _height = 1080;
const _warmup = 5;
const _runs = 30;
const _fnvBasis = 0xcbf29ce484222325;
const _fnvPrime = 0x100000001b3;
const _mask64 = 0xffffffffffffffff;

const _formatI420 = 1;
const _formatNv12 = 2;
const _formatBgra = 3;

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

typedef _NativeConvert = Int32 Function(Pointer<_Frame>, Pointer<_Frame>, Pointer<_Options>);
typedef _DartConvert = int Function(Pointer<_Frame>, Pointer<_Frame>, Pointer<_Options>);

const _names = ['unused', 'I420', 'NV12', 'BGRA'];

void main() {
  final path = Platform.environment['YUV_FFI_DLL'];
  if (!Platform.isWindows || path == null || !File(path).existsSync()) {
    throw StateError('Set YUV_FFI_DLL to the Windows Release yuv_ffi.dll');
  }
  final convert = DynamicLibrary.open(path).lookupFunction<_NativeConvert, _DartConvert>('yuv_convert_v1');

  for (final sourceFormat in [_formatNv12, _formatI420]) {
    final name = '${_names[sourceFormat]}->BGRA';
    test('yuv_convert_v1 dest_alloc candidates $name', () {
      final sourceBytes = _makeSourceBytes(sourceFormat);
      final expected = _oracleBgra(sourceFormat, sourceBytes);
      final expectedHash = _checksum([expected]);

      for (final useMalloc in [false, true]) {
        final label = useMalloc ? 'malloc' : 'calloc';
        final destAllocSamples = <double>[];
        final fullCallSamples = <double>[];
        late List<int> lastResult;

        double timeDestAllocOnly() {
          final sw = Stopwatch()..start();
          final dest = _allocateDestinationFrame(useMalloc: useMalloc);
          sw.stop();
          _freeFrame(dest.frame, dest.buffers, useMalloc: useMalloc);
          return sw.elapsedTicks * 1000000 / sw.frequency;
        }

        double timeFullCall() {
          final sw = Stopwatch()..start();
          final source = _allocateSourceFrame(sourceFormat, sourceBytes);
          final dest = _allocateDestinationFrame(useMalloc: useMalloc);
          final options = calloc<_Options>();
          options.ref
            ..structSize = sizeOf<_Options>()
            ..abiVersion = 1;
          final status = convert(source.frame, dest.frame, options);
          expect(status, 0);
          final result = _copyDestinationBgra(dest.buffers.single);
          sw.stop();
          calloc.free(options);
          _freeFrame(source.frame, source.buffers, useMalloc: false);
          _freeFrame(dest.frame, dest.buffers, useMalloc: useMalloc);
          lastResult = result;
          return sw.elapsedTicks * 1000000 / sw.frequency;
        }

        for (var i = 0; i < _warmup; i++) {
          timeDestAllocOnly();
          timeFullCall();
        }

        for (var i = 0; i < _runs; i++) {
          destAllocSamples.add(timeDestAllocOnly());
          fullCallSamples.add(timeFullCall());
          final actualHash = _checksum([lastResult]);
          if (actualHash != expectedHash) fail('$name/$label byte mismatch at run $i');
        }

        void report(String stage, List<double> samples) {
          final sorted = samples.toList()..sort();
          final median = sorted[sorted.length ~/ 2];
          print(
            'BGRA-03 $name $label $stage ${_width}x$_height: median=${(median / 1000).toStringAsFixed(4)} ms '
            'min=${(sorted.first / 1000).toStringAsFixed(4)} ms max=${(sorted.last / 1000).toStringAsFixed(4)} ms '
            'n=${samples.length}',
          );
        }

        report('dest_alloc', destAllocSamples);
        report('full_call', fullCallSamples);
        print('BGRA-03 $name $label checksum=0x${_hex64(expectedHash)}');
      }
    });
  }
}

class _Allocated {
  _Allocated(this.frame, this.buffers);
  final Pointer<_Frame> frame;
  final List<Pointer<Uint8>> buffers;
}

List<int> _sizes(int format) {
  final cw = (_width + 1) ~/ 2;
  final ch = (_height + 1) ~/ 2;
  return switch (format) {
    _formatI420 => [_width * _height, cw * ch, cw * ch],
    _formatNv12 => [_width * _height, cw * ch * 2],
    _ => [_width * _height * 4],
  };
}

List<Uint8List> _makeSourceBytes(int format) {
  final sizes = _sizes(format);
  return [
    for (var p = 0; p < sizes.length; p++)
      Uint8List.fromList(List<int>.generate(sizes[p], (i) => (i * 37 + (i ~/ 251) * 23 + p * 67 + format * 19) & 255)),
  ];
}

_Allocated _allocateSourceFrame(int format, List<Uint8List> sourceBytes) {
  final frame = calloc<_Frame>();
  final cw = (_width + 1) ~/ 2;
  final buffers = <Pointer<Uint8>>[];
  frame.ref
    ..structSize = sizeOf<_Frame>()
    ..abiVersion = 1
    ..format = format
    ..planeCount = sourceBytes.length
    ..width = _width
    ..height = _height
    ..colorMatrix = 1
    ..colorRange = 1;
  for (var p = 0; p < sourceBytes.length; p++) {
    final stride = format == _formatNv12 && p == 1 ? 2 : 1;
    final planeWidth = p == 0 ? _width : cw;
    final size = sourceBytes[p].length;
    // Source staging always stays calloc-backed here (BGRA-03 is only about
    // the destination); measuring it is BGRA-00's job, not this file's.
    final buffer = calloc<Uint8>(size);
    buffers.add(buffer);
    buffer.asTypedList(size).setAll(0, sourceBytes[p]);
    frame.ref.planes[p]
      ..length = size
      ..rowStride = planeWidth * stride
      ..pixelStride = stride
      ..sampleBytes = stride
      ..data = buffer;
  }
  return _Allocated(frame, buffers);
}

_Allocated _allocateDestinationFrame({required bool useMalloc}) {
  final frame = calloc<_Frame>();
  final size = _width * _height * 4;
  // The candidate under test: `malloc` leaves the buffer uninitialized,
  // `calloc` zero-fills it. Both are freed with the matching free below;
  // package:ffi's calloc/malloc share one native allocator, but which
  // allocate call was used is tracked explicitly rather than assumed.
  final buffer = useMalloc ? malloc<Uint8>(size) : calloc<Uint8>(size);
  frame.ref
    ..structSize = sizeOf<_Frame>()
    ..abiVersion = 1
    ..format = _formatBgra
    ..planeCount = 1
    ..width = _width
    ..height = _height
    ..colorMatrix = 0
    ..colorRange = 0;
  frame.ref.planes[0]
    ..length = size
    ..rowStride = _width * 4
    ..pixelStride = 4
    ..sampleBytes = 4
    ..data = buffer;
  return _Allocated(frame, [buffer]);
}

Uint8List _copyDestinationBgra(Pointer<Uint8> buffer) {
  final size = _width * _height * 4;
  return Uint8List.fromList(buffer.asTypedList(size));
}

void _freeFrame(Pointer<_Frame> frame, List<Pointer<Uint8>> buffers, {required bool useMalloc}) {
  for (final buffer in buffers) {
    if (useMalloc) {
      malloc.free(buffer);
    } else {
      calloc.free(buffer);
    }
  }
  calloc.free(frame);
}

int _clip(int v) => v < 0 ? 0 : (v > 255 ? 255 : v);

List<int> _pixel(int sourceFormat, List<List<int>> src, int x, int y) {
  final yy = src[0][y * _width + x];
  final cw = (_width + 1) ~/ 2;
  final co = (y ~/ 2) * cw + x ~/ 2;
  final uu = sourceFormat == _formatI420 ? src[1][co] : src[1][co * 2];
  final vv = sourceFormat == _formatI420 ? src[2][co] : src[1][co * 2 + 1];
  final c = yy - 16, d = uu - 128, e = vv - 128;
  return [_clip((298 * c + 409 * e + 128) >> 8), _clip((298 * c - 100 * d - 208 * e + 128) >> 8), _clip((298 * c + 516 * d + 128) >> 8), 255];
}

List<int> _oracleBgra(int sourceFormat, List<List<int>> src) {
  final dst = List<int>.filled(_width * _height * 4, 0);
  for (var y = 0; y < _height; y++) {
    for (var x = 0; x < _width; x++) {
      final pixel = _pixel(sourceFormat, src, x, y);
      final offset = (y * _width + x) * 4;
      dst[offset] = pixel[2];
      dst[offset + 1] = pixel[1];
      dst[offset + 2] = pixel[0];
      dst[offset + 3] = pixel[3];
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
  return '${high.toRadixString(16).padLeft(8, '0')}${low.toRadixString(16).padLeft(8, '0')}';
}
