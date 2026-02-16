// Public entry point for the Web WASM loader.
//
// Why conditional export:
// - On Web we expose the real loader implementation that uses JS interop.
// - On non-Web targets we expose a stub that throws UnsupportedError.
//   This keeps imports safe in shared Dart code.
export 'impl/wasm_loader_io.dart'
    if (dart.library.js_interop) 'impl/wasm_loader_web.dart';
