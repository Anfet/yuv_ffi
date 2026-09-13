import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/src/loader/wasm_loader.dart';

/// Verifies YUV-21 on the Web backend: concurrent callers share one attempt,
/// a failure leaves nothing behind, and a later call really retries.
///
/// The counted initializer seam is what makes those observable without
/// deleting or substituting real WASM assets.
void main() {
  if (!kIsWeb) {
    test('web loader initialization tests are skipped on non-web runtime', () {
      expect(true, isTrue);
    });
    return;
  }

  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(YuvWasmLoader.debugReset);

  test('runs on a real web runtime', () {
    expect(kIsWeb, isTrue);
  });

  test('a successful initialization is cached across repeated calls', () async {
    YuvWasmLoader.debugReset();
    YuvWasmLoader.debugSetInitializer(({
      required String scriptPath,
      required String wasmPath,
      required String moduleFactoryName,
    }) async {
      return YuvModule(Object());
    });

    await YuvWasmLoader.ensureInitialized();
    await YuvWasmLoader.ensureInitialized();
    await YuvWasmLoader.ensureInitialized();

    expect(YuvWasmLoader.debugInitCount, 1);
  });

  test('concurrent callers share one in-flight attempt', () async {
    YuvWasmLoader.debugReset();
    YuvWasmLoader.debugSetInitializer(({
      required String scriptPath,
      required String wasmPath,
      required String moduleFactoryName,
    }) async {
      await Future<void>.delayed(Duration.zero);
      return YuvModule(Object());
    });

    await Future.wait<YuvModule>(<Future<YuvModule>>[
      YuvWasmLoader.ensureInitialized(),
      YuvWasmLoader.ensureInitialized(),
      YuvWasmLoader.ensureInitialized(),
      YuvWasmLoader.ensureInitialized(),
    ]);

    expect(YuvWasmLoader.debugInitCount, 1, reason: 'concurrent callers must not each start initialization');
  });

  test('a failed attempt is not cached and the next call retries', () async {
    var attempts = 0;
    YuvWasmLoader.debugReset();
    YuvWasmLoader.debugSetInitializer(({
      required String scriptPath,
      required String wasmPath,
      required String moduleFactoryName,
    }) async {
      attempts++;
      if (attempts == 1) {
        throw StateError('simulated init failure');
      }
      return YuvModule(Object());
    });

    await expectLater(YuvWasmLoader.ensureInitialized(), throwsStateError);

    // Before the fix a failed future was cached forever and this could not
    // succeed in the same process.
    await YuvWasmLoader.ensureInitialized();

    expect(attempts, 2);
    expect(YuvWasmLoader.debugInitCount, 2);
  });

  test('a failed attempt leaves no partially initialized module', () async {
    YuvWasmLoader.debugReset();
    YuvWasmLoader.debugSetInitializer(({
      required String scriptPath,
      required String wasmPath,
      required String moduleFactoryName,
    }) async {
      throw StateError('simulated init failure');
    });

    await expectLater(YuvWasmLoader.ensureInitialized(), throwsStateError);

    expect(YuvWasmLoader.moduleIfInitialized, isNull);
  });

  test('the original error type and stack trace survive', () async {
    YuvWasmLoader.debugReset();
    YuvWasmLoader.debugSetInitializer(({
      required String scriptPath,
      required String wasmPath,
      required String moduleFactoryName,
    }) async {
      throw StateError('simulated init failure');
    });

    Object? caught;
    StackTrace? trace;
    try {
      await YuvWasmLoader.ensureInitialized();
    } catch (error, stackTrace) {
      caught = error;
      trace = stackTrace;
    }

    expect(caught, isA<StateError>());
    expect(trace, isNotNull);
  });

  test('a successful initialization exposes the module', () async {
    YuvWasmLoader.debugReset();
    YuvWasmLoader.debugSetInitializer(({
      required String scriptPath,
      required String wasmPath,
      required String moduleFactoryName,
    }) async {
      return YuvModule(Object());
    });

    await YuvWasmLoader.ensureInitialized();

    expect(YuvWasmLoader.moduleIfInitialized, isNotNull);
  });
}
