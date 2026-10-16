// Public entrypoint for the native FFI loader surface.
//
// Platform-specific implementations live under `impl/`:
// - `loader_io.dart` for native/mobile/desktop.
// - `loader_web.dart` for Web (unsupported placeholders).
// IO retries do not guarantee that the operating-system loader unloads or
// reloads a library file that it already loaded.
export 'impl/loader_io.dart' if (dart.library.js_interop) 'impl/loader_web.dart';
