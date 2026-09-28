import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

import 'cases.dart';
import 'probe_seed.dart';

Map<String, dynamic> decodeProbeGolden(String document) {
  final decoded = jsonDecode(document) as Map<String, dynamic>;
  if (decoded['schema'] != 1) {
    throw FormatException('Unsupported probe golden schema: ${decoded['schema']}');
  }
  return decoded['cases'] as Map<String, dynamic>;
}

class ProbeCase {
  const ProbeCase(this.id);

  final String id;

  List<String> get _parts => id.split(' ');
  String get format => _parts[0];
  (int, int) get size {
    final dimensions = _parts[1].split('x');
    return (int.parse(dimensions[0]), int.parse(dimensions[1]));
  }

  String get layout => _parts[2];
  String get operation => _parts[3];
}

final probeInputIds = probeCaseIds.map((id) => id.split(' ').take(3).join(' ')).toSet().map((id) => 'input $id').toList(growable: false);

YuvOperation operationForCase(ProbeCase probeCase) => switch (probeCase.operation) {
  'gray' => YuvOperation.grayscale,
  'bw' => YuvOperation.blackWhite,
  'neg' => YuvOperation.negate,
  'gauss' => YuvOperation.gaussianBlur,
  'box' || 'boxRoi' => YuvOperation.boxBlur,
  'mean' || 'meanRoi' => YuvOperation.meanBlur,
  'crop' || 'cropEven' || 'cropped' => YuvOperation.crop,
  'flipH' => YuvOperation.flipHorizontal,
  'flipV' => YuvOperation.flipVertical,
  'r90' || 'r180' || 'r270' => YuvOperation.rotate,
  'toI420' || 'toNv12' || 'toBgra' || 'bgraBytes' || 'rgbaIn' => YuvOperation.convert,
  'swap' => YuvOperation.chromaSwap,
  _ => throw ArgumentError.value(probeCase.operation, 'operation'),
};

Uint8List _fill(int count, int Function() nextByte) => Uint8List.fromList(List<int>.generate(count, (_) => nextByte()));

YuvImage _makeImage(ProbeCase probeCase, int width, int height, int Function() nextByte) {
  final format = switch (probeCase.format) {
    'i420' => YuvPixelFormat.i420,
    'nv12' => YuvPixelFormat.nv12,
    'bgra8888' => YuvPixelFormat.bgra8888,
    _ => throw ArgumentError.value(probeCase.format, 'format'),
  };
  final chromaWidth = (width + 1) ~/ 2;
  final chromaHeight = (height + 1) ~/ 2;
  final padding = probeCase.layout == 'padded' ? 7 : 0;
  switch (format) {
    case YuvPixelFormat.i420:
      final pixelStride = probeCase.layout == 'gap' ? 2 : 1;
      final yRowStride = width * pixelStride + padding;
      final uvRowStride = chromaWidth * pixelStride + padding;
      return YuvImage.i420(
        width,
        height,
        yPixelStride: pixelStride,
        uvPixelStride: pixelStride,
        planes: [
          YuvPlane(height, yRowStride, pixelStride, _fill(height * yRowStride, nextByte)),
          YuvPlane(chromaHeight, uvRowStride, pixelStride, _fill(chromaHeight * uvRowStride, nextByte)),
          YuvPlane(chromaHeight, uvRowStride, pixelStride, _fill(chromaHeight * uvRowStride, nextByte)),
        ],
        layout: YuvPlaneLayout.preserve,
      );
    case YuvPixelFormat.nv12:
      final pixelStride = probeCase.layout == 'gap' ? 3 : 2;
      final yRowStride = width + padding;
      final uvRowStride = (chromaWidth - 1) * pixelStride + 2 + padding;
      return YuvImage.nv12(
        width,
        height,
        uvPixelStride: pixelStride,
        planes: [
          YuvPlane(height, yRowStride, 1, _fill(height * yRowStride, nextByte)),
          YuvPlane(chromaHeight, uvRowStride, pixelStride, _fill(chromaHeight * uvRowStride, nextByte)),
        ],
        layout: YuvPlaneLayout.preserve,
      );
    case YuvPixelFormat.bgra8888:
      final pixelStride = probeCase.layout == 'gap' ? 5 : 4;
      final rowStride = (width - 1) * pixelStride + 4 + padding;
      return YuvImage.bgra(
        width,
        height,
        planes: [YuvPlane(height, rowStride, pixelStride, _fill(height * rowStride, nextByte))],
        layout: YuvPlaneLayout.preserve,
      );
  }
}

Object _applyOperation(ProbeCase probeCase, YuvImage image, int Function() nextByte) {
  final width = image.width;
  final height = image.height;
  return switch (probeCase.operation) {
    'gray' => image.applyGrayscale(),
    'bw' => image.applyBlackWhite(),
    'neg' => image.applyNegate(),
    'gauss' => image.applyGaussianBlur(radius: 3, sigma: 2),
    'box' => image.applyBoxBlur(radius: 2),
    'mean' => image.applyMeanBlur(radius: 2),
    'boxRoi' => image.applyBoxBlur(radius: 2, region: ui.Rect.fromLTWH(1, 1, width / 2, height / 2)),
    'meanRoi' => image.applyMeanBlur(radius: 3, region: ui.Rect.fromLTWH(1, 0, width / 2 + 1, height / 2 + 1)),
    'crop' => image.applyCrop(ui.Rect.fromLTWH(1, 1, (width - 1).toDouble(), (height - 1).toDouble())),
    'cropEven' => image.applyCrop(ui.Rect.fromLTWH(0, 0, (width / 2).ceilToDouble(), (height / 2).ceilToDouble())),
    'cropped' => image.cropped(ui.Rect.fromLTWH(1, 0, (width / 2).ceilToDouble(), height.toDouble())),
    'flipH' => image.applyFlipHorizontal(),
    'flipV' => image.applyFlipVertical(),
    'r90' => image.applyRotation(YuvImageRotation.rotation90),
    'r180' => image.applyRotation(YuvImageRotation.rotation180),
    'r270' => image.applyRotation(YuvImageRotation.rotation270),
    'toI420' => image.toI420(),
    'toNv12' => image.toNv12(),
    'toBgra' => image.toBgra(),
    'bgraBytes' => image.toBgraBytes(),
    'rgbaIn' => image.applyRgbaBytes(_fill(width * height * 4, nextByte)),
    'swap' => image.format == YuvPixelFormat.nv12 ? image.applyChromaSwap() : image,
    _ => throw ArgumentError.value(probeCase.operation, 'operation'),
  };
}

String runProbeCase(ProbeCase probeCase) {
  final size = probeCase.size;
  var seed = 12345 + size.$1 * 31 + size.$2;
  int nextByte() {
    seed = probeNextSeed(seed);
    return (seed >> 8) & 0xff;
  }

  final image = _makeImage(probeCase, size.$1, size.$2, nextByte);
  try {
    final result = _applyOperation(probeCase, image, nextByte);
    if (result is Uint8List) {
      return sha256.convert(result).toString().substring(0, 16);
    }
    final output = result as YuvImage;
    final outputHash = sha256.convert(output.toBytes()).toString().substring(0, 16);
    final sourceHash = sha256.convert(image.toBytes()).toString().substring(0, 16);
    return '${output.format.name} ${output.width}x${output.height} $outputHash src=$sourceHash';
  } catch (error) {
    return 'ERR ${error.runtimeType}';
  }
}

String runProbeInput(String id) {
  final parts = id.split(' ');
  final probeCase = ProbeCase('${parts[1]} ${parts[2]} ${parts[3]} input');
  final size = probeCase.size;
  var seed = 12345 + size.$1 * 31 + size.$2;
  int nextByte() {
    seed = probeNextSeed(seed);
    return (seed >> 8) & 0xff;
  }

  final image = _makeImage(probeCase, size.$1, size.$2, nextByte);
  return sha256.convert(image.toBytes()).toString().substring(0, 16);
}

List<String> probeInputMismatches(Map<String, dynamic> golden) {
  final mismatches = <String>[];
  for (final id in probeInputIds) {
    final expected = golden[id];
    if (expected == null) {
      mismatches.add('$id: missing input golden');
      continue;
    }
    final actual = runProbeInput(id);
    if (actual != expected) {
      mismatches.add('$id: expected input $expected, got $actual');
    }
  }
  return mismatches;
}

Future<List<String>> probeMismatches(Map<String, dynamic> golden, {Iterable<String>? caseIds}) async {
  await YuvFfi.initialize();
  final mismatches = <String>[];
  for (final id in caseIds ?? probeCaseIds) {
    final expected = golden[id];
    if (expected == null) {
      mismatches.add('$id: missing golden');
      continue;
    }
    final actual = runProbeCase(ProbeCase(id));
    if (actual != expected) {
      mismatches.add('$id: expected $expected, got $actual');
    }
  }
  return mismatches;
}

void expectProbeMismatchesEmpty(List<String> mismatches) {
  expect(mismatches, isEmpty, reason: '${mismatches.length} probe mismatches:\n${mismatches.take(20).join('\n')}');
}
