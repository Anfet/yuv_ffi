// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

import 'bench_flip_images.dart' as flip_images;
import 'bench_matrix_core.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const metadata = MatrixMetadata(
    platform: 'web',
    machine: 'Chrome',
    sha: String.fromEnvironment('BENCH_SHA'),
    tree: String.fromEnvironment('BENCH_TREE'),
    compiler: 'Flutter web JS',
    flags: 'release;wasm-c-backend',
  );
  final rows = await runMeas02Matrix(_WebAbiV1Adapter(), metadata);
  for (var index = 0; index < rows.length; index++) {
    document.body!.append(
      PreElement()
        ..className = 'bench-result'
        ..id = 'bench-result-$index'
        ..text = rows[index],
    );
  }
  document.body!.append(
    DivElement()
      ..id = 'bench-complete'
      ..text = '${rows.length}',
  );
  runApp(const SizedBox.shrink());
}

final class _WebAbiV1Adapter implements MatrixAdapter {
  @override
  String get version => 'abi_v1';

  @override
  Future<void> initialize() => YuvFfi.initialize();

  @override
  Object create(BenchScenario scenario, BenchInput input) => flip_images.makeImageForFlip(input);

  @override
  Object flipVertical(Object image) => (image as YuvImage).applyFlipVertical();

  @override
  Uint8List packActiveSamples(Object result) => flip_images.packFlipActiveSamples(result);
}
