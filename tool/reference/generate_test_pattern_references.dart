/// Generates the versioned, backend-independent YUV-10 reference fixture.
///
/// Usage:
///   dart run tool/reference/generate_test_pattern_references.dart
///   dart run tool/reference/generate_test_pattern_references.dart --check
///
/// This tool intentionally imports only pure-Dart packages and the reference
/// helper. In particular, it must never import `package:yuv_ffi` or load FFI /
/// WASM symbols: it is the oracle those backends are measured against.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../test/helpers/reference/test_pattern_reference.dart';

const _sourcePath = 'test/assets/test_pattern_512.png';
const _referenceDirectory = 'test/reference/test_pattern_512';
const _artifactDirectory = '$_referenceDirectory/artifacts';
const _manifestPath = '$_referenceDirectory/manifest.json';

Future<void> main(List<String> arguments) async {
  if (arguments.any((argument) => argument != '--check')) {
    stderr.writeln('Usage: dart run tool/reference/generate_test_pattern_references.dart [--check]');
    exitCode = 64;
    return;
  }

  final check = arguments.contains('--check');
  final sourceBytes = await File(_sourcePath).readAsBytes();
  final source = decodePng(sourceBytes);
  if (source.width != referenceWidth || source.height != referenceHeight) {
    throw StateError('Expected ${referenceWidth}x$referenceHeight PNG, got ${source.width}x${source.height}.');
  }

  final i420 = rgbaToI420(source);
  final nv21 = i420ToNv21Uv(i420);
  final frames = _frames(source, i420, nv21);
  final artifacts = <String, Uint8List>{
    for (final entry in frames.entries) entry.key: encodePng(entry.value),
    'source_bgra8888.bin': source.toBgra(),
    'source_i420.yuv': _join(i420.planes),
    'source_nv21_uv.yuv': _join(nv21.planes),
    'blank_bgra8888.bin': Uint8List(source.width * source.height * 4),
    'blank_i420.yuv': Uint8List(_join(i420.planes).length),
    'blank_nv21_uv.yuv': Uint8List(_join(nv21.planes).length),
  };
  final manifest = _manifest(sourceBytes, source, i420, nv21, frames, artifacts);
  final expectedFiles = <String, Uint8List>{
    for (final entry in artifacts.entries) '$_artifactDirectory/${entry.key}': entry.value,
    _manifestPath: Uint8List.fromList(const JsonEncoder.withIndent('  ').convert(manifest).codeUnits + <int>[10]),
  };

  final mismatches = <String>[];
  for (final entry in expectedFiles.entries) {
    final file = File(entry.key);
    if (!await file.exists() || !_sameBytes(await file.readAsBytes(), entry.value)) {
      mismatches.add(entry.key);
      if (!check) {
        await file.parent.create(recursive: true);
        await file.writeAsBytes(entry.value, flush: true);
      }
    }
  }
  final artifactDirectory = Directory(_artifactDirectory);
  if (await artifactDirectory.exists()) {
    final expectedArtifactNames = artifacts.keys.toSet();
    await for (final entity in artifactDirectory.list(recursive: true)) {
      if (entity is File && !expectedArtifactNames.contains(entity.uri.pathSegments.last)) {
        mismatches.add('unexpected ${entity.path}');
      }
    }
  }

  if (mismatches.isNotEmpty) {
    final action = check ? 'is out of date' : 'was generated';
    stdout.writeln('Reference fixture $action:');
    for (final path in mismatches) {
      stdout.writeln('  $path');
    }
    if (check) {
      exitCode = 1;
    }
  } else {
    stdout.writeln('Reference fixture is byte-identical.');
  }
}

Map<String, RgbaFrame> _frames(RgbaFrame source, Yuv420Frame i420, Yuv420Frame nv21) {
  const cropLeft = 64;
  const cropTop = 96;
  const cropWidth = 256;
  const cropHeight = 320;
  const rectLeft = 32;
  const rectTop = 32;
  const rectWidth = 256;
  const rectHeight = 256;

  final swappedUv = Uint8List.fromList(nv21.uv!);
  for (var index = 0; index < swappedUv.length; index += 2) {
    final first = swappedUv[index];
    swappedUv[index] = swappedUv[index + 1];
    swappedUv[index + 1] = first;
  }
  final swappedNv21 = Yuv420Frame.nv21Uv(nv21.width, nv21.height, Uint8List.fromList(nv21.y), swappedUv);
  return <String, RgbaFrame>{
    'original.png': source,
    'i420_decoded.png': i420.decode(),
    'nv21_uv_decoded.png': nv21.decode(),
    'swap_nv_once.png': swappedNv21.decode(),
    'crop_inner.png': source.crop(cropLeft, cropTop, cropWidth, cropHeight),
    'crop_1x1.png': source.crop(0, 0, 1, 1),
    'crop_3x5.png': source.crop(0, 0, 3, 5),
    'crop_127x255.png': source.crop(0, 0, 127, 255),
    'rotate_90.png': source.rotate90(),
    'rotate_180.png': source.rotate180(),
    'rotate_270.png': source.rotate270(),
    'flip_horizontal.png': source.flipHorizontally(),
    'flip_vertical.png': source.flipVertically(),
    'grayscale.png': source.grayscale(),
    'blackwhite.png': source.blackwhite(),
    'negate.png': source.negate(),
    'gaussian_default.png': source.gaussianBlur(radius: 2, sigma: 2),
    'gaussian_r3_s2.png': source.gaussianBlur(radius: 3, sigma: 2),
    'box_default.png': source.boxBlur(radius: 10),
    'box_full.png': source.boxBlur(radius: 5),
    'box_rect.png': source.boxBlur(
      radius: 5,
      left: rectLeft,
      top: rectTop,
      rectWidth: rectWidth,
      rectHeight: rectHeight,
    ),
    'mean_default.png': source.meanBlur(radius: 2),
    'mean_full.png': source.meanBlur(radius: 5),
    'mean_rect.png': source.meanBlur(
      radius: 5,
      left: rectLeft,
      top: rectTop,
      rectWidth: rectWidth,
      rectHeight: rectHeight,
    ),
  };
}

Map<String, Object> _manifest(
  Uint8List sourcePng,
  RgbaFrame source,
  Yuv420Frame i420,
  Yuv420Frame nv21,
  Map<String, RgbaFrame> frames,
  Map<String, Uint8List> artifacts,
) {
  final bgra = source.toBgra();
  final sourceFormatMetadata = <String, Map<String, Object>>{
    'bgra8888': bgraPlaneMetadata(bgra, source.width, source.height, layout: 'tight'),
    'bgra8888-padded': bgraPlaneMetadata(bgra, source.width, source.height, layout: 'padded'),
    'i420': planeMetadata(i420, layout: 'tight'),
    'i420-padded': planeMetadata(i420, layout: 'padded'),
    'nv21': planeMetadata(nv21, layout: 'tight'),
    'nv21-padded': planeMetadata(nv21, layout: 'padded'),
  };
  final cases = _matrix(source, frames);
  return <String, Object>{
    'schemaVersion': 1,
    'fixture': 'test_pattern_512',
    'generator': <String, Object>{
      'path': 'tool/reference/generate_test_pattern_references.dart',
      'independence': 'pure Dart; no package:yuv_ffi, FFI, native symbols, or WASM imports',
      'updatePolicy': 'Fixtures change only through an explicit generator run and manifest/artifact diff review.',
    },
    'source': <String, Object>{
      'path': _sourcePath,
      'sha256': sha256Hex(sourcePng),
      'decoded': <String, Object>{
        'width': source.width,
        'height': source.height,
        'pixelFormat': 'RGBA8888',
        'colorSpaceAssumption': 'PNG samples are interpreted as sRGB, straight alpha; encoded reference PNGs retain the decoded 8-bit RGBA samples.',
      },
    },
    'compatibility': <String, Object>{
      'nv21':
          'The public legacy nv21 label is intentionally UV/NV12-like: each chroma pair is U then V. Do not silently change this order based on the label.',
      'yuvConversion': 'BT.601 limited-range 4:2:0 reference; chroma is the integer average of each 2x2 source block.',
    },
    'tolerances': <String, Object>{
      'exact': <String, Object>{
        'mae': 0,
        'maxChannelError': 0,
        'percentile99ChannelError': 0,
        'rationale':
            'Metadata, raw construction/serialization bytes, channel reorder, plane-only transforms, and exact RGB transforms are integer-preserving.',
      },
      'yuvRoundTrip': <String, Object>{
        'mae': 18,
        'maxChannelError': 96,
        'percentile99ChannelError': 48,
        'rationale':
            '4:2:0 chroma subsampling is lossy; bounds are fixed before backend execution and allow edge-local chroma error while rejecting broad color drift.',
      },
      'nv21RoundTrip': <String, Object>{
        'mae': 50,
        'maxChannelError': 160,
        'percentile99ChannelError': 96,
        'rationale':
            'Legacy UV compatibility paths have historically used a wider conversion envelope; this is predeclared, not tuned from a backend run.',
      },
      'blur': <String, Object>{
        'mae': 4,
        'maxChannelError': 24,
        'percentile99ChannelError': 12,
        'rationale':
            'Independent kernels use clamp-to-edge borders and rounded samples. Small fixed integer-kernel implementation differences are allowed, alpha remains exact.',
      },
    },
    'artifacts': <String, Object>{
      for (final entry in artifacts.entries)
        entry.key: <String, Object>{
          'path': 'artifacts/${entry.key}',
          'sha256': sha256Hex(entry.value),
          'byteLength': entry.value.length,
        },
    },
    'formatReference': sourceFormatMetadata,
    'cases': cases,
    'coverage': <String, Object>{
      'requiredMatrixRows': 18,
      'caseCount': cases.length,
      'formats': <String>['bgra8888', 'i420', 'nv21'],
      'visualReviewSet': <String>[
        'original.png',
        'crop_inner.png',
        'rotate_90.png',
        'rotate_180.png',
        'rotate_270.png',
        'grayscale.png',
        'blackwhite.png',
        'negate.png',
        'gaussian_default.png',
        'box_default.png',
        'mean_default.png',
      ],
    },
  };
}

List<Map<String, Object>> _matrix(
  RgbaFrame source,
  Map<String, RgbaFrame> frames,
) {
  final cases = <Map<String, Object>>[];
  void add({
    required String id,
    required String group,
    required String operation,
    required String inputFormat,
    String layout = 'tight',
    Map<String, Object> parameters = const <String, Object>{},
    String artifact = 'original.png',
    String comparison = 'exact',
    String? expectedFormat,
    Map<String, Object>? expectedDimensions,
    String? expectedLayout,
    String? rawArtifact,
    Map<String, Object>? rawPlaneReference,
    Map<String, Object>? inputDimensions,
  }) {
    final format = expectedFormat ?? inputFormat;
    final outputLayout = expectedLayout ?? layout;
    final referenceFrame = frames[rawArtifact ?? artifact] ?? source;
    final reference = rawPlaneReference ?? _formatReference(referenceFrame, format, outputLayout);
    cases.add(<String, Object>{
      'id': id,
      'group': group,
      'operation': operation,
      'input': <String, Object>{
        'format': inputFormat,
        'layout': layout,
        'dimensions': inputDimensions ?? _dimensions(source),
      },
      'parameters': parameters,
      'expected': <String, Object>{
        'format': format,
        'dimensions': expectedDimensions ?? _dimensions(source),
        'artifact': artifact,
        'rawPlaneReference': reference,
      },
      'comparison': comparison,
    });
  }

  const formats = <String>['bgra8888', 'i420', 'nv21'];
  for (final format in formats) {
    for (final layout in <String>['tight', 'padded']) {
      add(
          id: 'CONSTRUCT-${format.toUpperCase()}-${layout.toUpperCase()}',
          group: 'Construction',
          operation: 'YuvImage.${format == 'bgra8888' ? 'bgra' : format}',
          inputFormat: format,
          layout: layout);
    }
    add(
        id: 'INPUT-FROM-RGBA-${format.toUpperCase()}',
        group: 'Input',
        operation: 'fromRgba8888',
        inputFormat: format,
        artifact: format == 'bgra8888' ? 'source_bgra8888.bin' : '${format == 'i420' ? 'i420' : 'nv21_uv'}_decoded.png',
        rawArtifact: 'original.png',
        comparison: format == 'bgra8888'
            ? 'exact'
            : format == 'i420'
                ? 'yuvRoundTrip'
                : 'nv21RoundTrip');
    for (final layout in <String>['tight', 'padded']) {
      add(
          id: 'OUTPUT-TO-BGRA-${format.toUpperCase()}-${layout.toUpperCase()}',
          group: 'Output',
          operation: 'toBgra8888',
          inputFormat: format,
          layout: layout,
          artifact: format == 'bgra8888' ? 'source_bgra8888.bin' : '${format == 'i420' ? 'i420' : 'nv21_uv'}_decoded.png',
          comparison: format == 'bgra8888'
              ? 'exact'
              : format == 'i420'
                  ? 'yuvRoundTrip'
                  : 'nv21RoundTrip',
          expectedFormat: 'bgra8888',
          expectedLayout: 'tight');
    }
  }

  for (final input in <String>['i420', 'nv21']) {
    add(
        id: 'FORMAT-TO-BGRA-${input.toUpperCase()}',
        group: 'Format',
        operation: 'toYuvBgra8888',
        inputFormat: input,
        artifact: '${input == 'i420' ? 'i420' : 'nv21_uv'}_decoded.png',
        comparison: input == 'i420' ? 'yuvRoundTrip' : 'nv21RoundTrip',
        expectedFormat: 'bgra8888',
        expectedLayout: 'tight');
  }
  for (final layout in <String>['tight', 'padded']) {
    add(
        id: 'FORMAT-TO-I420-BGRA-${layout.toUpperCase()}',
        group: 'Format',
        operation: 'toYuvI420',
        inputFormat: 'bgra8888',
        layout: layout,
        artifact: 'i420_decoded.png',
        rawArtifact: 'original.png',
        comparison: 'yuvRoundTrip',
        expectedFormat: 'i420',
        expectedLayout: 'tight');
    add(
        id: 'FORMAT-TO-I420-NV21-${layout.toUpperCase()}',
        group: 'Format',
        operation: 'toYuvI420',
        inputFormat: 'nv21',
        layout: layout,
        artifact: 'i420_decoded.png',
        comparison: 'exact',
        expectedFormat: 'i420',
        expectedLayout: 'tight',
        rawPlaneReference: _formatReference(source, 'i420', 'tight'));
    add(
        id: 'FORMAT-TO-NV21-BGRA-${layout.toUpperCase()}',
        group: 'Format',
        operation: 'toYuvNv21',
        inputFormat: 'bgra8888',
        layout: layout,
        artifact: 'nv21_uv_decoded.png',
        rawArtifact: 'original.png',
        comparison: 'nv21RoundTrip',
        expectedFormat: 'nv21',
        expectedLayout: 'tight');
    add(
        id: 'FORMAT-TO-NV21-I420-${layout.toUpperCase()}',
        group: 'Format',
        operation: 'toYuvNv21',
        inputFormat: 'i420',
        layout: layout,
        artifact: 'nv21_uv_decoded.png',
        comparison: 'exact',
        expectedFormat: 'nv21',
        expectedLayout: 'tight',
        rawPlaneReference: _formatReference(source, 'nv21', 'tight'));
  }

  for (final input in <String>['nv21', 'i420']) {
    for (final swaps in <int>[1, 2]) {
      add(
          id: 'CHROMA-SWAP-${input.toUpperCase()}-$swaps',
          group: 'Chroma',
          operation: 'swapNv',
          inputFormat: input,
          parameters: <String, Object>{'swaps': swaps},
          artifact: swaps == 1 ? 'swap_nv_once.png' : 'original.png',
          comparison: 'exact',
          expectedFormat: 'nv21',
          rawPlaneReference: _swapNvReference(source, swaps));
    }
  }

  final cropCases = <(String, Map<String, Object>, String)>[
    ('inner', <String, Object>{'left': 64, 'top': 96, 'width': 256, 'height': 320}, 'crop_inner.png'),
    ('clamped', <String, Object>{'left': -50, 'top': -10, 'width': 9999, 'height': 9999}, 'original.png'),
    ('empty', <String, Object>{'left': 100, 'top': 100, 'width': -20, 'height': 10}, 'original.png'),
  ];
  for (final format in formats) {
    for (final cropCase in cropCases) {
      add(
          id: 'GEOMETRY-CROP-${format.toUpperCase()}-${cropCase.$1.toUpperCase()}',
          group: 'Geometry',
          operation: 'crop',
          inputFormat: format,
          parameters: cropCase.$2,
          artifact: cropCase.$3,
          expectedDimensions: cropCase.$1 == 'inner' ? <String, Object>{'width': 256, 'height': 320} : _dimensions(source));
    }
    for (final rotation in <int>[0, 90, 180, 270]) {
      add(
          id: 'GEOMETRY-ROTATE-${format.toUpperCase()}-$rotation',
          group: 'Geometry',
          operation: 'rotate',
          inputFormat: format,
          parameters: <String, Object>{'degreesClockwise': rotation},
          artifact: rotation == 0 ? 'original.png' : 'rotate_$rotation.png');
    }
    add(
        id: 'GEOMETRY-FLIP-H-${format.toUpperCase()}',
        group: 'Geometry',
        operation: 'flipHorizontally',
        inputFormat: format,
        artifact: 'flip_horizontal.png');
    add(
        id: 'GEOMETRY-FLIP-V-${format.toUpperCase()}',
        group: 'Geometry',
        operation: 'flipVertically',
        inputFormat: format,
        artifact: 'flip_vertical.png');
  }

  for (final operation in <(String, String)>[
    ('grayscale', 'grayscale.png'),
    ('blackwhite', 'blackwhite.png'),
    ('negate', 'negate.png'),
  ]) {
    for (final format in formats) {
      add(
          id: 'EFFECT-${operation.$1.toUpperCase()}-${format.toUpperCase()}',
          group: 'Effect',
          operation: operation.$1,
          inputFormat: format,
          artifact: operation.$2,
          comparison: format == 'bgra8888' ? 'exact' : 'yuvRoundTrip');
    }
  }

  final blurCases = <(String, String, Map<String, Object>)>[
    ('gaussianBlur', 'gaussian_default.png', <String, Object>{'radius': 2, 'sigma': 2}),
    ('gaussianBlur', 'gaussian_r3_s2.png', <String, Object>{'radius': 3, 'sigma': 2}),
    ('boxBlur', 'box_default.png', <String, Object>{'radius': 10}),
    ('boxBlur', 'box_full.png', <String, Object>{'radius': 5}),
    (
      'boxBlur',
      'box_rect.png',
      <String, Object>{
        'radius': 5,
        'rect': <String, int>{'left': 32, 'top': 32, 'width': 256, 'height': 256}
      }
    ),
    ('meanBlur', 'mean_default.png', <String, Object>{'radius': 2}),
    ('meanBlur', 'mean_full.png', <String, Object>{'radius': 5}),
    (
      'meanBlur',
      'mean_rect.png',
      <String, Object>{
        'radius': 5,
        'rect': <String, int>{'left': 32, 'top': 32, 'width': 256, 'height': 256}
      }
    ),
  ];
  for (final blur in blurCases) {
    for (final format in formats) {
      add(
          id: 'BLUR-${blur.$1.toUpperCase()}-${format.toUpperCase()}-${blur.$2.replaceAll('.png', '').toUpperCase()}',
          group: 'Blur',
          operation: blur.$1,
          inputFormat: format,
          parameters: blur.$3,
          artifact: blur.$2,
          comparison: 'blur');
    }
  }

  for (final format in formats) {
    for (final blank in <bool>[false, true]) {
      add(
          id: 'STATE-COPY-${format.toUpperCase()}-${blank ? 'BLANK' : 'NORMAL'}',
          group: 'State',
          operation: 'copy',
          inputFormat: format,
          parameters: <String, Object>{'blank': blank},
          artifact: blank
              ? format == 'bgra8888'
                  ? 'blank_bgra8888.bin'
                  : format == 'i420'
                      ? 'blank_i420.yuv'
                      : 'blank_nv21_uv.yuv'
              : 'original.png',
          rawPlaneReference: blank ? _blankReference(source, format, 'tight') : null);
    }
    for (final layout in <String>['tight', 'padded']) {
      add(
          id: 'BYTES-GET-${format.toUpperCase()}-${layout.toUpperCase()}',
          group: 'Bytes',
          operation: 'getBytes',
          inputFormat: format,
          layout: layout);
    }
    for (final stream in <String>['single_chunk', 'fragmented']) {
      add(
          id: 'IO-SAVE-LOAD-${format.toUpperCase()}-${stream.toUpperCase()}',
          group: 'I/O',
          operation: 'save/load',
          inputFormat: format,
          parameters: <String, Object>{'stream': stream});
    }
    add(
        id: 'FLUTTER-TO-IMAGE-${format.toUpperCase()}',
        group: 'Flutter',
        operation: 'toImage',
        inputFormat: format,
        artifact: format == 'bgra8888' ? 'original.png' : '${format == 'i420' ? 'i420' : 'nv21_uv'}_decoded.png',
        comparison: format == 'bgra8888'
            ? 'exact'
            : format == 'i420'
                ? 'yuvRoundTrip'
                : 'nv21RoundTrip');
  }

  for (final oddCase in <(String, int, int)>[
    ('1X1', 1, 1),
    ('3X5', 3, 5),
    ('127X255', 127, 255),
  ]) {
    final artifact = 'crop_${oddCase.$2}x${oddCase.$3}.png';
    final dimensions = <String, Object>{'width': oddCase.$2, 'height': oddCase.$3};
    for (final format in formats) {
      add(
        id: 'INPUT-ODD-CUSTOM-STRIDE-${format.toUpperCase()}-${oddCase.$1}',
        group: 'Input',
        operation: 'fromRgba8888',
        inputFormat: format,
        layout: 'customStride',
        parameters: <String, Object>{
          'sourceCrop': <String, int>{'left': 0, 'top': 0, 'width': oddCase.$2, 'height': oddCase.$3},
          'purpose': 'YUV-05 odd-size tight-RGBA to custom-stride destination reference',
        },
        artifact: artifact,
        expectedDimensions: dimensions,
        inputDimensions: dimensions,
      );
    }
  }
  return cases;
}

Map<String, Object> _dimensions(RgbaFrame frame) => <String, Object>{'width': frame.width, 'height': frame.height};

Map<String, Object> _formatReference(RgbaFrame frame, String format, String layout) => switch (format) {
      'bgra8888' => bgraPlaneMetadata(frame.toBgra(), frame.width, frame.height, layout: layout),
      'i420' => planeMetadata(rgbaToI420(frame), layout: layout),
      'nv21' => planeMetadata(i420ToNv21Uv(rgbaToI420(frame)), layout: layout),
      _ => throw ArgumentError.value(format, 'format', 'unsupported reference format'),
    };

Map<String, Object> _swapNvReference(RgbaFrame source, int swaps) {
  final nv21 = i420ToNv21Uv(rgbaToI420(source));
  final uv = Uint8List.fromList(nv21.uv!);
  if (swaps.isOdd) {
    for (var index = 0; index < uv.length; index += 2) {
      final first = uv[index];
      uv[index] = uv[index + 1];
      uv[index + 1] = first;
    }
  }
  return planeMetadata(Yuv420Frame.nv21Uv(nv21.width, nv21.height, nv21.y, uv), layout: 'tight');
}

Map<String, Object> _blankReference(RgbaFrame source, String format, String layout) {
  final reference = _formatReference(source, format, layout);
  final planes = (reference['planes']! as List<Map<String, Object>>)
      .map(
        (plane) => <String, Object>{
          ...plane,
          'sha256': sha256Hex(Uint8List(plane['byteLength']! as int)),
        },
      )
      .toList(growable: false);
  return <String, Object>{...reference, 'planes': planes, 'isZeroFilled': true};
}

Uint8List _join(List<Uint8List> planes) {
  final length = planes.fold<int>(0, (sum, plane) => sum + plane.length);
  final result = Uint8List(length);
  var offset = 0;
  for (final plane in planes) {
    result.setRange(offset, offset + plane.length, plane);
    offset += plane.length;
  }
  return result;
}

bool _sameBytes(Uint8List first, Uint8List second) {
  if (first.length != second.length) {
    return false;
  }
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) {
      return false;
    }
  }
  return true;
}
