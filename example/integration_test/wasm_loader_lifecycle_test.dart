import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_ffi/src/loader/wasm_loader.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Web acceptance for YUV-21: the WASM loader lifecycle seams behave
/// correctly under a real browser runtime.
///
/// `flutter test --platform chrome` serves no asset bundle, so it cannot
/// exercise the real asset-loaded module (see `wasm_bootstrap_test.dart`).
/// This harness runs against a real built application instead, which is
/// also why these lifecycle cases — originally proven in
/// `test/web/wasm_loader_initialization_test.dart` against the loader in
/// isolation — are ported here rather than merely trusted from that suite.
///
/// Each case installs a fake initializer via `debugSetInitializer` to count
/// attempts and fail deterministically without touching real WASM assets.
/// The final case restores the real initializer and proves the harness
/// genuinely loads the WASM bundle, so the fakes above did not leave the
/// loader broken for actual use.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  tearDown(YuvWasmLoader.debugReset);

  testWidgets('runs on a real web runtime', (tester) async {
    expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');
  });

  testWidgets('a successful initialization is cached across repeated calls', (tester) async {
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

  testWidgets('concurrent callers share one in-flight attempt', (tester) async {
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

  testWidgets('a failed attempt is not cached and the next call retries', (tester) async {
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

  testWidgets('a failed attempt leaves no partially initialized module', (tester) async {
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

  testWidgets('the original error type and stack trace survive', (tester) async {
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

  testWidgets('the real asset-loaded module still initializes after the fakes above', (tester) async {
    YuvWasmLoader.debugReset();

    await YuvFfi.ensureInitialized();

    expect(YuvWasmLoader.moduleIfInitialized, isNotNull);
  });

  testWidgets('a retry after a real script-load failure succeeds', (tester) async {
    expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');

    // Every case above replaces the initializer wholesale, which means none of
    // them ever runs _injectScriptOnce — and that is precisely where retry was
    // broken: a failed <script> stayed in the document, so the next attempt
    // found the marker, skipped injection, and then failed looking for a
    // factory no script had defined. Only the real initializer can show it.
    YuvWasmLoader.debugReset();

    await expectLater(
      YuvWasmLoader.ensureInitialized(scriptPath: 'assets/packages/yuv_ffi/assets/wasm/does_not_exist.js'),
      throwsA(isA<StateError>()),
      reason: 'a missing loader script must surface as a StateError',
    );
    expect(YuvWasmLoader.moduleIfInitialized, isNull);

    // The retry uses the real defaults. Before the fix this threw "module
    // factory was not found", because injection had been skipped.
    await YuvWasmLoader.ensureInitialized();

    expect(YuvWasmLoader.moduleIfInitialized, isNotNull, reason: 'a retry after a failed script load must be able to succeed');
    expect(YuvWasmLoader.debugInitCount, 2, reason: 'the failure and the retry are two genuine attempts');
  });

  testWidgets('the module works after recovering from a failed script load', (tester) async {
    expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');

    YuvWasmLoader.debugReset();

    await expectLater(
      YuvWasmLoader.ensureInitialized(scriptPath: 'assets/packages/yuv_ffi/assets/wasm/missing_loader.js'),
      throwsA(isA<StateError>()),
    );

    await YuvFfi.ensureInitialized();

    // A recovered loader has to give a usable module, not merely a non-null
    // one: this crosses into WASM and back.
    final image = YuvImage.bgra(2, 2);
    expect(image.toBgra8888(), hasLength(2 * 2 * 4));
  });
}
