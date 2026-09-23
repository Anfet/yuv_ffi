@TestOn('browser')
// Drives the public Web backend against a fake Emscripten module through
// `dart:js_interop`, which the VM cannot compile; `@TestOn` excludes this file
// from a VM run rather than letting it fail to load.
library;

// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/src/loader/wasm_loader.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_abi_v1_symbols.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_native_status.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_revision.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// YUV-51 review regression (2026-09-23): `swapNv()` on a non-NV receiver is
/// atomic across both of its native calls.
///
/// `swapNv()` on I420/BGRA needs two WASM calls -- a conversion to NV12, then
/// the chroma swap. The reviewed implementation published the conversion
/// before attempting the swap, so a swap that returned a non-zero status left
/// the receiver converted: different format, different bytes, advanced
/// revision. The public contract requires all three to be unchanged.
///
/// The IO half of this is `test/io_abi_v1_public_contract_test.dart`, which
/// drives `YuvAbiV1Runner.debugInvokeOverride`. Web has no such seam, so this
/// installs a fake Emscripten module through the loader's own debug
/// initializer and returns a chosen `YuvStatus` per call. The whole staging,
/// dispatch and publish path runs for real; only the kernel's return value is
/// substituted, which is what makes this a test of the publish step rather
/// than of a mock.

JSObject get _globalThis => globalContext;

/// Installs a fake module factory whose `ccall` returns a per-call status.
void _installFactory() {
  if (_globalThis.has('__yuvMakeStatusModule')) {
    return;
  }
  const source = r'''
globalThis.__yuvMakeStatusModule = function () {
  const buffer = new ArrayBuffer(1 << 20);
  return {
    HEAPU8: new Uint8Array(buffer),
    HEAP32: new Int32Array(buffer),
    __brk: 16,
    __calls: [],
    // One status per call, consumed in order; the last entry repeats once the
    // list runs out, so a test only has to name the calls it cares about.
    __statuses: [0],
    _malloc: function (size) {
      const ptr = (this.__brk + 7) & ~7;
      this.__brk = ptr + size;
      if (this.__brk > this.HEAPU8.length) return 0;
      this.HEAPU8.fill(0, ptr, ptr + size);
      return ptr;
    },
    _free: function (ptr) {},
    ccall: function (name, returnType, argTypes, args) {
      const index = this.__calls.length;
      this.__calls.push(name);
      const statuses = this.__statuses;
      return index < statuses.length ? statuses[index] : statuses[statuses.length - 1];
    },
  };
};
''';
  final compile = _globalThis.getProperty<JSFunction>('Function'.toJS);
  compile.callAsConstructor<JSFunction>(source.toJS).callAsFunction(_globalThis);
}

/// A fake module returning [statuses] for its successive `ccall`s.
JSObject _statusModule(List<int> statuses) {
  _installFactory();
  final module = _globalThis.getProperty<JSFunction>('__yuvMakeStatusModule'.toJS).callAsFunction(_globalThis) as JSObject;
  module.setProperty('__statuses'.toJS, statuses.map((s) => s.toJS).toList().toJS);
  for (final symbol in yuvAbiV1Symbols) {
    module.setProperty('_$symbol'.toJS, true.toJS);
  }
  return module;
}

/// Installs [module] as the loaded WASM module for the public Web backend.
Future<void> _useModule(JSObject module) async {
  YuvWasmLoader.debugReset();
  YuvWasmLoader.debugSetInitializer(({required String scriptPath, required String wasmPath, required String moduleFactoryName}) async {
    return YuvModule(module);
  });
  await YuvFfi.ensureInitialized();
}

List<String> _calls(JSObject module) => [for (final c in module.getProperty<JSArray>('__calls'.toJS).toDart) (c as JSString).toDart];

YuvPlane _plane(int height, int rowStride, int pixelStride, int fill) =>
    YuvPlane(height, rowStride, pixelStride, Uint8List(height * rowStride)..fillRange(0, height * rowStride, fill));

YuvImage _imageOf(YuvFileFormat format) => switch (format) {
  YuvFileFormat.i420 => YuvImage.i420(8, 8, planes: [_plane(8, 8, 1, 0x30), _plane(4, 4, 1, 0x50), _plane(4, 4, 1, 0x70)]),
  YuvFileFormat.bgra8888 => YuvImage.bgra(8, 8, planes: [_plane(8, 32, 4, 0x30)]),
  YuvFileFormat.nv21 => YuvImage.nv21(8, 8, planes: [_plane(8, 8, 1, 0x30), _plane(4, 8, 2, 0x50)]),
};

void main() {
  tearDown(YuvWasmLoader.debugReset);

  test('runs on a real browser runtime', () {
    expect(kIsWeb, isTrue);
  });

  for (final format in [YuvFileFormat.i420, YuvFileFormat.bgra8888]) {
    test('a failing chroma swap after a successful conversion leaves a ${format.name} receiver untouched', () async {
      // Call 1 is yuv_convert_v1 and succeeds; call 2 is yuv_chroma_swap_v1
      // and fails. This is the exact sequence the review reproduced.
      final module = _statusModule([yuvStatusOk, yuvStatusInternalError]);
      await _useModule(module);

      final image = _imageOf(format);
      final bytesBefore = image.getBytes();
      final revisionBefore = (image as YuvRevisionAware).internalRevision;

      expect(() => image.swapNv(), throwsA(isA<YuvNativeException>().having((e) => e.operation, 'operation', YuvOperation.chromaSwap)));

      expect(_calls(module), [yuvSymbolConvertV1, yuvSymbolChromaSwapV1], reason: 'the conversion must have succeeded before the swap was attempted');
      expect(image.format, format, reason: 'format changed although swapNv failed');
      expect(image.getBytes(), bytesBefore, reason: 'bytes changed although swapNv failed');
      expect(image.width, 8);
      expect(image.height, 8);
      expect((image as YuvRevisionAware).internalRevision, revisionBefore, reason: 'revision advanced although swapNv failed');
    });

    test('a failing conversion leaves a ${format.name} receiver untouched', () async {
      final module = _statusModule([yuvStatusInternalError]);
      await _useModule(module);

      final image = _imageOf(format);
      final bytesBefore = image.getBytes();
      final revisionBefore = (image as YuvRevisionAware).internalRevision;

      expect(() => image.swapNv(), throwsA(isA<YuvNativeException>()));

      expect(_calls(module), [yuvSymbolConvertV1]);
      expect(image.format, format);
      expect(image.getBytes(), bytesBefore);
      expect((image as YuvRevisionAware).internalRevision, revisionBefore);
    });
  }

  test('a failing chroma swap leaves an already-NV21 receiver untouched', () async {
    // The one-call form: no conversion happens, so the only thing that could
    // publish early is the swap itself.
    final module = _statusModule([yuvStatusInternalError]);
    await _useModule(module);

    final image = _imageOf(YuvFileFormat.nv21);
    final bytesBefore = image.getBytes();
    final revisionBefore = (image as YuvRevisionAware).internalRevision;

    expect(() => image.swapNv(), throwsA(isA<YuvNativeException>()));

    expect(_calls(module), [yuvSymbolChromaSwapV1], reason: 'an NV21 receiver needs no conversion');
    expect(image.format, YuvPixelFormat.nv12);
    expect(image.getBytes(), bytesBefore);
    expect((image as YuvRevisionAware).internalRevision, revisionBefore);
  });

  test('both calls succeeding publishes once, as NV21, advancing the revision by one', () async {
    // The positive half of the same path, so the fix cannot be "never
    // publish": two native calls must still be exactly one publish.
    final module = _statusModule([yuvStatusOk, yuvStatusOk]);
    await _useModule(module);

    final image = _imageOf(YuvFileFormat.i420);
    final revisionBefore = (image as YuvRevisionAware).internalRevision;

    image.swapNv();

    expect(_calls(module), [yuvSymbolConvertV1, yuvSymbolChromaSwapV1]);
    expect(image.format, YuvPixelFormat.nv12);
    expect((image as YuvRevisionAware).internalRevision, revisionBefore + 1, reason: 'two native calls must still be one publish');
  });
}
