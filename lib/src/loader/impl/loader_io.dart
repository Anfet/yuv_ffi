import 'dart:ffi' as ffi;
import 'dart:io' show Platform;

import 'package:yuv_ffi/src/functions/bindings/yuv_ffi_bingings.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_abi_v1_symbols.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_operation.dart';
import 'package:yuv_ffi/src/yuv_capabilities.dart';

ffi.DynamicLibrary? _library;
YuvFfiBindings? _ffiBingings;
YuvCapabilities? _capabilities;

/// Opens the platform dynamic library.
///
/// Replaceable so tests can count invocations and simulate failures without
/// deleting or substituting a real binary. Not exported from the package's
/// public API.
typedef YuvLibraryOpener = ffi.DynamicLibrary Function();

YuvLibraryOpener _opener = _openYuvLibrary;

/// Number of times the opener actually ran.
///
/// A successful open is cached, so this is what proves that repeated and
/// concurrent calls do not reopen the library.
int debugOpenCount = 0;

/// Replaces the library opener for a test and returns the previous one.
void debugSetLibraryOpener(YuvLibraryOpener opener) {
  _opener = opener;
}

/// Whether [library] provides [symbol]; defaults to
/// [ffi.DynamicLibrary.providesSymbol].
///
/// Replaceable so a test can exercise [ensureInitialized]'s complete-manifest
/// gate with a fake library that cannot really export `yuv_*_v1` symbols
/// (`ffi.DynamicLibrary.executable()`, used throughout this loader's other
/// tests), without asserting anything about the real native build. Production
/// code never overrides this.
bool Function(ffi.DynamicLibrary library, String symbol) _symbolChecker = (library, symbol) => library.providesSymbol(symbol);

/// Replaces the symbol-presence check [ensureInitialized] uses for its
/// complete-manifest gate.
void debugSetSymbolChecker(bool Function(ffi.DynamicLibrary library, String symbol) checker) {
  _symbolChecker = checker;
}

/// Restores the real opener and symbol checker, and drops every cached
/// handle.
///
/// Clears the library, the bindings built from it and the open counter
/// together, so a later test cannot observe bindings belonging to a library
/// that is no longer installed.
void debugResetLoader() {
  _opener = _openYuvLibrary;
  _symbolChecker = (library, symbol) => library.providesSymbol(symbol);
  _library = null;
  _ffiBingings = null;
  _capabilities = null;
  debugOpenCount = 0;
}

/// Unified backend initialization entrypoint for IO/native platforms.
///
/// Async by contract so it matches the Web API; opening a native dynamic
/// library is itself synchronous.
///
/// A successful open is cached, so repeated and concurrent calls reuse the same
/// library. A failed attempt caches nothing: the next explicit call really
/// retries and may succeed, which is what makes a transient failure (a library
/// that was not deployed yet) recoverable without restarting the process.
///
/// Rethrows the original error. An unsupported platform throws
/// [UnsupportedError]; a library that cannot be opened throws the platform's
/// own FFI error, with its message and stack trace preserved. Native IO
/// initialization additionally requires the complete ABI v1 symbol manifest
/// (`doc/api-abi-0.4-design.md` section 7): a library missing any required
/// `yuv_*_v1` export fails initialization with [StateError] naming the missing
/// symbols, rather than returning capabilities that silently mark them
/// unsupported.
Future<YuvCapabilities> ensureInitialized() async {
  final library = _openIfNeeded();
  final missing = <String>[
    for (final symbol in yuvAbiV1Symbols)
      if (!_symbolChecker(library, symbol)) symbol,
  ];
  if (missing.isNotEmpty) {
    throw StateError(
      'The loaded yuv_ffi native library does not export ${missing.length} of the '
      '${yuvAbiV1Symbols.length} required ABI v1 symbols: ${missing.join(', ')}.',
    );
  }
  final snapshot = YuvCapabilitiesSnapshot(YuvOperation.values);
  _capabilities = snapshot;
  return snapshot;
}

/// The most recently computed [YuvCapabilities], or `null` when
/// [ensureInitialized] has not yet completed successfully.
///
/// Mirrors [library]/[ffiBingings]: a synchronous, per-isolate cache next to
/// the other state this loader already keeps after a successful
/// initialization, so `apply*` call sites can read the current backend's
/// capabilities without threading an async result through every image
/// instance.
YuvCapabilities? get capabilitiesIfInitialized => _capabilities;

/// The loaded dynamic library.
///
/// Opens it on first use when [ensureInitialized] was not called. Calling
/// [ensureInitialized] during startup is still recommended, because it surfaces
/// a missing or unloadable library at a predictable point instead of at the
/// first image operation. On Web the explicit call is mandatory rather than
/// merely recommended.
ffi.DynamicLibrary get library => _openIfNeeded();

/// Generated bindings for [library].
///
/// Cached alongside the library, and dropped with it, so bindings can never
/// outlive the library they were built from.
YuvFfiBindings get ffiBingings => _ffiBingings ??= YuvFfiBindings(library);

ffi.DynamicLibrary _openIfNeeded() {
  final cached = _library;
  if (cached != null) {
    return cached;
  }

  // Assign only after a successful open: leaving `_library` null on failure is
  // what allows the next explicit attempt to retry.
  debugOpenCount++;
  final opened = _opener();
  _library = opened;
  _ffiBingings = null;
  return opened;
}

/// Opens the library by its installed name, never by a build-tree path.
///
/// `native/src/build/libyuv_ffi.*` used to be hardcoded for Linux and macOS.
/// That directory is an artifact of building the CMake target in place: it does
/// not exist in a published package or in an application bundle, so any consumer
/// outside this repository failed at the first FFI call.
///
/// The contract per platform:
/// - Android/Linux load the installed shared object by name, so the dynamic
///   loader resolves it through the app's library search path;
/// - Windows loads `yuv_ffi.dll` the same way;
/// - iOS/macOS link the sources into the pod target, so the symbols are already
///   in the running process and there is no separate file to open.
ffi.DynamicLibrary _openYuvLibrary() {
  if (Platform.isIOS) {
    return ffi.DynamicLibrary.process();
  }
  if (Platform.isMacOS) {
    // In a real macOS app the sources are linked into the pod target, so the
    // symbols are already in the process. A plain Dart VM — `flutter test`, a
    // command-line host — links nothing, and `process()` there resolves to a
    // handle whose first symbol lookup throws "symbol not found". Falling back
    // to the installed dylib keeps both hosts working.
    // Probed by an ABI v1 symbol, named from the shared manifest. It used to
    // probe `yuv420_from_rgba8888`, one of the legacy processing exports
    // YUV-52 removed: had the probe stayed, every macOS host would have fallen
    // through to `open('libyuv_ffi.dylib')`, which in a real app bundle finds
    // no such file and throws instead of using the already-linked symbols.
    final fromProcess = ffi.DynamicLibrary.process();
    if (fromProcess.providesSymbol(yuvSymbolConvertV1)) {
      return fromProcess;
    }
    return ffi.DynamicLibrary.open('libyuv_ffi.dylib');
  }
  if (Platform.isLinux || Platform.isAndroid) {
    return ffi.DynamicLibrary.open('libyuv_ffi.so');
  }
  if (Platform.isWindows) {
    return ffi.DynamicLibrary.open('yuv_ffi.dll');
  }
  throw UnsupportedError('Unsupported platform');
}
