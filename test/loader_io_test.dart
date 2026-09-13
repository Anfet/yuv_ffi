import 'dart:ffi' as ffi;

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/src/loader/impl/loader_io.dart' as loader_io;
import 'package:yuv_ffi/src/loader/loader.dart';

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

      await loader_io.ensureInitialized();
      await loader_io.ensureInitialized();
      await loader_io.ensureInitialized();

      expect(loader_io.debugOpenCount, 1, reason: 'a cached library must not be reopened');
    });

    test('concurrent callers observe a single open', () async {
      final fake = ffi.DynamicLibrary.executable();
      loader_io.debugResetLoader();
      loader_io.debugSetLibraryOpener(() => fake);

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

      await loader_io.ensureInitialized();
      final before = loader_io.ffiBingings;

      loader_io.debugResetLoader();
      loader_io.debugSetLibraryOpener(() => fake);
      await loader_io.ensureInitialized();

      expect(identical(loader_io.ffiBingings, before), isFalse, reason: 'bindings must not outlive their library');
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
