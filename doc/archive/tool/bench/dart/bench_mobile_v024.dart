import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

import 'bench_flip_images.dart' as flip_images;
import 'bench_matrix_core.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const metadata = MatrixMetadata(
    platform: 'android',
    machine: 'Pixel_3_8B1X11QLW',
    sha: String.fromEnvironment('BENCH_SHA'),
    tree: String.fromEnvironment('BENCH_TREE'),
    compiler: 'Flutter AOT',
    flags: 'release',
  );
  final rows = await runMeas02Matrix(_LegacyAdapter(), metadata);
  for (final row in rows) {
    developer.log('YUV_BENCH_CSV:$row', name: 'yuv_bench');
  }
  runApp(Directionality(textDirection: TextDirection.ltr, child: Text(rows.join('\n'))));
}

final class _LegacyAdapter implements MatrixAdapter {
  @override
  String get version => 'v024';

  @override
  Future<void> initialize() => YuvFfi.ensureInitialized();

  @override
  Object create(BenchScenario scenario, BenchInput input) => flip_images.makeImageForFlip(input);

  @override
  Object flipVertical(Object image) => (image as YuvImage).flipVertically();

  @override
  Uint8List packActiveSamples(Object result) => flip_images.packFlipActiveSamples(result);
}
