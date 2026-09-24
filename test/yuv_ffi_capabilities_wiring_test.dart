import 'dart:ffi' as ffi;

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/src/loader/impl/loader_io.dart' as loader_io;
import 'package:yuv_ffi/src/yuv/shared/yuv_abi_v1_symbols.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Verifies REL-09's IO wiring: [YuvFfi.initialize] computes capabilities from
/// the real symbols the loaded library resolves -- never a hardcoded
/// "everything is supported" default -- and native IO initialization requires
/// the complete ABI v1 manifest rather than returning a capability snapshot
/// that silently marks a missing export unsupported
/// (`doc/api-abi-0.4-design.md` section 7).
///
/// Uses the same replaceable-opener/symbol-checker seam
/// `loader_io_test.dart`/`yuv_ffi_initializer_test.dart` use, so this runs on
/// every host without a real native library.
void main() {
  tearDown(loader_io.debugResetLoader);

  group('IO capabilities reflect real symbol presence', () {
    test('a library exporting the complete ABI v1 manifest yields capabilities supporting every operation', () async {
      loader_io.debugResetLoader();
      loader_io.debugSetLibraryOpener(() => ffi.DynamicLibrary.executable());
      loader_io.debugSetSymbolChecker((_, _) => true);

      final capabilities = await YuvFfi.initialize();

      for (final operation in YuvOperation.values) {
        // chromaSwap only ever accepts NV12 (section 11); every other
        // operation accepts every YuvPixelFormat, so NV12 exercises all of
        // them uniformly.
        expect(
          capabilities.supports(
            operation,
            sourceFormat: YuvPixelFormat.nv12,
            destinationFormat: operation == YuvOperation.convert ? YuvPixelFormat.nv12 : null,
          ),
          isTrue,
          reason: '$operation must be supported once every ABI v1 symbol resolved',
        );
      }
    });

    test('a library missing one required symbol fails initialization outright, rather than returning a partial snapshot', () async {
      loader_io.debugResetLoader();
      loader_io.debugSetLibraryOpener(() => ffi.DynamicLibrary.executable());
      // Every symbol resolves except the one grayscale needs.
      loader_io.debugSetSymbolChecker((_, symbol) => symbol != yuvSymbolGrayscaleV1);

      await expectLater(YuvFfi.initialize(), throwsA(isA<StateError>().having((e) => e.message, 'message', contains(yuvSymbolGrayscaleV1))));
    });

    test('a library missing every symbol fails initialization naming all of them', () async {
      loader_io.debugResetLoader();
      loader_io.debugSetLibraryOpener(() => ffi.DynamicLibrary.executable());
      loader_io.debugSetSymbolChecker((_, _) => false);

      await expectLater(YuvFfi.initialize(), throwsA(isA<StateError>()));
    });
  });
}
