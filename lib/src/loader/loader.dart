// Public entrypoint for the native FFI loader surface.
//
// Platform-specific implementations live under `impl/`:
// - `loader_io.dart` for native/mobile/desktop.
// - `loader_web.dart` for Web (unsupported placeholders).
export 'impl/loader_io.dart'
    if (dart.library.js_interop) 'impl/loader_web.dart';
