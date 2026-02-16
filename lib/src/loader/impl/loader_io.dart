import 'dart:ffi' as ffi;
import 'dart:io' show Platform;

import 'package:yuv_ffi/src/functions/bindings/yuv_ffi_bingings.dart';

ffi.DynamicLibrary? _library;

/// Unified backend initialization entrypoint for IO/native platforms.
///
/// This function is async by contract (to match Web API), but initialization
/// itself is synchronous for native dynamic libraries.
Future<void> ensureInitialized() async {
  _library ??= _openYuvLibrary();
}

ffi.DynamicLibrary get library {
  return _library ?? _openYuvLibrary();
}

YuvFfiBindings? _ffiBingings;

YuvFfiBindings get ffiBingings => _ffiBingings ?? YuvFfiBindings(library);

ffi.DynamicLibrary _openYuvLibrary() {
  _library = Platform.isMacOS
      ? ffi.DynamicLibrary.open('native/src/build/libyuv_ffi.dylib')
      : Platform.isLinux
          ? ffi.DynamicLibrary.open('native/src/build/libyuv_ffi.so')
          : Platform.isWindows
              ? ffi.DynamicLibrary.open('yuv_ffi.dll')
              : Platform.isAndroid
                  ? ffi.DynamicLibrary.open('libyuv_ffi.so')
                  : Platform.isIOS
                      ? ffi.DynamicLibrary.process()
                      : null;

  if (_library == null) {
    throw UnsupportedError('Unsupported platform');
  }
  return _library!;
}
