// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_ffi/src/loader/wasm_loader.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_abi_v1_symbols.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_native_status.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_revision.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// A failing chroma swap leaves an NV12 receiver untouched.
///
/// Web has no native-status seam, so this installs a fake Emscripten module
/// through the loader's debug initializer. The staging, dispatch and publish
/// path runs for real; only the kernel status is substituted.

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
  // ignore: deprecated_member_use_from_same_package
  await YuvFfi.initialize();
}

List<String> _calls(JSObject module) => [for (final c in module.getProperty<JSArray>('__calls'.toJS).toDart) (c as JSString).toDart];

YuvPlane _plane(int height, int rowStride, int pixelStride, int fill) =>
    YuvPlane(height, rowStride, pixelStride, Uint8List(height * rowStride)..fillRange(0, height * rowStride, fill));

YuvImage _nv12Image() => YuvImage.nv12(8, 8, planes: [_plane(8, 8, 1, 0x30), _plane(4, 8, 2, 0x50)]);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  tearDown(YuvWasmLoader.debugReset);

  testWidgets('runs on a real browser runtime', (_) async {
    expect(kIsWeb, isTrue);
  });

  testWidgets('a failing chroma swap leaves an NV12 receiver untouched', (_) async {
    final module = _statusModule([yuvStatusInternalError]);
    await _useModule(module);

    final image = _nv12Image();
    final bytesBefore = image.toBytes();
    final revisionBefore = (image as YuvRevisionAware).internalRevision;

    expect(() => image.applyChromaSwap(), throwsA(isA<YuvNativeException>()));

    expect(_calls(module), [yuvSymbolChromaSwapV1]);
    expect(image.format, YuvPixelFormat.nv12);
    expect(image.toBytes(), bytesBefore);
    expect((image as YuvRevisionAware).internalRevision, revisionBefore);
  });

  testWidgets('a successful chroma swap advances the revision once', (_) async {
    final module = _statusModule([yuvStatusOk]);
    await _useModule(module);

    final image = _nv12Image();
    final revisionBefore = (image as YuvRevisionAware).internalRevision;

    image.applyChromaSwap();

    expect(_calls(module), [yuvSymbolChromaSwapV1]);
    expect(image.format, YuvPixelFormat.nv12);
    expect((image as YuvRevisionAware).internalRevision, revisionBefore + 1);
  });
}
