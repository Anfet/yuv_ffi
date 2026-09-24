// ignore_for_file: avoid_web_libraries_in_flutter

import 'package:yuv_ffi/src/web/impl/js_util_compat_web.dart' as js_util;
import 'package:yuv_ffi/src/yuv/shared/yuv_abi_v1_symbols.dart';

/// The Web side of the ABI v1 symbol dispatch: how the Web backend names and
/// resolves each of the eleven `yuv_*_v1` symbols against a loaded WASM module.
///
/// This is the fourth source the symbol-manifest gate compares (YUV-28): the C
/// header declares the symbols, `ffigen.yaml` allows them into the native
/// bindings, `tool/wasm/build_wasm.sh` exports them from the WASM build, and
/// this file is what Web dispatch actually asks the module for. Every name comes
/// from [yuvAbiV1Symbols] rather than being spelled out again here, so the Web
/// dispatch cannot drift onto a different spelling than the native runner uses.
///
/// Since YUV-51 the Web backend's public operations run entirely on these
/// symbols, staged by `abi/yuv_abi_v1_web_runner.dart`. What this class
/// guarantees is that the symbol a Web operation reaches for is the same one
/// the header declares and the build exports -- and that a symbol missing from
/// the module is reported by name before the call, instead of failing as an
/// opaque JS error deep inside a `ccall`. Running on ABI v1 does not make Web a
/// feature-complete peer of the native backend; it remains a partial WASM
/// backend.
abstract final class YuvAbiV1WebDispatch {
  /// Emscripten prefixes an exported C function with an underscore.
  static const String exportPrefix = '_';

  /// The exported-function name [symbol] has inside the WASM module.
  static String exportedNameOf(String symbol) => '$exportPrefix$symbol';

  /// Every ABI v1 symbol's exported WASM name, in manifest order.
  static List<String> get exportedNames => [for (final symbol in yuvAbiV1Symbols) exportedNameOf(symbol)];

  /// Whether [rawModule] exports [symbol].
  static bool moduleExports(Object rawModule, String symbol) => js_util.hasProperty(rawModule, exportedNameOf(symbol));

  /// The ABI v1 symbols [rawModule] does not export.
  ///
  /// An empty result means the loaded module carries the whole ABI v1 surface.
  /// A non-empty one names exactly what is missing, which is the difference
  /// between a diagnosable partial build and an opaque `ccall` failure.
  static List<String> missingFrom(Object rawModule) => [
    for (final symbol in yuvAbiV1Symbols)
      if (!moduleExports(rawModule, symbol)) symbol,
  ];

  /// Throws [StateError] naming every ABI v1 symbol [rawModule] is missing.
  ///
  /// Called before an ABI v1 Web operation so a partially exported module is
  /// rejected up front, with the symbol names in the message, rather than
  /// surfacing later as a failure inside the WASM call itself.
  static void requireComplete(Object rawModule) {
    final missing = missingFrom(rawModule);
    if (missing.isEmpty) {
      return;
    }
    throw StateError(
      'The loaded YUV WASM module does not export ${missing.length} of the '
      '${yuvAbiV1Symbols.length} ABI v1 symbols: ${missing.join(', ')}. '
      'Rebuild it with tool/wasm/build_wasm.sh, whose EXPORTED_FUNCTIONS list '
      'must name every symbol in src/yuv/abi/h/yuv_ops_v1.h.',
    );
  }

  /// Invokes [symbol] on [rawModule] through Emscripten's `ccall`.
  ///
  /// [argTypes] and [args] are passed straight through; ABI v1 takes pointers
  /// only, so every entry is Emscripten's `'number'`. The returned `YuvStatus`
  /// is handed back as an `int` for the caller to map -- this layer performs no
  /// status interpretation of its own, exactly as the native runner separates
  /// dispatch from status mapping.
  static int call(Object rawModule, String symbol, {required List<String> argTypes, required List<Object?> args}) {
    if (!moduleExports(rawModule, symbol)) {
      throw StateError('The loaded YUV WASM module does not export the ABI v1 symbol $symbol.');
    }
    final result = js_util.callMethod<Object?>(rawModule, 'ccall', <Object?>[symbol, 'number', argTypes, args]);
    if (result is num) {
      return result.toInt();
    }
    throw StateError('ABI v1 symbol $symbol returned ${result.runtimeType} instead of a YuvStatus number.');
  }
}
