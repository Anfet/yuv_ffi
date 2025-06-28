import 'dart:ffi' as ffi;
import 'dart:io' show Platform;

import 'package:yuv_ffi/src/yuv_ffi_bingings.dart';

ffi.DynamicLibrary? _library;

ffi.DynamicLibrary get library => _library ?? openYuvLibrary();

YuvFfiBindings? _ffiBingings;

YuvFfiBindings get ffiBingings => _ffiBingings ?? YuvFfiBindings(library);

ffi.DynamicLibrary openYuvLibrary() {
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
