import 'package:yuv_ffi/src/loader/wasm_loader.dart';
import 'package:yuv_ffi/src/yuv/impl/web/yuv_abi_v1_dispatch_web.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_operation.dart';
import 'package:yuv_ffi/src/yuv_capabilities.dart';

/// Web implementation placeholder for native FFI loader entrypoints.
///
/// The native dynamic-library loader is not available on Web.
Never get library => throw UnsupportedError('Native FFI dynamic library is not available on Web.');

/// Web implementation placeholder for generated native bindings access.
Never get ffiBingings => throw UnsupportedError('Native FFI bindings are not available on Web.');

/// Unified backend initialization entrypoint for web platform.
///
/// This reuses the WASM bootstrap loader and gives higher-level code a single
/// entrypoint (`ensureInitialized`) across all platforms. Unlike IO, a missing
/// export does not fail initialization here: Web is a partial WASM backend
/// (`doc/api-abi-0.4-design.md` section 7), so the returned capabilities mark
/// an operation supported only when its required export is actually present
/// on the loaded module.
Future<YuvCapabilities> ensureInitialized() async {
  final module = await YuvWasmLoader.ensureInitialized();
  final available = yuvAvailableOperations((symbol) => YuvAbiV1WebDispatch.moduleExports(module.rawModule, symbol));
  return YuvCapabilitiesSnapshot(available);
}
