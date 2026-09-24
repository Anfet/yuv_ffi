@TestOn('browser')
// Drives the Web loader against a fake Emscripten module through
// `dart:js_interop`, which the VM cannot compile; `@TestOn` excludes this file
// from a VM run rather than letting it fail to load.
library;

// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/src/loader/wasm_loader.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_abi_v1_symbols.dart';
import 'package:yuv_ffi/src/yuv_capabilities.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Verifies REL-09's Web wiring: [YuvFfi.initialize] computes capabilities
/// from the real WASM exports the loaded module actually carries -- never a
/// hardcoded "everything is supported" default -- and marks an operation
/// supported only when its required export is present and the module
/// initialized successfully (`doc/api-abi-0.4-design.md` section 7). Unlike
/// IO, a partially exported module does not fail initialization: it yields a
/// capability snapshot naming exactly what is present, since Web is a
/// documented partial WASM backend.
///
/// Follows `wasm_swap_nv_atomicity_test.dart`'s pattern: a fake Emscripten
/// module object whose exported-function properties are set directly, so
/// `YuvAbiV1WebDispatch.moduleExports` sees real property presence rather than
/// a mocked return value.

/// A fake module object exporting exactly [presentSymbols] (by their
/// Emscripten-prefixed name) of the ABI v1 manifest.
JSObject _moduleExporting(Iterable<String> presentSymbols) {
  final module = JSObject();
  for (final symbol in presentSymbols) {
    module.setProperty('_$symbol'.toJS, true.toJS);
  }
  return module;
}

Future<YuvCapabilities> _initializeWith(JSObject module) async {
  YuvWasmLoader.debugReset();
  YuvWasmLoader.debugSetInitializer(({required String scriptPath, required String wasmPath, required String moduleFactoryName}) async {
    return YuvModule(module);
  });
  return YuvFfi.initialize();
}

void main() {
  tearDown(YuvWasmLoader.debugReset);

  test('runs on a real browser runtime', () {
    expect(kIsWeb, isTrue);
  });

  test('a module exporting the complete ABI v1 manifest yields capabilities supporting every operation', () async {
    final capabilities = await _initializeWith(_moduleExporting(yuvAbiV1Symbols));

    for (final operation in YuvOperation.values) {
      expect(
        capabilities.supports(
          operation,
          sourceFormat: YuvPixelFormat.nv12,
          destinationFormat: operation == YuvOperation.convert ? YuvPixelFormat.nv12 : null,
        ),
        isTrue,
        reason: '$operation must be supported once its WASM export is present',
      );
    }
  });

  test('a module missing one export marks only the affected operation unsupported, without failing initialization', () async {
    final present = yuvAbiV1Symbols.where((symbol) => symbol != yuvSymbolGrayscaleV1);
    final capabilities = await _initializeWith(_moduleExporting(present));

    expect(
      capabilities.supports(YuvOperation.grayscale, sourceFormat: YuvPixelFormat.nv12),
      isFalse,
      reason: 'grayscale must be unsupported when yuv_grayscale_v1 is missing from the module',
    );
    expect(
      capabilities.supports(YuvOperation.negate, sourceFormat: YuvPixelFormat.nv12),
      isTrue,
      reason: 'an unrelated operation whose export is present must remain supported',
    );
  });

  test('a module exporting nothing yields a snapshot supporting no operation, not a hardcoded default', () async {
    final capabilities = await _initializeWith(_moduleExporting(const <String>[]));

    for (final operation in YuvOperation.values) {
      expect(
        capabilities.supports(
          operation,
          sourceFormat: YuvPixelFormat.nv12,
          destinationFormat: operation == YuvOperation.convert ? YuvPixelFormat.nv12 : null,
        ),
        isFalse,
        reason: '$operation must be unsupported when no WASM export is present',
      );
    }
  });

  test('querying an operation the module does not support throws UnsupportedError before any state exists to mutate', () async {
    final capabilities = await _initializeWith(_moduleExporting(const <String>[]));

    expect(() => yuvRequireCapability(capabilities, YuvOperation.rotate, sourceFormat: YuvPixelFormat.nv12), throwsUnsupportedError);
  });
}
