import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

import 'bench_common.dart';
import 'bench_images.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    exit(await runBench(args, _AbiAdapter()));
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    exit(2);
  }
}

final class _AbiAdapter implements BenchAdapter {
  @override
  String get version => 'abi_v1';

  @override
  Future<void> initialize() async {
    await YuvFfi.initialize();
  }

  @override
  Object create(Scenario scenario, InputFrame input) => makeImage(scenario, input);

  @override
  Object call(Scenario scenario, Object image, InputFrame input) {
    final source = image as YuvImage;
    switch (scenario.operation) {
      case 'CVT':
        if (scenario.sourceFormat == 'RGBA') {
          final format = switch (scenario.destinationFormat) {
            'I420' => YuvPixelFormat.i420,
            'NV12' => YuvPixelFormat.nv12,
            'BGRA' => YuvPixelFormat.bgra8888,
            _ => throw ArgumentError.value(scenario.destinationFormat),
          };
          return YuvImage.fromRgbaBytes(input.planes.single, width: input.width, height: input.height, format: format);
        }
        return switch (scenario.destinationFormat) {
          'I420' => source.toI420(),
          'NV12' => source.toNv12(),
          'BGRA' => scenario.sourceFormat == 'BGRA' ? source.toBgra() : source.toBgraBytes(),
          _ => throw ArgumentError.value(scenario.destinationFormat),
        };
      case 'FLIP':
        return scenario.parts[2] == 'H' ? source.applyFlipHorizontal() : source.applyFlipVertical();
      case 'ROT':
        return source.rotated(rotation(scenario));
      case 'CROP':
        return source.cropped(crop(scenario, input.width, input.height));
      case 'GRAY':
        return source.applyGrayscale();
      case 'BW':
        return source.applyBlackWhite();
      case 'NEG':
        return source.applyNegate();
      case 'SWAP':
        return source.applyChromaSwap();
      case 'BOX':
        return source.applyBoxBlur(radius: scenario.radius, region: scenario.roi ? region(input.width, input.height) : null);
      case 'MEAN':
        return source.applyMeanBlur(radius: scenario.radius, region: scenario.roi ? region(input.width, input.height) : null);
      case 'GAUSS':
        return source.applyGaussianBlur(radius: scenario.radius, sigma: scenario.sigma.toDouble());
      default:
        throw ArgumentError.value(scenario.operation);
    }
  }

  @override
  Uint8List bytes(Object result) => outputBytes(result);
}
