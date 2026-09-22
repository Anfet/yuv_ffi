@TestOn('browser')
// The runner reaches the WASM module through `dart:js_interop`, which the VM
// cannot compile at all -- unlike the other `test/web` suites, which import
// only platform-agnostic code and guard on `kIsWeb` at runtime. `@TestOn`
// excludes this file from a VM run rather than letting it fail to load.
library;

// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/src/yuv/impl/web/abi/yuv_abi_v1_wasm_layout.dart';
import 'package:yuv_ffi/src/yuv/impl/web/abi/yuv_abi_v1_web_runner.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_abi_v1_constants.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_abi_v1_frame.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_abi_v1_symbols.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_native_status.dart';

/// YUV-51: what the Web runner actually writes into WASM linear memory.
///
/// `wasm_abi_v1_layout_test.dart` proves the offset constants match the C
/// header. This proves the runner uses them correctly: it runs against a fake
/// Emscripten module whose heap is an ordinary `ArrayBuffer`, so every
/// descriptor byte the runner stages can be read back and checked field by
/// field -- including the fields nothing would notice being wrong until a
/// browser silently misread them (`sampleBytes`, the disabled region's zeroed
/// coordinates, unused plane slots, the reserved tails).
///
/// The fake also makes the failure paths testable, which a real module cannot:
/// it can return any `YuvStatus`, so the "non-zero status publishes nothing"
/// half of the contract is exercised for real rather than argued from code
/// shape. Correctness of the *kernels* is not in scope here -- that is the
/// reference matrix in `example/integration_test/reference_web_conversions_test.dart`,
/// which runs the real WASM build in Chrome.
///
/// These run in a browser (`flutter test --platform chrome`) because the runner
/// reaches the module through `dart:js_interop`; they need no WASM asset, only
/// a JS object shaped like an Emscripten module.

/// A JS object standing in for an Emscripten module: a heap, a bump allocator,
/// `ccall`, and every ABI v1 export name so the dispatch's completeness check
/// passes.
///
/// `globalContext` rather than an `@JS() external` getter: the latter resolves
/// against the library's JS namespace, which is not the page's global object
/// under DDC, so `eval` is not found there.
JSObject get _globalThis => globalContext;

/// Installs the fake module factory into the page once.
void _installFakeModuleFactory() {
  // Written as JS source rather than assembled through js_interop wrappers so
  // the heap views (`HEAPU8`/`HEAP32`) are the real Emscripten shape -- typed
  // array views over one growable buffer -- rather than Dart objects that only
  // resemble them.
  const source = r'''
globalThis.__yuvMakeFakeModule = function (heapBytes) {
  const buffer = new ArrayBuffer(heapBytes);
  const module = {
    HEAPU8: new Uint8Array(buffer),
    HEAP32: new Int32Array(buffer),
    // Offset 0 is left unused so a real pointer is never 0, which the arena
    // treats as an allocation failure.
    __brk: 16,
    __live: 0,
    __calls: [],
    __status: 0,
    __onCall: null,
    _malloc: function (size) {
      // 8-byte aligned, like Emscripten's allocator: the ABI structs carry
      // uint64 and double members.
      const ptr = (this.__brk + 7) & ~7;
      this.__brk = ptr + size;
      if (this.__brk > this.HEAPU8.length) return 0;
      this.__live++;
      // Deliberately poisoned, so any field the runner fails to write shows up
      // as 0xA5 rather than accidentally-correct zero.
      this.HEAPU8.fill(0xA5, ptr, ptr + size);
      return ptr;
    },
    _free: function (ptr) {
      this.__live--;
    },
    ccall: function (name, returnType, argTypes, args) {
      this.__calls.push({ name: name, args: args.slice() });
      if (this.__onCall) this.__onCall(this, name, args);
      return this.__status;
    },
  };
  return module;
};
''';
  if (_globalThis.has('__yuvMakeFakeModule')) {
    return;
  }
  // `new Function(src)()` rather than `globalThis.eval(src)`: `eval` is not a
  // property of the global object DDC hands out, while `Function` is.
  final compile = _globalThis.getProperty<JSFunction>('Function'.toJS);
  final factory = compile.callAsConstructor<JSFunction>(source.toJS);
  factory.callAsFunction(_globalThis);
}

JSObject _newFakeModule({int heapBytes = 1 << 20}) {
  _installFakeModuleFactory();
  final factory = _globalThis.getProperty<JSFunction>('__yuvMakeFakeModule'.toJS);
  final module = factory.callAsFunction(_globalThis, heapBytes.toJS) as JSObject;
  // The completeness gate asks the module for each exported `_yuv_*_v1` name.
  for (final symbol in yuvAbiV1Symbols) {
    module.setProperty('_$symbol'.toJS, true.toJS);
  }
  return module;
}

extension on JSObject {
  ByteData get heap {
    final view = getProperty<JSUint8Array>('HEAPU8'.toJS).toDart;
    return ByteData.view(view.buffer, view.offsetInBytes, view.lengthInBytes);
  }

  Uint8List get heapBytes => getProperty<JSUint8Array>('HEAPU8'.toJS).toDart;

  int get liveAllocations => getProperty<JSNumber>('__live'.toJS).toDartInt;

  set status(int value) => setProperty('__status'.toJS, value.toJS);

  List<_RecordedCall> get calls {
    final raw = getProperty<JSArray>('__calls'.toJS).toDart;
    return [
      for (final entry in raw)
        _RecordedCall((entry as JSObject).getProperty<JSString>('name'.toJS).toDart, [
          for (final a in (entry.getProperty<JSArray>('args'.toJS)).toDart) (a as JSNumber).toDartInt,
        ]),
    ];
  }
}

class _RecordedCall {
  _RecordedCall(this.name, this.args);

  final String name;
  final List<int> args;

  int get sourceFrame => args[0];

  int get destinationFrame => args[1];

  int get options => args[2];
}

/// Reads a plane descriptor out of the staged frame at [framePtr].
({int length, int rowStride, int pixelStride, int sampleBytes, int data}) _readPlane(JSObject module, int framePtr, int index) {
  final heap = module.heap;
  final base = framePtr + YuvWasmFrameV1.offsetOfPlane(index);
  return (
    // Only the low half is read back: every length and stride here is far
    // below 2^32, and the high half is asserted to be zero separately.
    length: heap.getUint32(base + YuvWasmPlaneV1.offsetLength, Endian.little),
    rowStride: heap.getUint32(base + YuvWasmPlaneV1.offsetRowStride, Endian.little),
    pixelStride: heap.getUint32(base + YuvWasmPlaneV1.offsetPixelStride, Endian.little),
    sampleBytes: heap.getUint32(base + YuvWasmPlaneV1.offsetSampleBytes, Endian.little),
    data: heap.getUint32(base + YuvWasmPlaneV1.offsetData, Endian.little),
  );
}

/// An I420 source with distinct, recognizable bytes in each plane.
YuvAbiV1FrameInput _i420Source({int width = 4, int height = 4, int yRowStride = 4, int uvRowStride = 2}) {
  return YuvAbiV1FrameInput(
    format: yuvFormatI420,
    width: width,
    height: height,
    planes: [
      YuvAbiV1PlaneInput(bytes: Uint8List.fromList(List.generate(yRowStride * height, (i) => 10 + i)), rowStride: yRowStride, pixelStride: 1),
      YuvAbiV1PlaneInput(
        bytes: Uint8List.fromList(List.generate(uvRowStride * (height ~/ 2), (i) => 100 + i)),
        rowStride: uvRowStride,
        pixelStride: 1,
      ),
      YuvAbiV1PlaneInput(
        bytes: Uint8List.fromList(List.generate(uvRowStride * (height ~/ 2), (i) => 200 + i)),
        rowStride: uvRowStride,
        pixelStride: 1,
      ),
    ],
  );
}

void main() {
  test('runs on a real browser runtime', () {
    // @TestOn('browser') already excludes a VM run, so this asserts the
    // annotation is doing its job rather than the suite silently passing
    // somewhere the staging under test cannot even execute.
    expect(kIsWeb, isTrue);
  });

  group('source frame staging', () {
    test('every scalar field carries the value ABI v1 requires', () {
      final module = _newFakeModule();
      YuvAbiV1WebRunner.grayscale(module: module, source: _i420Source());

      final call = module.calls.single;
      expect(call.name, yuvSymbolGrayscaleV1);

      final heap = module.heap;
      final src = call.sourceFrame;
      expect(heap.getUint32(src + YuvWasmFrameV1.offsetStructSize, Endian.little), 160);
      expect(heap.getUint32(src + YuvWasmFrameV1.offsetAbiVersion, Endian.little), yuvAbiVersion1);
      expect(heap.getUint32(src + YuvWasmFrameV1.offsetFormat, Endian.little), yuvFormatI420);
      expect(heap.getUint32(src + YuvWasmFrameV1.offsetPlaneCount, Endian.little), 3);
      expect(heap.getUint32(src + YuvWasmFrameV1.offsetWidth, Endian.little), 4);
      expect(heap.getUint32(src + YuvWasmFrameV1.offsetHeight, Endian.little), 4);
      // Derived from the format, never accepted from a caller, so an
      // UNSUPPORTED_COLOR can only come from a genuine ABI disagreement.
      expect(heap.getUint32(src + YuvWasmFrameV1.offsetColorMatrix, Endian.little), yuvColorMatrixBt601);
      expect(heap.getUint32(src + YuvWasmFrameV1.offsetColorRange, Endian.little), yuvColorRangeLimited);
    });

    test('plane descriptors carry real lengths, both strides and the format sampleBytes', () {
      final module = _newFakeModule();
      // A padded Y plane: rowStride 6 for a 4-pixel-wide frame.
      final source = _i420Source(yRowStride: 6, uvRowStride: 3);
      YuvAbiV1WebRunner.grayscale(module: module, source: source);

      final src = module.calls.single.sourceFrame;

      final y = _readPlane(module, src, 0);
      expect(y.length, 6 * 4, reason: 'length must be the real buffer length, padding included');
      expect(y.rowStride, 6, reason: 'a padded source keeps its own row stride');
      expect(y.pixelStride, 1);
      expect(y.sampleBytes, 1);
      expect(y.data, isNonZero);

      final u = _readPlane(module, src, 1);
      expect(u.length, 3 * 2);
      expect(u.rowStride, 3);
      expect(u.sampleBytes, 1);
      expect(u.data, isNonZero);

      final v = _readPlane(module, src, 2);
      expect(v.data, isNonZero);
      expect(v.data, isNot(u.data), reason: 'each plane must get its own buffer');
    });

    test('NV12 stages two planes, with sampleBytes 2 on the interleaved chroma plane', () {
      final module = _newFakeModule();
      final source = YuvAbiV1FrameInput(
        format: yuvFormatNv12,
        width: 4,
        height: 4,
        planes: [
          YuvAbiV1PlaneInput(bytes: Uint8List(16), rowStride: 4, pixelStride: 1),
          YuvAbiV1PlaneInput(bytes: Uint8List(8), rowStride: 4, pixelStride: 2),
        ],
      );
      YuvAbiV1WebRunner.grayscale(module: module, source: source);

      final src = module.calls.single.sourceFrame;
      expect(module.heap.getUint32(src + YuvWasmFrameV1.offsetPlaneCount, Endian.little), 2);
      expect(_readPlane(module, src, 0).sampleBytes, 1);
      expect(_readPlane(module, src, 1).sampleBytes, 2, reason: 'NV12 chroma is an interleaved (U, V) pair per sample');
      expect(_readPlane(module, src, 1).pixelStride, 2);
    });

    test('the unused third plane slot is a zero-filled descriptor with null data', () {
      // Section 9's explicit rule. The fake allocator poisons fresh memory with
      // 0xA5, so a slot the runner never zeroed would be caught here rather
      // than passing by luck on a zeroed heap.
      final module = _newFakeModule();
      final source = YuvAbiV1FrameInput(
        format: yuvFormatBgra8888,
        width: 2,
        height: 2,
        planes: [YuvAbiV1PlaneInput(bytes: Uint8List(16), rowStride: 8, pixelStride: 4)],
      );
      YuvAbiV1WebRunner.grayscale(module: module, source: source);

      final src = module.calls.single.sourceFrame;
      expect(_readPlane(module, src, 0).sampleBytes, 4);

      for (final unused in [1, 2]) {
        final base = src + YuvWasmFrameV1.offsetOfPlane(unused);
        expect(
          module.heapBytes.sublist(base, base + YuvWasmPlaneV1.sizeBytes),
          everyElement(0),
          reason: 'plane slot $unused must be entirely zeroed',
        );
      }
    });

    test('the reserved tail is zeroed rather than left as allocator garbage', () {
      // A non-zero reserved field is INVALID_ARGUMENT under section 9, so this
      // is the difference between working and a rejected descriptor.
      final module = _newFakeModule();
      YuvAbiV1WebRunner.grayscale(module: module, source: _i420Source());

      final call = module.calls.single;
      for (final frame in [call.sourceFrame, call.destinationFrame]) {
        final base = frame + YuvWasmFrameV1.offsetReserved;
        expect(module.heapBytes.sublist(base, base + 32), everyElement(0));
      }
    });

    test('plane bytes reach the heap exactly as given, padding included', () {
      final module = _newFakeModule();
      final source = _i420Source(yRowStride: 6, uvRowStride: 3);
      YuvAbiV1WebRunner.grayscale(module: module, source: source);

      final y = _readPlane(module, module.calls.single.sourceFrame, 0);
      expect(module.heapBytes.sublist(y.data, y.data + y.length), source.planes[0].bytes);
    });

    test('a uint64 length writes a zero high half', () {
      // wasm32 is little-endian; a stray high half would make `length` absurd.
      final module = _newFakeModule();
      YuvAbiV1WebRunner.grayscale(module: module, source: _i420Source());

      final src = module.calls.single.sourceFrame;
      final base = src + YuvWasmFrameV1.offsetOfPlane(0);
      expect(module.heap.getUint32(base + YuvWasmPlaneV1.offsetLength + 4, Endian.little), 0);
      expect(module.heap.getUint32(base + YuvWasmPlaneV1.offsetRowStride + 4, Endian.little), 0);
    });
  });

  group('destination frame staging', () {
    test('the destination is tight regardless of a padded source', () {
      final module = _newFakeModule();
      YuvAbiV1WebRunner.grayscale(module: module, source: _i420Source(yRowStride: 6, uvRowStride: 3));

      final dst = module.calls.single.destinationFrame;
      final y = _readPlane(module, dst, 0);
      expect(y.rowStride, 4, reason: 'the destination the runner allocates is always tight');
      expect(y.length, 16);
      expect(_readPlane(module, dst, 1).rowStride, 2);
    });

    test('rotate by 90 transposes the destination geometry', () {
      final module = _newFakeModule();
      YuvAbiV1WebRunner.rotate(module: module, source: _i420Source(width: 4, height: 8, yRowStride: 4, uvRowStride: 2), rotationDegrees: 90);

      final dst = module.calls.single.destinationFrame;
      expect(module.heap.getUint32(dst + YuvWasmFrameV1.offsetWidth, Endian.little), 8);
      expect(module.heap.getUint32(dst + YuvWasmFrameV1.offsetHeight, Endian.little), 4);
      expect(_readPlane(module, dst, 0).rowStride, 8);
    });

    test('rotate by 180 keeps the source geometry', () {
      final module = _newFakeModule();
      YuvAbiV1WebRunner.rotate(module: module, source: _i420Source(width: 4, height: 8, yRowStride: 4, uvRowStride: 2), rotationDegrees: 180);

      final dst = module.calls.single.destinationFrame;
      expect(module.heap.getUint32(dst + YuvWasmFrameV1.offsetWidth, Endian.little), 4);
      expect(module.heap.getUint32(dst + YuvWasmFrameV1.offsetHeight, Endian.little), 8);
    });

    test('odd 4:2:0 geometry rounds chroma extents up', () {
      // ceil(5/2) == 3: a truncating division would under-allocate chroma and
      // the kernel would write past the buffer.
      final module = _newFakeModule();
      final source = YuvAbiV1FrameInput(
        format: yuvFormatI420,
        width: 5,
        height: 5,
        planes: [
          YuvAbiV1PlaneInput(bytes: Uint8List(25), rowStride: 5, pixelStride: 1),
          YuvAbiV1PlaneInput(bytes: Uint8List(9), rowStride: 3, pixelStride: 1),
          YuvAbiV1PlaneInput(bytes: Uint8List(9), rowStride: 3, pixelStride: 1),
        ],
      );
      YuvAbiV1WebRunner.grayscale(module: module, source: source);

      final dst = module.calls.single.destinationFrame;
      final u = _readPlane(module, dst, 1);
      expect(u.rowStride, 3);
      expect(u.length, 9, reason: 'chroma is ceil(5/2) x ceil(5/2)');
    });

    test('a non-ROI destination starts zeroed, not as allocator garbage', () {
      final module = _newFakeModule();
      YuvAbiV1WebRunner.grayscale(module: module, source: _i420Source());

      final dst = module.calls.single.destinationFrame;
      final y = _readPlane(module, dst, 0);
      expect(module.heapBytes.sublist(y.data, y.data + y.length), everyElement(0));
    });

    test('an ROI destination is seeded with the source samples so bytes outside it survive', () {
      final module = _newFakeModule();
      final source = _i420Source();
      YuvAbiV1WebRunner.blackWhite(module: module, source: source, region: const YuvAbiV1Region(left: 0, top: 0, right: 2, bottom: 2));

      final dst = module.calls.single.destinationFrame;
      final y = _readPlane(module, dst, 0);
      expect(
        module.heapBytes.sublist(y.data, y.data + y.length),
        source.planes[0].bytes,
        reason: 'the whole destination starts as a copy of the source, so a kernel writing only inside the ROI leaves the rest correct',
      );
    });

    test('seeding walks a padded source through its own strides', () {
      final module = _newFakeModule();
      // rowStride 6 over a 4-wide frame: bytes 4 and 5 of each row are padding
      // and must not appear in the tight destination.
      final source = _i420Source(yRowStride: 6, uvRowStride: 3);
      YuvAbiV1WebRunner.blackWhite(module: module, source: source, region: const YuvAbiV1Region(left: 0, top: 0, right: 2, bottom: 2));

      final dst = module.calls.single.destinationFrame;
      final y = _readPlane(module, dst, 0);
      final staged = module.heapBytes.sublist(y.data, y.data + y.length);

      final expected = <int>[];
      for (int row = 0; row < 4; row++) {
        for (int col = 0; col < 4; col++) {
          expected.add(source.planes[0].bytes[row * 6 + col]);
        }
      }
      expect(staged, expected, reason: 'padding bytes must be stepped over, not copied through');
    });
  });

  group('options staging', () {
    test('effect options carry a disabled region with every coordinate zeroed', () {
      final module = _newFakeModule();
      YuvAbiV1WebRunner.grayscale(module: module, source: _i420Source());

      final heap = module.heap;
      final options = module.calls.single.options;
      expect(heap.getUint32(options + YuvWasmEffectOptionsV1.offsetStructSize, Endian.little), 56);
      expect(heap.getUint32(options + YuvWasmEffectOptionsV1.offsetAbiVersion, Endian.little), yuvAbiVersion1);

      final region = options + YuvWasmEffectOptionsV1.offsetRegion;
      expect(heap.getUint32(region + YuvWasmRegionOptionsV1.offsetStructSize, Endian.little), 32);
      expect(heap.getUint32(region + YuvWasmRegionOptionsV1.offsetEnabled, Endian.little), 0);
      // Section 10: "when 0, all four coordinates and reserved0 must be zero".
      for (final offset in [
        YuvWasmRegionOptionsV1.offsetLeft,
        YuvWasmRegionOptionsV1.offsetTop,
        YuvWasmRegionOptionsV1.offsetRight,
        YuvWasmRegionOptionsV1.offsetBottom,
        YuvWasmRegionOptionsV1.offsetReserved0,
      ]) {
        expect(heap.getUint32(region + offset, Endian.little), 0);
      }
      expect(module.heapBytes.sublist(options + YuvWasmEffectOptionsV1.offsetReserved, options + YuvWasmEffectOptionsV1.sizeBytes), everyElement(0));
    });

    test('an enabled region carries its four coordinates', () {
      final module = _newFakeModule();
      YuvAbiV1WebRunner.negate(module: module, source: _i420Source(), region: const YuvAbiV1Region(left: 1, top: 2, right: 3, bottom: 4));

      final region = module.calls.single.options + YuvWasmEffectOptionsV1.offsetRegion;
      final heap = module.heap;
      expect(heap.getUint32(region + YuvWasmRegionOptionsV1.offsetEnabled, Endian.little), 1);
      expect(heap.getInt32(region + YuvWasmRegionOptionsV1.offsetLeft, Endian.little), 1);
      expect(heap.getInt32(region + YuvWasmRegionOptionsV1.offsetTop, Endian.little), 2);
      expect(heap.getInt32(region + YuvWasmRegionOptionsV1.offsetRight, Endian.little), 3);
      expect(heap.getInt32(region + YuvWasmRegionOptionsV1.offsetBottom, Endian.little), 4);
    });

    test('blur options carry radius, clamp border and an IEEE-754 sigma', () {
      final module = _newFakeModule();
      YuvAbiV1WebRunner.blur(module: module, kind: YuvAbiV1BlurKind.gaussian, source: _i420Source(), radius: 3, sigma: 2.5);

      final heap = module.heap;
      final options = module.calls.single.options;
      expect(heap.getUint32(options + YuvWasmBlurOptionsV1.offsetStructSize, Endian.little), 72);
      expect(heap.getUint32(options + YuvWasmBlurOptionsV1.offsetRadius, Endian.little), 3);
      expect(heap.getUint32(options + YuvWasmBlurOptionsV1.offsetBorderMode, Endian.little), yuvBorderClamp);
      expect(heap.getFloat64(options + YuvWasmBlurOptionsV1.offsetSigma, Endian.little), 2.5);
    });

    test('the uniform-weight blurs carry sigma 0, as section 10 requires', () {
      for (final kind in [YuvAbiV1BlurKind.mean, YuvAbiV1BlurKind.box]) {
        final module = _newFakeModule();
        YuvAbiV1WebRunner.blur(module: module, kind: kind, source: _i420Source(), radius: 2);
        expect(module.heap.getFloat64(module.calls.single.options + YuvWasmBlurOptionsV1.offsetSigma, Endian.little), 0.0, reason: '$kind');
      }
    });

    test('crop options carry the rectangle', () {
      final module = _newFakeModule();
      YuvAbiV1WebRunner.crop(
        module: module,
        source: _i420Source(width: 8, height: 8, yRowStride: 8, uvRowStride: 4),
        left: 2,
        top: 2,
        width: 4,
        height: 4,
      );

      final heap = module.heap;
      final options = module.calls.single.options;
      expect(heap.getUint32(options + YuvWasmCropOptionsV1.offsetStructSize, Endian.little), 32);
      expect(heap.getInt32(options + YuvWasmCropOptionsV1.offsetLeft, Endian.little), 2);
      expect(heap.getInt32(options + YuvWasmCropOptionsV1.offsetTop, Endian.little), 2);
      expect(heap.getUint32(options + YuvWasmCropOptionsV1.offsetWidth, Endian.little), 4);
      expect(heap.getUint32(options + YuvWasmCropOptionsV1.offsetHeight, Endian.little), 4);
    });

    test('flip and rotate options carry their one field and a zeroed reserved tail', () {
      final flipModule = _newFakeModule();
      YuvAbiV1WebRunner.flip(module: flipModule, source: _i420Source(), direction: yuvFlipVertical);
      final flipOptions = flipModule.calls.single.options;
      expect(flipModule.heap.getUint32(flipOptions + YuvWasmFlipOptionsV1.offsetDirection, Endian.little), yuvFlipVertical);
      expect(
        flipModule.heapBytes.sublist(flipOptions + YuvWasmFlipOptionsV1.offsetReserved0, flipOptions + YuvWasmFlipOptionsV1.sizeBytes),
        everyElement(0),
      );

      final rotateModule = _newFakeModule();
      YuvAbiV1WebRunner.rotate(module: rotateModule, source: _i420Source(), rotationDegrees: 270);
      final rotateOptions = rotateModule.calls.single.options;
      expect(rotateModule.heap.getUint32(rotateOptions + YuvWasmRotateOptionsV1.offsetRotationDegrees, Endian.little), 270);
      expect(
        rotateModule.heapBytes.sublist(rotateOptions + YuvWasmRotateOptionsV1.offsetReserved0, rotateOptions + YuvWasmRotateOptionsV1.sizeBytes),
        everyElement(0),
      );
    });

    test('convert options are the bare versioned header', () {
      final module = _newFakeModule();
      YuvAbiV1WebRunner.convert(
        module: module,
        source: _i420Source(),
        destinationLayout: const YuvAbiV1DestinationLayout(
          format: yuvFormatBgra8888,
          width: 4,
          height: 4,
          planeRowStrides: [16],
          planePixelStrides: [4],
        ),
      );

      final options = module.calls.single.options;
      expect(module.heap.getUint32(options + YuvWasmConvertOptionsV1.offsetStructSize, Endian.little), 32);
      expect(module.heap.getUint32(options + YuvWasmConvertOptionsV1.offsetAbiVersion, Endian.little), yuvAbiVersion1);
      expect(
        module.heapBytes.sublist(options + YuvWasmConvertOptionsV1.offsetReserved, options + YuvWasmConvertOptionsV1.sizeBytes),
        everyElement(0),
      );
    });
  });

  group('dispatch and symbols', () {
    test('every public operation invokes exactly one v1 symbol, and the expected one', () {
      final cases = <String, void Function(JSObject)>{
        yuvSymbolConvertV1: (m) => YuvAbiV1WebRunner.convert(
          module: m,
          source: _i420Source(),
          destinationLayout: const YuvAbiV1DestinationLayout(
            format: yuvFormatBgra8888,
            width: 4,
            height: 4,
            planeRowStrides: [16],
            planePixelStrides: [4],
          ),
        ),
        yuvSymbolBlackWhiteV1: (m) => YuvAbiV1WebRunner.blackWhite(module: m, source: _i420Source()),
        yuvSymbolGrayscaleV1: (m) => YuvAbiV1WebRunner.grayscale(module: m, source: _i420Source()),
        yuvSymbolNegateV1: (m) => YuvAbiV1WebRunner.negate(module: m, source: _i420Source()),
        yuvSymbolChromaSwapV1: (m) => YuvAbiV1WebRunner.chromaSwap(module: m, source: _i420Source()),
        yuvSymbolGaussianBlurV1: (m) =>
            YuvAbiV1WebRunner.blur(module: m, kind: YuvAbiV1BlurKind.gaussian, source: _i420Source(), radius: 1, sigma: 1),
        yuvSymbolMeanBlurV1: (m) => YuvAbiV1WebRunner.blur(module: m, kind: YuvAbiV1BlurKind.mean, source: _i420Source(), radius: 1),
        yuvSymbolBoxBlurV1: (m) => YuvAbiV1WebRunner.blur(module: m, kind: YuvAbiV1BlurKind.box, source: _i420Source(), radius: 1),
        yuvSymbolCropV1: (m) => YuvAbiV1WebRunner.crop(module: m, source: _i420Source(), left: 0, top: 0, width: 2, height: 2),
        yuvSymbolFlipV1: (m) => YuvAbiV1WebRunner.flip(module: m, source: _i420Source(), direction: yuvFlipHorizontal),
        yuvSymbolRotateV1: (m) => YuvAbiV1WebRunner.rotate(module: m, source: _i420Source(), rotationDegrees: 90),
      };

      // Every one of the eleven, so a symbol the Web runner never reaches would
      // show up as a missing case rather than as an untested path.
      expect(cases.keys.toSet(), yuvAbiV1Symbols.toSet());

      for (final entry in cases.entries) {
        final module = _newFakeModule();
        entry.value(module);
        expect(module.calls.map((c) => c.name), [entry.key], reason: '${entry.key} must be the only symbol invoked');
      }
    });

    test('a module missing a v1 symbol is rejected by name before anything is staged', () {
      final module = _newFakeModule();
      module.delete('_yuv_grayscale_v1'.toJS);

      expect(
        () => YuvAbiV1WebRunner.grayscale(module: module, source: _i420Source()),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('yuv_grayscale_v1'))),
      );
      expect(module.calls, isEmpty);
      expect(module.liveAllocations, 0, reason: 'nothing may be allocated before the module is known to be complete');
    });
  });

  group('status mapping and memory', () {
    test('a successful call copies the destination back and frees everything', () {
      final module = _newFakeModule();
      final result = YuvAbiV1WebRunner.grayscale(module: module, source: _i420Source());

      expect(result.planes, hasLength(3));
      expect(result.planes[0], hasLength(16));
      expect(result.planes[1], hasLength(4));
      expect(module.liveAllocations, 0, reason: 'every WASM allocation must be released on the success path');
    });

    test('each status maps to the documented Dart exception and frees everything', () {
      final expectations = <int, Matcher>{
        yuvStatusInvalidArgument: isA<ArgumentError>(),
        yuvStatusUnsupportedFormat: isA<UnsupportedError>(),
        yuvStatusUnsupportedLayout: isA<UnsupportedError>(),
        yuvStatusUnsupportedColor: isA<UnsupportedError>(),
        yuvStatusOverflow: isA<YuvNativeException>(),
        yuvStatusAllocationFailed: isA<YuvNativeException>(),
        yuvStatusInternalError: isA<YuvNativeException>(),
        // Outside the ABI v1 range: preserved, not collapsed.
        99: isA<YuvNativeException>().having((e) => e.statusCode, 'statusCode', 99),
      };

      for (final entry in expectations.entries) {
        final module = _newFakeModule();
        module.status = entry.key;
        expect(
          () => YuvAbiV1WebRunner.grayscale(module: module, source: _i420Source()),
          throwsA(entry.value),
          reason: 'status ${entry.key}',
        );
        expect(module.liveAllocations, 0, reason: 'status ${entry.key} must still release every allocation');
      }
    });

    test('the thrown exception names the symbol that failed', () {
      final module = _newFakeModule();
      module.status = yuvStatusInternalError;
      expect(
        () => YuvAbiV1WebRunner.rotate(module: module, source: _i420Source(), rotationDegrees: 90),
        throwsA(isA<YuvNativeException>().having((e) => e.operation, 'operation', yuvSymbolRotateV1)),
      );
    });

    test('a wrong plane count is rejected before any allocation', () {
      final module = _newFakeModule();
      final source = YuvAbiV1FrameInput(
        format: yuvFormatI420,
        width: 4,
        height: 4,
        // I420 requires three.
        planes: [YuvAbiV1PlaneInput(bytes: Uint8List(16), rowStride: 4, pixelStride: 1)],
      );

      expect(() => YuvAbiV1WebRunner.grayscale(module: module, source: source), throwsA(isA<ArgumentError>()));
      expect(module.calls, isEmpty);
      expect(module.liveAllocations, 0);
    });

    test('an allocation failure releases what was already allocated', () {
      // A heap far too small for the staging this operation needs, so `_malloc`
      // returns 0 partway through and the arena has live pointers to release.
      final module = _newFakeModule(heapBytes: 256);
      expect(() => YuvAbiV1WebRunner.grayscale(module: module, source: _i420Source()), throwsA(isA<StateError>()));
      expect(module.liveAllocations, 0, reason: 'a throw partway through staging must not leak WASM memory');
    });
  });
}
