import 'dart:ffi' as ffi;

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/src/loader/impl/loader_io.dart' as loader_io;
import 'package:yuv_ffi/src/loader/loader.dart';
import 'package:yuv_ffi/src/loader/wasm_loader.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_operation.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_pixel_format.dart';

/// Verifies YUV-21: the native initialization contract.
///
/// The counted opener seam is what makes "does not reopen" and "really retries"
/// observable; asserting on the returned library alone would prove neither.
void main() {
  final bool nativeAvailable = _checkNativeAvailable();

  group('native bindings loader', () {
    test('reuses one bindings instance', () {
      final first = ffiBingings;
      final second = ffiBingings;
      final third = ffiBingings;

      expect(identical(second, first), isTrue);
      expect(identical(third, first), isTrue);
    });
  }, skip: nativeAvailable ? false : 'native yuv_ffi library is not available on this host');

  group('initialization contract', () {
    tearDown(loader_io.debugResetLoader);

    test('a successful open is cached across repeated calls', () async {
      final fake = ffi.DynamicLibrary.executable();
      loader_io.debugResetLoader();
      loader_io.debugSetLibraryOpener(() => fake);
      loader_io.debugSetSymbolChecker((_, _) => true);

      await loader_io.ensureInitialized();
      await loader_io.ensureInitialized();
      await loader_io.ensureInitialized();

      expect(loader_io.debugOpenCount, 1, reason: 'a cached library must not be reopened');
    });

    test('concurrent callers observe a single open', () async {
      final fake = ffi.DynamicLibrary.executable();
      loader_io.debugResetLoader();
      loader_io.debugSetLibraryOpener(() => fake);
      loader_io.debugSetSymbolChecker((_, _) => true);

      await Future.wait<void>(<Future<void>>[
        loader_io.ensureInitialized(),
        loader_io.ensureInitialized(),
        loader_io.ensureInitialized(),
        loader_io.ensureInitialized(),
      ]);

      expect(loader_io.debugOpenCount, 1);
    });

    test('a failed attempt is not cached and the next call retries', () async {
      final fake = ffi.DynamicLibrary.executable();
      var attempts = 0;
      loader_io.debugResetLoader();
      loader_io.debugSetSymbolChecker((_, _) => true);
      loader_io.debugSetLibraryOpener(() {
        attempts++;
        if (attempts == 1) {
          throw ArgumentError('simulated open failure');
        }
        return fake;
      });

      await expectLater(loader_io.ensureInitialized(), throwsArgumentError);

      // The second attempt must really run rather than replay the failure.
      await loader_io.ensureInitialized();

      expect(attempts, 2);
      expect(loader_io.debugOpenCount, 2);
    });

    test('the original error type and stack trace survive', () async {
      loader_io.debugResetLoader();
      loader_io.debugSetLibraryOpener(() => throw ArgumentError('simulated open failure'));

      Object? caught;
      StackTrace? trace;
      try {
        await loader_io.ensureInitialized();
      } catch (error, stackTrace) {
        caught = error;
        trace = stackTrace;
      }

      // The type is asserted rather than the platform message, which is brittle.
      expect(caught, isA<ArgumentError>());
      expect(trace, isNotNull);
    });

    test('the lazy getter opens the library without ensureInitialized', () {
      final fake = ffi.DynamicLibrary.executable();
      loader_io.debugResetLoader();
      loader_io.debugSetLibraryOpener(() => fake);

      // Documented IO behaviour: native access stays usable without an explicit
      // startup call, unlike Web.
      expect(loader_io.library, isNotNull);
      expect(loader_io.debugOpenCount, 1);
    });

    test('a reset drops bindings built from the previous library', () async {
      final fake = ffi.DynamicLibrary.executable();
      loader_io.debugResetLoader();
      loader_io.debugSetLibraryOpener(() => fake);
      loader_io.debugSetSymbolChecker((_, _) => true);

      await loader_io.ensureInitialized();
      final before = loader_io.ffiBingings;

      loader_io.debugResetLoader();
      loader_io.debugSetLibraryOpener(() => fake);
      loader_io.debugSetSymbolChecker((_, _) => true);
      await loader_io.ensureInitialized();

      expect(identical(loader_io.ffiBingings, before), isFalse, reason: 'bindings must not outlive their library');
    });
  });

  group('REL-10: missing ABI v1 symbol manifest gate', () {
    // `doc/api-abi-0.4-design.md` section 7: a native library missing a
    // required export "fails initialization ... rather than returning
    // capabilities that silently mark it unsupported" -- StateError, not
    // YuvNativeException or UnsupportedError, since this is a load-time
    // configuration failure rather than a per-call native status.
    tearDown(loader_io.debugResetLoader);

    test('a library missing a required export fails initialization with StateError naming it', () async {
      final fake = ffi.DynamicLibrary.executable();
      loader_io.debugResetLoader();
      loader_io.debugSetLibraryOpener(() => fake);
      loader_io.debugSetSymbolChecker((_, symbol) => symbol != 'yuv_grayscale_v1');

      await expectLater(loader_io.ensureInitialized(), throwsA(isA<StateError>().having((e) => e.message, 'message', contains('yuv_grayscale_v1'))));
    });

    test('a library missing several required exports names all of them', () async {
      final fake = ffi.DynamicLibrary.executable();
      loader_io.debugResetLoader();
      loader_io.debugSetLibraryOpener(() => fake);
      const missing = {'yuv_crop_v1', 'yuv_rotate_v1'};
      loader_io.debugSetSymbolChecker((_, symbol) => !missing.contains(symbol));

      await expectLater(
        loader_io.ensureInitialized(),
        throwsA(isA<StateError>().having((e) => e.message, 'message', allOf(contains('yuv_crop_v1'), contains('yuv_rotate_v1')))),
      );
    });

    test('a failed manifest gate is not cached: a later call with a complete library retries and succeeds', () async {
      final fake = ffi.DynamicLibrary.executable();
      loader_io.debugResetLoader();
      loader_io.debugSetLibraryOpener(() => fake);
      loader_io.debugSetSymbolChecker((_, symbol) => symbol != 'yuv_grayscale_v1');

      await expectLater(loader_io.ensureInitialized(), throwsStateError);

      // Nothing partial survives the failed attempt: the next explicit call
      // sees a complete manifest and genuinely succeeds instead of replaying
      // the earlier rejection.
      loader_io.debugSetSymbolChecker((_, _) => true);
      final capabilities = await loader_io.ensureInitialized();

      expect(capabilities.supports(YuvOperation.grayscale, sourceFormat: YuvPixelFormat.nv12), isTrue);
    });
  });

  group('REL-10: WASM loader stub on a non-web (VM) target', () {
    // `wasm_loader_io.dart` is the fallback compiled in whenever
    // `dart.library.js_interop` is unavailable, i.e. every host `flutter
    // test` runs on. Calling it here (rather than through the Web backend,
    // which never reaches this file on Web) is a configuration error --
    // native FFI backends exist for this platform instead -- so it must fail
    // fast with UnsupportedError rather than a native-status exception.
    test('ensureInitialized throws UnsupportedError and initializes nothing', () async {
      expect(YuvWasmLoader.moduleIfInitialized, isNull);
      await expectLater(YuvWasmLoader.ensureInitialized(), throwsUnsupportedError);
      expect(YuvWasmLoader.moduleIfInitialized, isNull, reason: 'a rejected non-web stub call must leave no module published');
      expect(YuvWasmLoader.debugInitCount, 0);
    });
  });
}

bool _checkNativeAvailable() {
  try {
    library;
    return true;
  } catch (_) {
    return false;
  }
}
