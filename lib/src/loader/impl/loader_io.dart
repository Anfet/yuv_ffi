import 'dart:ffi' as ffi;
import 'dart:io' show Platform;

import 'package:yuv_ffi/src/functions/bindings/yuv_ffi_bingings.dart';

ffi.DynamicLibrary? _library;
YuvFfiBindings? _ffiBingings;

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

/// Restores the real opener and drops every cached handle.
///
/// Clears the library, the bindings built from it and the open counter
/// together, so a later test cannot observe bindings belonging to a library
/// that is no longer installed.
void debugResetLoader() {
  _opener = _openYuvLibrary;
  _library = null;
  _ffiBingings = null;
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
/// own FFI error, with its message and stack trace preserved.
Future<void> ensureInitialized() async {
  _openIfNeeded();
}

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
  if (Platform.isMacOS || Platform.isIOS) {
    return ffi.DynamicLibrary.process();
  }
  if (Platform.isLinux || Platform.isAndroid) {
    return ffi.DynamicLibrary.open('libyuv_ffi.so');
  }
  if (Platform.isWindows) {
    return ffi.DynamicLibrary.open('yuv_ffi.dll');
  }
  throw UnsupportedError('Unsupported platform');
}
