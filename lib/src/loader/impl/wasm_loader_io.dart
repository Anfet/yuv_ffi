/// Non-web fallback for the WASM loader API.
///
/// This file intentionally provides the same surface as the web loader so
/// higher-level code can import `wasm_loader.dart` unconditionally.
class YuvModule {
  const YuvModule._();

  Object get rawModule => throw UnsupportedError(
        'YuvModule.rawModule is available only on Web.',
      );
}

/// Stub loader used on non-web targets.
///
/// Calling this on non-web platforms is a configuration error and should fail
/// fast with a clear message.
final class YuvWasmLoader {
  const YuvWasmLoader._();

  static YuvModule? get moduleIfInitialized => null;

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
