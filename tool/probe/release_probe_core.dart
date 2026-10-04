import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

import '../../test/probe/cases.dart';

const releaseProbeCaseCount = 1188;

/// Result of the release-only native smoke and golden probe execution.
class ReleaseProbeResult {
  const ReleaseProbeResult({required this.smoke, required this.probe, required this.caseCount});

  final String smoke;
  final String probe;
  final int caseCount;
}

/// Runs the release smoke and every exact golden case without test frameworks.
///
/// [goldenDocument] is the contents of the bundled probe golden asset.
Future<ReleaseProbeResult> runReleaseProbe(String goldenDocument) async {
  if (probeCaseIds.length != releaseProbeCaseCount) {
    throw StateError('Expected $releaseProbeCaseCount probe cases, found ${probeCaseIds.length}.');
  }

  await YuvFfi.initialize();
  _runRuntimeSmoke();

  final golden = _decodeGolden(goldenDocument);
  final expectedGoldenEntries = releaseProbeCaseCount + _probeInputIds.length;
  if (golden.length != expectedGoldenEntries) {
    throw StateError('Expected $expectedGoldenEntries golden entries, found ${golden.length}.');
  }

  final inputMismatches = <String>[];
  for (final id in _probeInputIds) {
    final expected = golden[id];
    if (expected is! String) {
      inputMismatches.add('$id: missing input golden');
      continue;
    }
    final actual = _runProbeInput(id);
    if (actual != expected) {
      inputMismatches.add('$id: expected $expected, got $actual');
    }
  }
  _throwIfMismatches('input', inputMismatches);

  final mismatches = <String>[];
  for (final id in probeCaseIds) {
    final expected = golden[id];
    if (expected is! String) {
      mismatches.add('$id: missing golden');
      continue;
    }
    final actual = _runProbeCase(ReleaseProbeCase(id));
    if (actual != expected) {
      mismatches.add('$id: expected $expected, got $actual');
    }
  }
  _throwIfMismatches('operation', mismatches);

  return const ReleaseProbeResult(smoke: 'PASS', probe: 'PASS', caseCount: releaseProbeCaseCount);
}

Map<String, dynamic> _decodeGolden(String document) {
  final decoded = jsonDecode(document);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Probe golden must be a JSON object.');
  }
  if (decoded['schema'] != 1) {
    throw FormatException('Unsupported probe golden schema: ${decoded['schema']}.');
  }
  final cases = decoded['cases'];
  if (cases is! Map<String, dynamic>) {
    throw const FormatException('Probe golden cases must be a JSON object.');
  }
  return cases;
}

void _throwIfMismatches(String kind, List<String> mismatches) {
  if (mismatches.isEmpty) {
    return;
  }
  throw StateError('$kind golden mismatches: ${mismatches.length}\n${mismatches.take(20).join('\n')}');
}

void _runRuntimeSmoke() {
  final image = YuvImage.i420(
    2,
    2,
    planes: [
      YuvPlane(2, 2, 1, Uint8List.fromList([16, 32, 48, 64])),
      YuvPlane(1, 1, 1, Uint8List.fromList([96])),
      YuvPlane(1, 1, 1, Uint8List.fromList([160])),
    ],
    layout: YuvPlaneLayout.preserve,
  );
  final output = image.applyGrayscale();
  if (output.format != YuvPixelFormat.i420 || output.width != 2 || output.height != 2 || output.toBytes().isEmpty) {
    throw StateError('Native runtime smoke returned an invalid I420 image.');
  }
}

class ReleaseProbeCase {
  const ReleaseProbeCase(this.id);

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

final _probeInputIds = probeCaseIds.map((id) => id.split(' ').take(3).join(' ')).toSet().map((id) => 'input $id').toList(growable: false);

int _nextSeed(int seed) {
  const aHi = 16838;
  const aLo = 20077;
  final hi = (seed * aHi) % 32768;
  return (seed * aLo + hi * 65536 + 12345) % 2147483648;
}

Uint8List _fill(int count, int Function() nextByte) => Uint8List.fromList(List<int>.generate(count, (_) => nextByte()));

YuvImage _makeImage(ReleaseProbeCase probeCase, int width, int height, int Function() nextByte) {
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

Object _applyOperation(ReleaseProbeCase probeCase, YuvImage image, int Function() nextByte) {
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

String _runProbeCase(ReleaseProbeCase probeCase) {
  final size = probeCase.size;
  var seed = 12345 + size.$1 * 31 + size.$2;
  int nextByte() {
    seed = _nextSeed(seed);
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

String _runProbeInput(String id) {
  final parts = id.split(' ');
  final probeCase = ReleaseProbeCase('${parts[1]} ${parts[2]} ${parts[3]} input');
  final size = probeCase.size;
  var seed = 12345 + size.$1 * 31 + size.$2;
  int nextByte() {
    seed = _nextSeed(seed);
    return (seed >> 8) & 0xff;
  }

  final image = _makeImage(probeCase, size.$1, size.$2, nextByte);
  return sha256.convert(image.toBytes()).toString().substring(0, 16);
}
