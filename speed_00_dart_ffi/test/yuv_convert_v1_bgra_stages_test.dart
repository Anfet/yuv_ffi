import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

// BGRA-00: decomposes the public toBgraBytes()/toBgra() call into the same
// stages YuvAbiV1Runner._run performs (see
// lib/src/yuv/impl/io/abi/yuv_abi_v1_runner.dart, steps 2/3/5/7): Dart input
// staging (calloc + copy source bytes into native buffers), destination
// allocation/zero-fill (calloc), the yuv_convert_v1 native call, and copying
// the destination planes back into a Dart buffer. Each stage is timed on its
// own so a later optimization task can be pointed at whichever stage the
// measurement blames, instead of only at the full public call.
//
// This file does not call the yuv_ffi package; it drives the same ABI v1
// struct layout yuv_convert_v1_test.dart uses, directly, to stay a read-only
// measurement against the native library.
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
    test('yuv_convert_v1 stages $name', () {
      final sourceBytes = _makeSourceBytes(sourceFormat);
      final expected = _oracleBgra(sourceFormat, sourceBytes);
      final expectedHash = _checksum([expected]);

      // Stage A: Dart input staging -- calloc the source frame/plane buffers
      // and copy the caller's bytes into them (YuvAbiV1Runner._allocateConstFrame).
      final stagingSamples = <double>[];
      // Stage B: destination allocation/zero-fill -- calloc the destination
      // frame/plane, zero-filled by calloc itself, no source seed needed for
      // a full-frame conversion (YuvAbiV1Runner._allocateMutableFrame).
      final destAllocSamples = <double>[];
      // Stage C: the native yuv_convert_v1 call alone (YuvAbiV1Runner._run
      // step 5), same pointers reused between stage measurements below.
      final kernelSamples = <double>[];
      // Stage D: copy destination plane bytes back into a Dart-owned buffer
      // (YuvAbiV1Runner._copyDestinationPlanes).
      final copyOutSamples = <double>[];
      // Stage E: full sequence A+B+C+D end to end, mirroring what
      // toBgraBytes()/toBgra() do per call (allocate, convert, copy out,
      // free), for direct comparison against the existing Flutter AOT
      // 43-44 ms full-call measurement.
      final fullCallSamples = <double>[];

      late List<int> lastResult;

      double timeStagingOnly() {
        final sw = Stopwatch()..start();
        final source = _allocateSourceFrame(sourceFormat, sourceBytes);
        sw.stop();
        _freeFrame(source.frame, source.buffers);
        return sw.elapsedTicks * 1000000 / sw.frequency;
      }

      double timeDestAllocOnly() {
        final sw = Stopwatch()..start();
        final dest = _allocateDestinationFrame();
        sw.stop();
        _freeFrame(dest.frame, dest.buffers);
        return sw.elapsedTicks * 1000000 / sw.frequency;
      }

      double timeKernelOnly(_Allocated source, _Allocated dest, Pointer<_Options> options) {
        final sw = Stopwatch()..start();
        final status = convert(source.frame, dest.frame, options);
        sw.stop();
        expect(status, 0);
        return sw.elapsedTicks * 1000000 / sw.frequency;
      }

      double timeCopyOutOnly(_Allocated dest) {
        final sw = Stopwatch()..start();
        lastResult = _copyDestinationBgra(dest.buffers.single);
        sw.stop();
        return sw.elapsedTicks * 1000000 / sw.frequency;
      }

      double timeFullCall() {
        final sw = Stopwatch()..start();
        final source = _allocateSourceFrame(sourceFormat, sourceBytes);
        final dest = _allocateDestinationFrame();
        final options = calloc<_Options>();
        options.ref
          ..structSize = sizeOf<_Options>()
          ..abiVersion = 1;
        final status = convert(source.frame, dest.frame, options);
        expect(status, 0);
        final result = _copyDestinationBgra(dest.buffers.single);
        sw.stop();
        calloc.free(options);
        _freeFrame(source.frame, source.buffers);
        _freeFrame(dest.frame, dest.buffers);
        lastResult = result;
        return sw.elapsedTicks * 1000000 / sw.frequency;
      }

      // Warm-up covers every stage and the full call so JIT/cache effects
      // land before the timed samples, matching yuv_convert_v1_test.dart.
      for (var i = 0; i < _warmup; i++) {
        timeStagingOnly();
        timeDestAllocOnly();
        final source = _allocateSourceFrame(sourceFormat, sourceBytes);
        final dest = _allocateDestinationFrame();
        final options = calloc<_Options>();
        options.ref
          ..structSize = sizeOf<_Options>()
          ..abiVersion = 1;
        timeKernelOnly(source, dest, options);
        timeCopyOutOnly(dest);
        calloc.free(options);
        _freeFrame(source.frame, source.buffers);
        _freeFrame(dest.frame, dest.buffers);
        timeFullCall();
      }

      for (var i = 0; i < _runs; i++) {
        stagingSamples.add(timeStagingOnly());
        destAllocSamples.add(timeDestAllocOnly());

        final source = _allocateSourceFrame(sourceFormat, sourceBytes);
        final dest = _allocateDestinationFrame();
        final options = calloc<_Options>();
        options.ref
          ..structSize = sizeOf<_Options>()
          ..abiVersion = 1;
        kernelSamples.add(timeKernelOnly(source, dest, options));
        copyOutSamples.add(timeCopyOutOnly(dest));
        final actualHash = _checksum([lastResult]);
        if (actualHash != expectedHash) fail('$name byte mismatch at run $i');
        calloc.free(options);
        _freeFrame(source.frame, source.buffers);
        _freeFrame(dest.frame, dest.buffers);

        fullCallSamples.add(timeFullCall());
        final fullHash = _checksum([lastResult]);
        if (fullHash != expectedHash) fail('$name full-call byte mismatch at run $i');
      }

      void report(String stage, List<double> samples) {
        final sorted = samples.toList()..sort();
        final median = sorted[sorted.length ~/ 2];
        final us = median;
        print(
          'BGRA-00 $name $stage ${_width}x$_height: median=${(us / 1000).toStringAsFixed(4)} ms '
          'min=${(sorted.first / 1000).toStringAsFixed(4)} ms max=${(sorted.last / 1000).toStringAsFixed(4)} ms '
          'n=${samples.length}',
        );
      }

      report('staging', stagingSamples);
      report('dest_alloc_zero', destAllocSamples);
      report('kernel', kernelSamples);
      report('copy_out', copyOutSamples);
      report('full_call', fullCallSamples);
      print('BGRA-00 $name checksum=0x${_hex64(expectedHash)}');
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
    final buffer = calloc<Uint8>(size);
    buffers.add(buffer);
    // Bulk typed-list copy, matching YuvAbiV1Runner._allocateConstFrame's
    // `data.asTypedList(...).setAll(0, plane.bytes)` -- a per-byte Dart loop
    // here would measure a different, slower path than the library's.
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

_Allocated _allocateDestinationFrame() {
  final frame = calloc<_Frame>();
  final size = _width * _height * 4;
  // calloc zero-fills the destination buffer; a full-frame BGRA conversion
  // overwrites every byte, so no source seed copy is needed here, matching
  // YuvAbiV1Runner._allocateMutableFrame's non-ROI path.
  final buffer = calloc<Uint8>(size);
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
  // Bulk typed-list copy, matching YuvAbiV1Runner._copyDestinationPlanes'
  // `Uint8List.fromList(plane.data.asTypedList(plane.length))`.
  return Uint8List.fromList(buffer.asTypedList(size));
}

void _freeFrame(Pointer<_Frame> frame, List<Pointer<Uint8>> buffers) {
  for (final buffer in buffers) {
    calloc.free(buffer);
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
