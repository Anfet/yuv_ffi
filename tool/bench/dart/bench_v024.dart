import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

import 'bench_common.dart';
import 'bench_images.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    exit(await runBench(args, _LegacyAdapter()));
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    exit(2);
  }
}

final class _LegacyAdapter implements BenchAdapter {
  @override
  String get version => 'v024';

  @override
  Future<void> initialize() => YuvFfi.ensureInitialized();

  @override
  Object create(Scenario scenario, InputFrame input) => makeImage(scenario, input);

  @override
  Object call(Scenario scenario, Object image, InputFrame input) {
    final source = image as YuvImage;
    switch (scenario.operation) {
      case 'CVT':
        if (scenario.sourceFormat == 'RGBA') {
          source.fromRgba8888(input.planes.single);
          return source;
        }
        if (scenario.sourceFormat == scenario.destinationFormat) return source.copy();
        return switch (scenario.destinationFormat) {
          'I420' => source.toYuvI420(),
          'NV12' => source.toYuvNv21(),
          'BGRA' => source.toBgra8888(),
          _ => throw ArgumentError.value(scenario.destinationFormat),
        };
      case 'FLIP':
        return scenario.parts[2] == 'H' ? source.flipHorizontally() : source.flipVertically();
      case 'ROT':
        return scenario.degrees == 0 ? source.copy() : source.rotate(rotation(scenario));
      case 'CROP':
        return source.crop(crop(scenario, input.width, input.height));
      case 'GRAY':
        return source.grayscale();
      case 'BW':
        return source.blackwhite();
      case 'NEG':
        return source.negate();
      case 'SWAP':
        return source.swapNv();
      case 'BOX':
        return source.boxBlur(radius: scenario.radius, rect: scenario.roi ? region(input.width, input.height) : null);
      case 'MEAN':
        return source.meanBlur(radius: scenario.radius, rect: scenario.roi ? region(input.width, input.height) : null);
      case 'GAUSS':
        return source.gaussianBlur(radius: scenario.radius, sigma: scenario.sigma);
      default:
        throw ArgumentError.value(scenario.operation);
    }
  }

  @override
  Uint8List bytes(Object result) => outputBytes(result);
}
