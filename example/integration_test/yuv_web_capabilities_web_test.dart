// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_ffi/src/loader/wasm_loader.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_abi_v1_symbols.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_revision.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

// Forward real calls and fresh heap views: memory growth must remain visible.
// Only the named export/primitive is removed; production assets stay complete.
JSObject _forwardingModule(JSObject real, {String omitted = ''}) {
  const source = r'''
return function(real, omitted) {
  const live = new Set();
  const facade = {
    get HEAPU8() { return real.HEAPU8; },
    __allocations: 0,
    __calls: 0,
    __status: 0,
    get __live() { return live.size; },
    _malloc(size) {
      const ptr = real._malloc(size);
      if (ptr) { live.add(ptr); facade.__allocations++; }
      return ptr;
    },
    _free(ptr) { live.delete(ptr); real._free(ptr); },
    ccall(...args) {
      facade.__calls++;
      return facade.__status || real.ccall(...args);
    },
  };
  for (const key of Object.keys(real)) {
    if (key.startsWith('_yuv_')) facade[key] = real[key];
  }
  delete facade[omitted];
  return facade;
};
''';
  final compile = globalContext.getProperty<JSFunction>('Function'.toJS);
  final factory = compile.callAsConstructor<JSFunction>(source.toJS).callAsFunction() as JSFunction;
  return factory.callAsFunction(null, real, omitted.toJS) as JSObject;
}

Future<YuvCapabilities> _initializeWith(JSObject module) async {
  YuvWasmLoader.debugReset();
  YuvWasmLoader.debugSetInitializer(({required String scriptPath, required String wasmPath, required String moduleFactoryName}) async {
    return YuvModule(module);
  });
  return YuvFfi.initialize();
}

YuvImage _grayImage() => YuvImage.bgra(2, 2, planes: [YuvPlane(2, 8, 4, Uint8List.fromList(List.generate(16, (i) => i % 4 == 3 ? 255 : 100)))]);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late JSObject realModule;
  setUpAll(() async {
    YuvWasmLoader.debugReset();
    realModule = (await YuvWasmLoader.ensureInitialized()).rawModule as JSObject;
  });
  tearDown(YuvWasmLoader.debugReset);

  for (final omitted in ['', '_$yuvSymbolGrayscaleV1']) {
    testWidgets('${omitted.isEmpty ? 'complete' : 'partial'} shipped module executes public convert and negate with exact pixels', (_) async {
      final module = _forwardingModule(realModule, omitted: omitted);
      final capabilities = await _initializeWith(module);
      expect(capabilities.supports(YuvOperation.grayscale, sourceFormat: YuvPixelFormat.bgra8888), omitted.isEmpty);
      expect(capabilities.supports(YuvOperation.convert, sourceFormat: YuvPixelFormat.bgra8888, destinationFormat: YuvPixelFormat.i420), isTrue);
      expect(capabilities.supports(YuvOperation.negate, sourceFormat: YuvPixelFormat.bgra8888), isTrue);

      final image = _grayImage();
      final converted = image.toI420();
      expect(converted.planes.map((plane) => plane.bytes), [
        [102, 102, 102, 102],
        [128],
        [128],
      ]);
      image.applyNegate();
      expect(image.planes.single.bytes, List.generate(16, (i) => i % 4 == 3 ? 255 : 155));
      expect(module.getProperty<JSNumber>('__calls'.toJS).toDartInt, 2);
      expect(module.getProperty<JSNumber>('__live'.toJS).toDartInt, 0);
    });
  }

  testWidgets('missing requested export rejects before staging and preserves image bytes and revision', (_) async {
    final module = _forwardingModule(realModule, omitted: '_$yuvSymbolNegateV1');
    final capabilities = await _initializeWith(module);
    expect(capabilities.supports(YuvOperation.negate, sourceFormat: YuvPixelFormat.bgra8888), isFalse);
    final image = _grayImage();
    final before = image.toBytes();
    final revision = (image as YuvRevisionAware).internalRevision;

    expect(image.applyNegate, throwsUnsupportedError);
    expect(image.toBytes(), before);
    expect((image as YuvRevisionAware).internalRevision, revision);
    expect(module.getProperty<JSNumber>('__allocations'.toJS).toDartInt, 0);
    expect(module.getProperty<JSNumber>('__calls'.toJS).toDartInt, 0);
  });

  testWidgets('missing runtime primitive names the failure before any staging or mutation', (_) async {
    for (final primitive in ['ccall', '_malloc', '_free', 'HEAPU8']) {
      final module = _forwardingModule(realModule, omitted: primitive);
      await _initializeWith(module);
      final image = _grayImage();
      final before = image.toBytes();
      final revision = (image as YuvRevisionAware).internalRevision;

      expect(image.applyNegate, throwsA(isA<StateError>().having((error) => error.message, 'primitive', contains(primitive))));
      expect(image.toBytes(), before);
      expect((image as YuvRevisionAware).internalRevision, revision);
      expect(module.getProperty<JSNumber>('__allocations'.toJS).toDartInt, 0);
    }
  });

  testWidgets('failed partial-module ABI call frees staging and preserves image bytes and revision', (_) async {
    final module = _forwardingModule(realModule, omitted: '_$yuvSymbolGrayscaleV1');
    module.setProperty('__status'.toJS, 6.toJS);
    await _initializeWith(module);
    final image = _grayImage();
    final before = image.toBytes();
    final revision = (image as YuvRevisionAware).internalRevision;

    expect(image.applyNegate, throwsA(isA<YuvNativeException>()));
    expect(image.toBytes(), before);
    expect((image as YuvRevisionAware).internalRevision, revision);
    expect(module.getProperty<JSNumber>('__calls'.toJS).toDartInt, 1);
    expect(module.getProperty<JSNumber>('__allocations'.toJS).toDartInt, greaterThan(0));
    expect(module.getProperty<JSNumber>('__live'.toJS).toDartInt, 0);
  });
}
