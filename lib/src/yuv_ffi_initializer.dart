import 'package:yuv_ffi/src/loader/loader.dart' as backend_loader;

/// Public package bootstrap API.
///
/// Call this once at app startup before using image operations.
/// - On IO/native platforms it initializes native dynamic library access.
/// - On Web it initializes the WASM runtime/module loader.
final class YuvFfi {
  const YuvFfi._();

  static Future<void> ensureInitialized() async {
    await backend_loader.ensureInitialized();
  }
}
