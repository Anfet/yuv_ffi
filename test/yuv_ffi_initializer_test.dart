import 'dart:ffi' as ffi;

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/src/loader/impl/loader_io.dart' as loader_io;
import 'package:yuv_ffi/yuv_ffi.dart';

/// Verifies REL-08: the public `YuvFfi.initialize()` entrypoint shares one
/// in-flight future across concurrent callers, really retries after a failure,
/// and keeps the deprecated `ensureInitialized()` name working as a forwarder.
///
/// These tests exercise the IO backend loader beneath `YuvFfi`, using the same
/// replaceable-opener seam `loader_io_test.dart` uses, so a failure can be
/// simulated deterministically without deleting or substituting the real
/// native library.
void main() {
  tearDown(loader_io.debugResetLoader);

  group('YuvFfi.initialize', () {
    test('concurrent callers share a single initialization', () async {
      var opens = 0;
      loader_io.debugResetLoader();
      loader_io.debugSetLibraryOpener(() {
        opens++;
        return _fakeLibrary();
      });

      await Future.wait<void>(<Future<void>>[YuvFfi.initialize(), YuvFfi.initialize(), YuvFfi.initialize(), YuvFfi.initialize()]);

      expect(opens, 1, reason: 'concurrent callers must not each trigger initialization');
    });

    test('a failed initialization is not cached and a later call retries', () async {
      var attempts = 0;
      loader_io.debugResetLoader();
      loader_io.debugSetLibraryOpener(() {
        attempts++;
        if (attempts == 1) {
          throw ArgumentError('simulated open failure');
        }
        return _fakeLibrary();
      });

      await expectLater(YuvFfi.initialize(), throwsArgumentError);

      // A poisoned future would make this hang or replay the same rejection.
      await YuvFfi.initialize();

      expect(attempts, 2);
    });

    test('a successful initialization is cached across repeated calls', () async {
      var opens = 0;
      loader_io.debugResetLoader();
      loader_io.debugSetLibraryOpener(() {
        opens++;
        return _fakeLibrary();
      });

      await YuvFfi.initialize();
      await YuvFfi.initialize();
      await YuvFfi.initialize();

      expect(opens, 1);
    });
  });

  group('YuvFfi.ensureInitialized (deprecated forwarder)', () {
    test('forwards to initialize() and completes successfully', () async {
      var opens = 0;
      loader_io.debugResetLoader();
      loader_io.debugSetLibraryOpener(() {
        opens++;
        return _fakeLibrary();
      });

      // ignore: deprecated_member_use_from_same_package
      await YuvFfi.ensureInitialized();

      expect(opens, 1);
    });

    test('shares in-flight state with initialize() rather than starting a second attempt', () async {
      var opens = 0;
      loader_io.debugResetLoader();
      loader_io.debugSetLibraryOpener(() {
        opens++;
        return _fakeLibrary();
      });

      await Future.wait<void>(<Future<void>>[
        YuvFfi.initialize(),
        // ignore: deprecated_member_use_from_same_package
        YuvFfi.ensureInitialized(),
      ]);

      expect(opens, 1);
    });

    test('a failure surfaced through ensureInitialized() still allows a later retry', () async {
      var attempts = 0;
      loader_io.debugResetLoader();
      loader_io.debugSetLibraryOpener(() {
        attempts++;
        if (attempts == 1) {
          throw ArgumentError('simulated open failure');
        }
        return _fakeLibrary();
      });

      // ignore: deprecated_member_use_from_same_package
      await expectLater(YuvFfi.ensureInitialized(), throwsArgumentError);
      await YuvFfi.initialize();

      expect(attempts, 2);
    });
  });
}

ffi.DynamicLibrary _fakeLibrary() => ffi.DynamicLibrary.executable();
