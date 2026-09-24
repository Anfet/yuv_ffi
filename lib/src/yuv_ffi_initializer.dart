import 'package:yuv_ffi/src/loader/loader.dart' as backend_loader;
import 'package:yuv_ffi/src/yuv_capabilities.dart';

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
  /// On IO/native it must complete before the capability-gated `0.4.0`
  /// processing methods: [YuvImage.applyRgbaBytes], [YuvImage.applyGrayscale],
  /// [YuvImage.applyBlackWhite], [YuvImage.applyNegate],
  /// [YuvImage.applyGaussianBlur], [YuvImage.applyMeanBlur],
  /// [YuvImage.applyBoxBlur], [YuvImage.applyCrop],
  /// [YuvImage.applyFlipHorizontal], [YuvImage.applyFlipVertical],
  /// [YuvImage.applyRotation], [YuvImage.applyFormat],
  /// [YuvImage.applyChromaSwap], [YuvImage.cropped], [YuvImage.rotated],
  /// [YuvImage.toI420], [YuvImage.toNv12], and [YuvImage.toBgra].
  /// [YuvImage.applyPlanes] is not capability-gated: it only validates and
  /// replaces Dart plane buffers, so it works before bootstrap. Before this
  /// call succeeds, a capability-gated method throws [UnsupportedError]
  /// because backend capability has not been determined, not because the
  /// requested operation is unsupported.
  ///
  /// IO/native retains its previous lazy behavior for constructors, plane
  /// access, [YuvImage.copy], [YuvImage.applyPlanes], [YuvImage.toBytes],
  /// [YuvImage.toBgraBytes], [YuvImage.toImage], [YuvImage.encodeTo],
  /// [YuvImage.decode], [YuvImage.fromRgbaBytes], and the deprecated legacy
  /// instance methods.
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
  /// - IO additionally requires the complete ABI v1 symbol manifest: a native
  ///   library missing a required export throws [StateError] naming it,
  ///   rather than returning capabilities that silently mark it unsupported.
  ///
  /// ## Capabilities
  ///
  /// The returned [YuvCapabilities] is an immutable snapshot computed once
  /// initialization succeeds. On Web it reflects the real WASM exports found
  /// on the loaded module: an operation is supported only when its required
  /// export is present and the module initialized successfully. See
  /// `doc/api-abi-0.4-design.md` section 7.
  static Future<YuvCapabilities> initialize() async {
    return backend_loader.ensureInitialized();
  }

  /// Deprecated alias for [initialize].
  @Deprecated('Use initialize().')
  static Future<YuvCapabilities> ensureInitialized() => initialize();
}
