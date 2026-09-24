import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

import 'helpers/reference/test_pattern_reference.dart';

@JS('console.log')
external void _consoleLog(JSString message);

@JS('console.error')
external void _consoleError(JSString message);

const _sourceAssetPath = 'assets/reference/test_pattern_512.png';

/// Test-only YUV-40 probe for F-010. The default variant exercises the
/// suspect case in isolation; `-DYUV40_VARIANT=after-nv21-to-i420` first runs
/// its immediate predecessor from the interrupted matrix.
const _variant = String.fromEnvironment('YUV40_VARIANT', defaultValue: 'isolated');

void _marker(String message) {
  final line = 'YUV-40 MARKER $_variant: $message';
  debugPrint(line);
  _consoleLog(line.toJS);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('F-010 BGRA to NV21 abort boundary', (tester) async {
    expect(kIsWeb, isTrue, reason: 'YUV-40 must run in Chrome.');
    _marker('before ensureInitialized');
    await YuvFfi.initialize();
    _marker('after ensureInitialized');

    final sourcePng = await rootBundle.load(_sourceAssetPath);
    final source = decodePng(Uint8List.view(sourcePng.buffer));
    _marker('after fixture decode ${source.width}x${source.height}');

    // Control: same browser harness, loader, source and BGRA allocation, but
    // a conversion known to return to Dart before the suspect call.
    final control = _bgra(source);
    _marker('control before applyFormat(i420)');
    control.applyFormat(YuvPixelFormat.i420);
    _marker('control after applyFormat(i420) format=${control.format.name} planes=${control.planes.length}');

    if (_variant == 'after-nv21-to-i420') {
      final predecessor = _nv21(source);
      _marker('predecessor before applyFormat(i420)');
      predecessor.applyFormat(YuvPixelFormat.i420);
      _marker('predecessor after applyFormat(i420) format=${predecessor.format.name} planes=${predecessor.planes.length}');
    }

    final candidate = _bgra(source);
    _marker('candidate after BGRA construction yBytes=${candidate.yPlane.bytes.length}');
    _marker('candidate before applyFormat(nv12)');
    try {
      candidate.applyFormat(YuvPixelFormat.nv12);
    } catch (error, stackTrace) {
      final line = 'YUV-40 candidate caught $error\n$stackTrace';
      debugPrint(line);
      _consoleError(line.toJS);
      rethrow;
    }
    _marker(
      'candidate after applyFormat(nv12) format=${candidate.format.name} planes=${candidate.planes.length} yBytes=${candidate.yPlane.bytes.length} uvBytes=${candidate.uPlane.bytes.length}',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}

YuvImage _bgra(RgbaFrame source) =>
    YuvImage.bgra(source.width, source.height, planes: <YuvPlane>[YuvPlane(source.height, source.width * 4, 4, source.toBgra())]);

YuvImage _nv21(RgbaFrame source) {
  final i420 = rgbaToI420(source);
  return YuvImage.nv12(
    source.width,
    source.height,
    planes: <YuvPlane>[
      YuvPlane(source.height, source.width, 1, i420.y),
      YuvPlane((source.height + 1) ~/ 2, ((source.width + 1) ~/ 2) * 2, 2, i420ToNv21Uv(i420).uv!),
    ],
  );
}
