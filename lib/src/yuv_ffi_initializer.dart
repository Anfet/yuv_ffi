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
  /// Behavior by platform:
  /// - IO/native: loads and prepares the dynamic library bindings.
  /// - Web: loads and initializes the WASM runtime/module.
  ///
  /// ## When it is required
  ///
  /// On Web this must be awaited before any `YuvImage` operation: there is no
  /// lazy fallback, and an operation started earlier fails.
  ///
  /// On IO/native it is recommended rather than required. Native operations can
  /// still open the library lazily on first use, so calling this at startup
  /// buys early, predictable diagnostics instead of a failure at the first
  /// image operation.
  ///
  /// ## Repeated calls
  ///
  /// A successful initialization is cached, so later calls reuse it and do no
  /// work. Concurrent Web callers share a single in-flight attempt.
  ///
  /// A failed attempt is not cached on either platform: the next explicit call
  /// really retries and may succeed. Nothing partially initialized is left
  /// behind by a failure.
  ///
  /// ## Isolates
  ///
  /// Initialization state is held per-isolate, not process-wide. A fresh
  /// isolate always starts uninitialized and must call this itself.
  ///
  /// ## Web status
  ///
  /// The Web backend is a partial WASM implementation: a successful
  /// [initialize] only means the WASM runtime loaded, not that every
  /// operation available on IO/native is supported. See
  /// `lib/src/yuv/impl/web/yuv_web.dart` for current Web limitations.
  ///
  /// ## Errors
  ///
  /// The original error is preserved rather than wrapped, so its type, message
  /// and stack trace stay usable:
  /// - Web configuration and runtime failures (missing WASM asset or module
  ///   factory) throw [StateError].
  /// - An unsupported native platform throws [UnsupportedError].
  /// - A native library that cannot be opened throws the platform's own FFI
  ///   error.
  static Future<void> initialize() async {
    await backend_loader.ensureInitialized();
  }

  /// Deprecated alias for [initialize].
  @Deprecated('Use initialize().')
  static Future<void> ensureInitialized() => initialize();
}
