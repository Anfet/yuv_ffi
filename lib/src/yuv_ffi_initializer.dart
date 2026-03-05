import 'package:yuv_ffi/src/loader/loader.dart' as backend_loader;

/// Public package bootstrap API.
///
/// Call this once at app startup before using image operations.
/// - On IO/native platforms it initializes native dynamic library access.
/// - On Web it initializes the WASM runtime/module loader.
final class YuvFfi {
  const YuvFfi._();

  /// Initializes backend resources required by this package.
  ///
  /// Call once before any `YuvImage` operation.
  ///
  /// Behavior by platform:
  /// - IO/native: loads and prepares the dynamic library bindings.
  /// - Web: loads and initializes the WASM runtime/module.
  ///
  /// This method is idempotent and safe to call multiple times.
  ///
  /// Throws a [StateError] when initialization fails
  /// (for example, missing Web WASM assets or module factory).
  static Future<void> ensureInitialized() async {
    await backend_loader.ensureInitialized();
  }
}
