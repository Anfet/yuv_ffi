import 'package:yuv_ffi/src/loader/wasm_loader.dart';

/// Web implementation placeholder for native FFI loader entrypoints.
///
/// The native dynamic-library loader is not available on Web.
Never get library => throw UnsupportedError(
      'Native FFI dynamic library is not available on Web.',
    );

/// Web implementation placeholder for generated native bindings access.
Never get ffiBingings => throw UnsupportedError(
      'Native FFI bindings are not available on Web.',
    );

/// Unified backend initialization entrypoint for web platform.
///
/// This reuses the WASM bootstrap loader and gives higher-level code a single
/// entrypoint (`ensureInitialized`) across all platforms.
Future<void> ensureInitialized() async {
  await YuvWasmLoader.ensureInitialized();
}
