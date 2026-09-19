/// Non-web fallback for the WASM loader API.
///
/// This file intentionally provides the same surface as the web loader so
/// higher-level code — and tests resolved against the VM target — can import
/// `wasm_loader.dart` unconditionally. Behaviour still differs: everything that
/// would touch a real module fails fast here.
class YuvModule {
  /// Mirrors the web constructor so shared test code compiles on both targets.
  const YuvModule(Object rawModule) : _rawModule = rawModule;

  final Object _rawModule;

  Object get rawModule => _rawModule;
}

/// Stub loader used on non-web targets.
///
/// Calling initialization on non-web platforms is a configuration error and
/// fails fast with a clear message. The debug seam exists only to keep the
/// surface identical to the web implementation.
final class YuvWasmLoader {
  const YuvWasmLoader._();

  static YuvModule? get moduleIfInitialized => null;

  /// Always zero: initialization never starts on a non-web target.
  static int debugInitCount = 0;

  /// Accepted and ignored, so a shared test can set it on either target.
  static void debugSetInitializer(
    Future<YuvModule> Function({
      required String scriptPath,
      required String wasmPath,
      required String moduleFactoryName,
    })? initializer,
  ) {}

  /// Resets the counter; there is no cached state on a non-web target.
  static void debugReset() {
    debugInitCount = 0;
  }

  /// Accepted and ignored: there is no document to inject into here.
  static void debugRemoveInjectedScript() {}

  /// Always false: there is no document to inject into here.
  static bool get debugHasInjectedScript => false;

  static Future<YuvModule> ensureInitialized({
    String scriptPath = '',
    String wasmPath = '',
    String moduleFactoryName = '',
  }) async {
    throw UnsupportedError(
      'YuvWasmLoader is available only on Web. '
      'Use native FFI backends on mobile/desktop.',
    );
  }
}
