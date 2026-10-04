import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

import 'probe_runner.dart';
import 'probe_seed.dart';

/// One representative public call for a [YuvOperation] at a benchmark size.
///
/// Input construction happens before the timer. Each invocation receives a
/// fresh image because the public `apply*` calls mutate their receiver.
class ProbeScenario {
  const ProbeScenario({required this.operation, required this.name, required this.sourceFormat, required this.invoke});

  final YuvOperation operation;
  final String name;
  final String sourceFormat;
  final Object Function(YuvImage image) invoke;

  PreparedProbeInvocation prepare(int width, int height) {
    final image = _newImage(width, height);
    return PreparedProbeInvocation(call: () => invoke(image), hash: _hash);
  }

  YuvImage _newImage(int width, int height) {
    var seed = 12345 + width * 31 + height;
    int nextByte() {
      seed = probeNextSeed(seed);
      return (seed >> 8) & 0xff;
    }

    return _makePerformanceImage(sourceFormat, width, height, nextByte);
  }

  static String _hash(Object result) {
    if (result is Uint8List) {
      return sha256.convert(result).toString().substring(0, 16);
    }
    final image = result as YuvImage;
    final hash = sha256.convert(image.toBytes()).toString().substring(0, 16);
    return '${image.format.name} ${image.width}x${image.height} $hash';
  }
}

YuvImage _makePerformanceImage(String sourceFormat, int width, int height, int Function() nextByte) {
  final format = switch (sourceFormat) {
    'i420' => YuvPixelFormat.i420,
    'nv12' => YuvPixelFormat.nv12,
    'bgra8888' => YuvPixelFormat.bgra8888,
    _ => throw ArgumentError.value(sourceFormat, 'sourceFormat'),
  };
  final chromaWidth = (width + 1) ~/ 2;
  final chromaHeight = (height + 1) ~/ 2;
  switch (format) {
    case YuvPixelFormat.i420:
      return YuvImage.i420(
        width,
        height,
        planes: [
          YuvPlane(height, width, 1, _fill(height * width, nextByte)),
          YuvPlane(chromaHeight, chromaWidth, 1, _fill(chromaHeight * chromaWidth, nextByte)),
          YuvPlane(chromaHeight, chromaWidth, 1, _fill(chromaHeight * chromaWidth, nextByte)),
        ],
      );
    case YuvPixelFormat.nv12:
      return YuvImage.nv12(
        width,
        height,
        planes: [
          YuvPlane(height, width, 1, _fill(height * width, nextByte)),
          YuvPlane(chromaHeight, chromaWidth * 2, 2, _fill(chromaHeight * chromaWidth * 2, nextByte)),
        ],
      );
    case YuvPixelFormat.bgra8888:
      return YuvImage.bgra(width, height, planes: [YuvPlane(height, width * 4, 4, _fill(height * width * 4, nextByte))]);
  }
}

Uint8List _fill(int count, int Function() nextByte) => Uint8List.fromList(List<int>.generate(count, (_) => nextByte()));

/// Benchmark scenarios cover every public operation once at each target size.
///
/// `convert` uses I420-to-BGRA and `chromaSwap` starts from NV12; the remaining
/// operations use the same deterministic I420 input. This keeps the input and
/// public-call boundary consistent across Windows and Android runs.
const probeScenarios = <ProbeScenario>[
  ProbeScenario(operation: YuvOperation.convert, name: 'i420-to-bgra', sourceFormat: 'i420', invoke: _toBgra),
  ProbeScenario(operation: YuvOperation.blackWhite, name: 'i420-whole-frame', sourceFormat: 'i420', invoke: _blackWhite),
  ProbeScenario(operation: YuvOperation.grayscale, name: 'i420-whole-frame', sourceFormat: 'i420', invoke: _grayscale),
  ProbeScenario(operation: YuvOperation.negate, name: 'i420-whole-frame', sourceFormat: 'i420', invoke: _negate),
  ProbeScenario(operation: YuvOperation.gaussianBlur, name: 'i420-r3-s2', sourceFormat: 'i420', invoke: _gaussian),
  ProbeScenario(operation: YuvOperation.meanBlur, name: 'i420-r2', sourceFormat: 'i420', invoke: _mean),
  ProbeScenario(operation: YuvOperation.boxBlur, name: 'i420-r2', sourceFormat: 'i420', invoke: _box),
  ProbeScenario(operation: YuvOperation.crop, name: 'i420-inset-8', sourceFormat: 'i420', invoke: _crop),
  ProbeScenario(operation: YuvOperation.flipHorizontal, name: 'i420-whole-frame', sourceFormat: 'i420', invoke: _flipHorizontal),
  ProbeScenario(operation: YuvOperation.flipVertical, name: 'i420-whole-frame', sourceFormat: 'i420', invoke: _flipVertical),
  ProbeScenario(operation: YuvOperation.rotate, name: 'i420-90', sourceFormat: 'i420', invoke: _rotate),
  ProbeScenario(operation: YuvOperation.chromaSwap, name: 'nv12-whole-frame', sourceFormat: 'nv12', invoke: _chromaSwap),
];

YuvImage _toBgra(YuvImage image) => image.toBgra();
YuvImage _blackWhite(YuvImage image) => image.applyBlackWhite();
YuvImage _grayscale(YuvImage image) => image.applyGrayscale();
YuvImage _negate(YuvImage image) => image.applyNegate();
YuvImage _gaussian(YuvImage image) => image.applyGaussianBlur(radius: 3, sigma: 2);
YuvImage _mean(YuvImage image) => image.applyMeanBlur(radius: 2);
YuvImage _box(YuvImage image) => image.applyBoxBlur(radius: 2);
YuvImage _crop(YuvImage image) => image.applyCrop(ui.Rect.fromLTWH(8, 8, (image.width - 16).toDouble(), (image.height - 16).toDouble()));
YuvImage _flipHorizontal(YuvImage image) => image.applyFlipHorizontal();
YuvImage _flipVertical(YuvImage image) => image.applyFlipVertical();
YuvImage _rotate(YuvImage image) => image.applyRotation(YuvImageRotation.rotation90);
YuvImage _chromaSwap(YuvImage image) => image.applyChromaSwap();
