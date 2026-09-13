import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

import 'helpers/reference/test_pattern_reference.dart';

const _manifestPath = 'test/reference/test_pattern_512/manifest.json';
const _sourcePath = 'test/assets/test_pattern_512.png';
const _fixtureRoot = 'test/reference/test_pattern_512';

/// Native provenance is deliberately printed by this suite.  The repository
/// does not contain the ignored DLL, so a local run must not be mistaken for a
/// clean-checkout or CI binary check.
void main() {
  late Map<String, dynamic> manifest;
  late RgbaFrame source;
  late Map<String, RgbaFrame> expectedImages;
  late bool nativeAvailable;

  setUpAll(() async {
    manifest = jsonDecode(await File(_manifestPath).readAsString()) as Map<String, dynamic>;
    source = decodePng(await File(_sourcePath).readAsBytes());
    expectedImages = <String, RgbaFrame>{};
    final artifacts = manifest['artifacts'] as Map<String, dynamic>;
    for (final entry in artifacts.entries) {
      if (entry.key.endsWith('.png')) {
        final metadata = entry.value as Map<String, dynamic>;
        expectedImages[entry.key] = decodePng(await File('$_fixtureRoot/${metadata['path']}').readAsBytes());
      }
    }

    final nativeLibrary = _nativeLibraryFile();
    nativeAvailable = nativeLibrary?.existsSync() ?? false;
    debugPrint(
      'YUV-11 native provenance: os=${Platform.operatingSystem}, '
      'arch=${Abi.current()}, dart=${Platform.version.split(' ').first}, '
      'library=${nativeLibrary?.absolute.path ?? 'unsupported'}, exists=$nativeAvailable, '
      'sha256=${nativeAvailable ? sha256Hex(await nativeLibrary!.readAsBytes()) : 'not available'}',
    );
  });

  test('manifest declares the complete native reference matrix', () {
    final cases = (manifest['cases'] as List<dynamic>).cast<Map<String, dynamic>>();
    expect(cases, hasLength(119));
    expect(cases.map((entry) => entry['id']).toSet(), hasLength(cases.length));
  });

  test('native library required by the backend is available', () {
    expect(
      nativeAvailable,
      isTrue,
      reason: 'YUV-11 cannot be accepted from a run that skipped every native case',
    );
  });

  for (final entry in _casesFromManifest()) {
    test(entry['id'] as String, () async {
      if (!nativeAvailable) {
        markTestSkipped('YUV-11 native library is not available on this host');
      }
      final result = await _runCase(entry, source);
      _assertCase(entry, result, expectedImages);
    }, timeout: const Timeout(Duration(minutes: 2)));
  }
}

File? _nativeLibraryFile() {
  if (Platform.isWindows) return File('yuv_ffi.dll');
  if (Platform.isLinux) return File('native/src/build/libyuv_ffi.so');
  if (Platform.isMacOS) return File('native/src/build/libyuv_ffi.dylib');
  return null;
}

List<Map<String, dynamic>> _casesFromManifest() {
  final bytes = File(_manifestPath).readAsBytesSync();
  final manifest = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  return (manifest['cases'] as List<dynamic>).cast<Map<String, dynamic>>();
}

class _CaseResult {
  _CaseResult({required this.image, required this.outputBytes, this.imageBytes, this.rawBytes});

  final YuvImage image;
  final Uint8List outputBytes;
  final Uint8List? imageBytes;
  final Uint8List? rawBytes;
}

Future<_CaseResult> _runCase(Map<String, dynamic> entry, RgbaFrame source) async {
  final input = entry['input'] as Map<String, dynamic>;
  final dimensions = input['dimensions'] as Map<String, dynamic>;
  final width = dimensions['width'] as int;
  final height = dimensions['height'] as int;
  final format = _format(input['format'] as String);
  final layout = input['layout'] as String;
  final parameters = (entry['parameters'] as Map<String, dynamic>?) ?? <String, dynamic>{};
  final frame = _sourceFrame(source, parameters);
  final operation = entry['operation'] as String;
  final image = _newImage(format, width, height, _planesFor(format, frame, layout), operation == 'fromRgba8888');
  final sourceFrameHash = sha256Hex(frame.bytes);
  final sourcePlaneHash = _planesHash(image.planes);
  Uint8List? imageBytes;
  Uint8List? rawBytes;

  switch (operation) {
    case 'YuvImage.bgra':
    case 'YuvImage.i420':
    case 'YuvImage.nv21':
      break;
    case 'fromRgba8888':
      image.fromRgba8888(frame.bytes);
      break;
    case 'toBgra8888':
      rawBytes = image.toBgra8888();
      break;
    case 'toYuvBgra8888':
      _inPlace(entry, image, image.toYuvBgra8888);
      break;
    case 'toYuvI420':
      _inPlace(entry, image, image.toYuvI420);
      break;
    case 'toYuvNv21':
      _inPlace(entry, image, image.toYuvNv21);
      break;
    case 'swapNv':
      final swaps = parameters['swaps'] as int;
      for (var i = 0; i < swaps; i++) {
        _inPlace(entry, image, image.swapNv);
      }
      break;
    case 'crop':
      _inPlace(entry, image, () => image.crop(_rect(parameters)));
      break;
    case 'rotate':
      _inPlace(entry, image, () => image.rotate(_rotation(parameters['degreesClockwise'] as int)));
      break;
    case 'flipHorizontally':
      _inPlace(entry, image, image.flipHorizontally);
      break;
    case 'flipVertically':
      _inPlace(entry, image, image.flipVertically);
      break;
    case 'grayscale':
      _inPlace(entry, image, image.grayscale);
      break;
    case 'blackwhite':
      _inPlace(entry, image, image.blackwhite);
      break;
    case 'negate':
      _inPlace(entry, image, image.negate);
      break;
    case 'gaussianBlur':
      _inPlace(entry, image, () => image.gaussianBlur(radius: parameters['radius'] as int, sigma: parameters['sigma'] as int));
      break;
    case 'boxBlur':
      _inPlace(
          entry,
          image,
          () => image.boxBlur(
              radius: parameters['radius'] as int, rect: parameters.containsKey('rect') ? _rect(parameters['rect'] as Map<String, dynamic>) : null));
      break;
    case 'meanBlur':
      _inPlace(
          entry,
          image,
          () => image.meanBlur(
              radius: parameters['radius'] as int, rect: parameters.containsKey('rect') ? _rect(parameters['rect'] as Map<String, dynamic>) : null));
      break;
    case 'copy':
      final copied = image.copy(blank: parameters['blank'] as bool);
      expect(identical(copied, image), isFalse, reason: '${entry['id']} copy must return a new image instance');
      expect(sha256Hex(frame.bytes), sourceFrameHash, reason: '${entry['id']} mutated source RGBA fixture');
      expect(_planesHash(image.planes), sourcePlaneHash, reason: '${entry['id']} mutated input during copy');
      return _CaseResult(image: copied, outputBytes: copied.toBgra8888(), rawBytes: copied.getBytes());
    case 'getBytes':
      rawBytes = image.getBytes();
      break;
    case 'save/load':
      final chunks = <List<int>>[];
      await image.save(_ListSink(chunks));
      final loaded = _newImage(format, width, height, _planesFor(format, frame, layout), false);
      final stream = parameters['stream'] == 'fragmented' ? _fragment(chunks) : chunks;
      await loaded.load(Stream<List<int>>.fromIterable(stream));
      expect(sha256Hex(frame.bytes), sourceFrameHash, reason: '${entry['id']} mutated source RGBA fixture');
      expect(_planesHash(image.planes), sourcePlaneHash, reason: '${entry['id']} mutated input during save');
      return _CaseResult(image: loaded, outputBytes: loaded.toBgra8888(), rawBytes: loaded.getBytes());
    case 'toImage':
      final decoded = await image.toImage();
      try {
        final data = await decoded.toByteData(format: ui.ImageByteFormat.rawRgba);
        imageBytes = data == null ? null : Uint8List.fromList(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      } finally {
        decoded.dispose();
      }
      break;
    default:
      throw StateError('Unimplemented YUV-11 operation: $operation');
  }

  expect(sha256Hex(frame.bytes), sourceFrameHash, reason: '${entry['id']} mutated source RGBA fixture');
  if (operation == 'toBgra8888' || operation == 'getBytes' || operation == 'toImage') {
    expect(_planesHash(image.planes), sourcePlaneHash, reason: '${entry['id']} mutated input during read-only operation');
  }
  return _CaseResult(image: image, outputBytes: rawBytes ?? image.toBgra8888(), imageBytes: imageBytes, rawBytes: rawBytes);
}

void _inPlace(Map<String, dynamic> entry, YuvImage image, YuvImage Function() operation) {
  expect(identical(operation(), image), isTrue, reason: '${entry['id']} must return the same image instance');
}

String _planesHash(Iterable<YuvPlane> planes) => sha256Hex(_concat(planes.map((plane) => plane.bytes)));

YuvImage _newImage(YuvFileFormat format, int width, int height, List<YuvPlane> planes, bool blank) {
  if (blank) {
    planes = _blankLogicalSamples(format, width, planes);
  }
  return switch (format) {
    // The named IO BGRA constructor intentionally normalizes padded input to a
    // tight plane. The explicit-format constructor is required here because
    // YUV-05 exercises fromRgba8888 into the custom destination layout pinned
    // by the manifest.
    YuvFileFormat.bgra8888 when blank => YuvImage(format, width, height, planes: planes),
    YuvFileFormat.bgra8888 => YuvImage.bgra(width, height, planes: planes),
    YuvFileFormat.i420 => YuvImage.i420(width, height, planes: planes),
    YuvFileFormat.nv21 => YuvImage.nv21(width, height, planes: planes),
  };
}

List<YuvPlane> _blankLogicalSamples(
  YuvFileFormat format,
  int width,
  List<YuvPlane> planes,
) {
  final chromaWidth = (width + 1) ~/ 2;
  return List<YuvPlane>.generate(planes.length, (planeIndex) {
    final plane = planes[planeIndex];
    final bytes = Uint8List.fromList(plane.bytes);
    final logicalWidth = planeIndex == 0 ? width : chromaWidth;
    final sampleBytes = switch (format) {
      YuvFileFormat.bgra8888 => 4,
      YuvFileFormat.nv21 when planeIndex == 1 => 2,
      _ => 1,
    };
    for (var row = 0; row < plane.height; row++) {
      for (var column = 0; column < logicalWidth; column++) {
        final offset = row * plane.rowStride + column * plane.pixelStride;
        bytes.fillRange(offset, offset + sampleBytes, 0);
      }
    }
    return YuvPlane(plane.height, plane.rowStride, plane.pixelStride, bytes);
  });
}

YuvFileFormat _format(String value) => switch (value) {
      'bgra8888' => YuvFileFormat.bgra8888,
      'i420' => YuvFileFormat.i420,
      'nv21' => YuvFileFormat.nv21,
      _ => throw ArgumentError.value(value, 'format'),
    };

YuvImageRotation _rotation(int degrees) => switch (degrees) {
      0 => YuvImageRotation.rotation0,
      90 => YuvImageRotation.rotation90,
      180 => YuvImageRotation.rotation180,
      270 => YuvImageRotation.rotation270,
      _ => throw ArgumentError.value(degrees, 'degrees'),
    };

ui.Rect _rect(Map<String, dynamic> value) => ui.Rect.fromLTWH(
      (value['left'] as num).toDouble(),
      (value['top'] as num).toDouble(),
      (value['width'] as num).toDouble(),
      (value['height'] as num).toDouble(),
    );

RgbaFrame _sourceFrame(RgbaFrame source, Map<String, dynamic> parameters) {
  final crop = parameters['sourceCrop'];
  if (crop is! Map<String, dynamic>) return source;
  return source.crop(crop['left'] as int, crop['top'] as int, crop['width'] as int, crop['height'] as int);
}

List<YuvPlane> _planesFor(YuvFileFormat format, RgbaFrame frame, String layout) {
  final i420 = rgbaToI420(frame);
  final tight = switch (format) {
    YuvFileFormat.bgra8888 => <Uint8List>[frame.toBgra()],
    YuvFileFormat.i420 => <Uint8List>[i420.y, i420.u!, i420.v!],
    YuvFileFormat.nv21 => <Uint8List>[i420.y, i420ToNv21Uv(i420).uv!],
  };
  final chromaWidth = (frame.width + 1) ~/ 2;
  final chromaHeight = (frame.height + 1) ~/ 2;
  final strides = switch (format) {
    YuvFileFormat.bgra8888 => <int>[
        switch (layout) { 'padded' => frame.width * 4 + 16, 'customStride' => frame.width * 4 + 7, _ => frame.width * 4 }
      ],
    YuvFileFormat.i420 => <int>[
        switch (layout) { 'padded' => frame.width + 8, 'customStride' => frame.width + 3, _ => frame.width },
        switch (layout) { 'padded' => chromaWidth + 4, 'customStride' => chromaWidth + 2, _ => chromaWidth },
        switch (layout) { 'padded' => chromaWidth + 4, 'customStride' => chromaWidth + 2, _ => chromaWidth },
      ],
    YuvFileFormat.nv21 => <int>[
        switch (layout) { 'padded' => frame.width + 8, 'customStride' => frame.width + 3, _ => frame.width },
        switch (layout) { 'padded' => chromaWidth * 2 + 8, 'customStride' => chromaWidth * 2 + 3, _ => chromaWidth * 2 },
      ],
  };
  final heights =
      format == YuvFileFormat.bgra8888 ? <int>[frame.height] : <int>[frame.height, chromaHeight, if (format == YuvFileFormat.i420) chromaHeight];
  final useful = format == YuvFileFormat.bgra8888
      ? <int>[frame.width * 4]
      : <int>[frame.width, if (format == YuvFileFormat.nv21) chromaWidth * 2 else chromaWidth, if (format == YuvFileFormat.i420) chromaWidth];
  final pixelStrides =
      format == YuvFileFormat.bgra8888 ? <int>[4] : <int>[1, if (format == YuvFileFormat.nv21) 2 else 1, if (format == YuvFileFormat.i420) 1];
  return List<YuvPlane>.generate(tight.length, (index) => _plane(tight[index], heights[index], strides[index], pixelStrides[index], useful[index]));
}

YuvPlane _plane(Uint8List tight, int height, int rowStride, int pixelStride, int usefulRowBytes) {
  final bytes = Uint8List(height * rowStride);
  for (var row = 0; row < height; row++) {
    final destination = row * rowStride;
    final source = row * usefulRowBytes;
    bytes.setRange(destination, destination + usefulRowBytes, tight, source);
    bytes.fillRange(destination + usefulRowBytes, destination + rowStride, 0xa5);
  }
  return YuvPlane(height, rowStride, pixelStride, bytes);
}

void _assertCase(Map<String, dynamic> entry, _CaseResult result, Map<String, RgbaFrame> expectedImages) {
  final expected = entry['expected'] as Map<String, dynamic>;
  final expectedDimensions = expected['dimensions'] as Map<String, dynamic>;
  expect(result.image.width, expectedDimensions['width'], reason: entry['id'] as String);
  expect(result.image.height, expectedDimensions['height'], reason: entry['id'] as String);

  final operation = entry['operation'] as String;
  if (operation == 'toYuvBgra8888' ||
      operation == 'toYuvI420' ||
      operation == 'toYuvNv21' ||
      (operation == 'swapNv' && result.image.format == YuvFileFormat.nv21)) {
    expect(result.image.format.name, expected['format'], reason: entry['id'] as String);
  }

  final artifact = expected['artifact'] as String;
  final expectedFrame = expectedImages[artifact];
  final compareVisual = expectedFrame != null && (expected['format'] == 'bgra8888' || entry['comparison'] != 'exact');
  if (compareVisual) {
    final expectedBytes = operation == 'toImage' ? expectedFrame.bytes : expectedFrame.toBgra();
    final actual = result.imageBytes ?? result.outputBytes;
    final tolerance =
        (jsonDecode(File(_manifestPath).readAsStringSync()) as Map<String, dynamic>)['tolerances'][entry['comparison']] as Map<String, dynamic>;
    final metrics = _metrics(actual, expectedBytes, threshold: tolerance['maxChannelError'] as int);
    debugPrint('${entry['id']}: ${metrics.format()} expected=${entry['comparison']}');
    expect(metrics.mae, lessThanOrEqualTo((tolerance['mae'] as num).toDouble()), reason: entry['id'] as String);
    expect(metrics.maxChannelError, lessThanOrEqualTo(tolerance['maxChannelError'] as num), reason: entry['id'] as String);
    expect(metrics.percentile99ChannelError, lessThanOrEqualTo(tolerance['percentile99ChannelError'] as num), reason: entry['id'] as String);
    expect(metrics.alphaMismatches, 0, reason: entry['id'] as String);
    if (entry['comparison'] == 'exact') expect(actual, orderedEquals(expectedBytes), reason: entry['id'] as String);
  }

  if (operation == 'copy' || operation == 'getBytes' || operation == 'save/load') {
    final expectedRaw = parametersForRaw(entry);
    final actualRaw = result.rawBytes!;
    final metrics = _metrics(actualRaw, expectedRaw);
    debugPrint('${entry['id']}: raw length=${actualRaw.length}/${expectedRaw.length} ${metrics.format()}');
    expect(actualRaw, orderedEquals(expectedRaw), reason: entry['id'] as String);
  } else if (operation != 'toImage') {
    _assertPlaneReference(entry, result);
  }
}

void _assertPlaneReference(Map<String, dynamic> entry, _CaseResult result) {
  final expected = entry['expected'] as Map<String, dynamic>;
  final expectedPlanes = (expected['rawPlaneReference']['planes'] as List<dynamic>).cast<Map<String, dynamic>>();
  final operation = entry['operation'] as String;
  final actualPlanes = <YuvPlane>[];
  if (operation == 'toBgra8888' || operation == 'toImage') {
    final bytes = operation == 'toImage' ? _rgbaToBgra(result.imageBytes!) : result.outputBytes;
    final dimensions = expected['dimensions'] as Map<String, dynamic>;
    actualPlanes.add(YuvPlane(dimensions['height'] as int, (dimensions['width'] as int) * 4, 4, bytes));
  } else {
    actualPlanes.addAll(result.image.planes);
  }
  expect(actualPlanes, hasLength(expectedPlanes.length), reason: entry['id'] as String);
  for (var index = 0; index < actualPlanes.length; index++) {
    final actual = actualPlanes[index];
    final expectedPlane = expectedPlanes[index];
    final actualHash = sha256Hex(actual.bytes);
    debugPrint('${entry['id']}: plane[$index] ${actual.bytes.length} bytes sha256=$actualHash');
    expect(actual.height, expectedPlane['height'], reason: entry['id'] as String);
    expect(actual.rowStride, expectedPlane['rowStride'], reason: entry['id'] as String);
    expect(actual.pixelStride, expectedPlane['pixelStride'], reason: entry['id'] as String);
    expect(actual.bytes.length, expectedPlane['byteLength'], reason: entry['id'] as String);
    if (entry['comparison'] == 'exact') {
      expect(actualHash, expectedPlane['sha256'], reason: entry['id'] as String);
    }
  }
}

Uint8List _rgbaToBgra(Uint8List rgba) {
  final bgra = Uint8List(rgba.length);
  for (var index = 0; index < rgba.length; index += 4) {
    bgra[index] = rgba[index + 2];
    bgra[index + 1] = rgba[index + 1];
    bgra[index + 2] = rgba[index];
    bgra[index + 3] = rgba[index + 3];
  }
  return bgra;
}

Uint8List parametersForRaw(Map<String, dynamic> entry) {
  final input = entry['input'] as Map<String, dynamic>;
  final layout = input['format'] == 'bgra8888' ? 'tight' : input['layout'] as String;
  final planes = _planesFor(_format(input['format'] as String), _rawSourceFrame(entry), layout);
  if (entry['operation'] == 'copy' && (entry['parameters'] as Map<String, dynamic>)['blank'] == true) {
    return Uint8List(planes.fold<int>(0, (sum, plane) => sum + plane.bytes.length));
  }
  return _concat(planes.map((plane) => plane.bytes));
}

RgbaFrame _rawSourceFrame(Map<String, dynamic> entry) {
  final params = entry['parameters'] as Map<String, dynamic>;
  final crop = params['sourceCrop'];
  final full = decodePng(File(_sourcePath).readAsBytesSync());
  if (crop is Map<String, dynamic>) return full.crop(crop['left'] as int, crop['top'] as int, crop['width'] as int, crop['height'] as int);
  return full;
}

Uint8List _concat(Iterable<Uint8List> parts) {
  final result = BytesBuilder(copy: false);
  for (final part in parts) {
    result.add(part);
  }
  return result.takeBytes();
}

List<List<int>> _fragment(List<List<int>> chunks) {
  final bytes = _concat(chunks.map(Uint8List.fromList));
  return [
    for (var start = 0; start < bytes.length; start += 137) bytes.sublist(start, (start + 137).clamp(0, bytes.length)),
  ];
}

class _ListSink implements Sink<List<int>> {
  _ListSink(this.chunks);
  final List<List<int>> chunks;
  @override
  void add(List<int> data) => chunks.add(List<int>.from(data));
  @override
  void close() {}
}

class _Metrics {
  _Metrics(this.mae, this.maxChannelError, this.percentile99ChannelError, this.pixelsOutsideThreshold, this.alphaMismatches);
  final double mae;
  final int maxChannelError;
  final int percentile99ChannelError;
  final int pixelsOutsideThreshold;
  final int alphaMismatches;

  String format() =>
      'mae=${mae.toStringAsFixed(3)} max=$maxChannelError p99=$percentile99ChannelError outside=$pixelsOutsideThreshold alpha=$alphaMismatches';
}

_Metrics _metrics(Uint8List actual, Uint8List expected, {int threshold = 0}) {
  if (actual.length != expected.length) {
    return _Metrics(double.infinity, 255, 255, math.max(actual.length, expected.length), 1);
  }
  var sum = 0;
  var maxError = 0;
  var outside = 0;
  var alpha = 0;
  final histogram = List<int>.filled(256, 0);
  for (var i = 0; i < actual.length; i++) {
    final error = (actual[i] - expected[i]).abs();
    sum += error;
    maxError = math.max(maxError, error);
    histogram[error]++;
    if (i % 4 == 3 && error != 0) alpha++;
    if (i % 4 == 3) {
      final pixelStart = i - 3;
      final pixelMax = math.max(
        math.max((actual[pixelStart] - expected[pixelStart]).abs(), (actual[pixelStart + 1] - expected[pixelStart + 1]).abs()),
        math.max((actual[pixelStart + 2] - expected[pixelStart + 2]).abs(), (actual[pixelStart + 3] - expected[pixelStart + 3]).abs()),
      );
      if (pixelMax > threshold) outside++;
    }
  }
  var rank = (actual.length * 0.99).ceil();
  var seen = 0;
  var p99 = 0;
  for (var error = 0; error < histogram.length; error++) {
    seen += histogram[error];
    if (seen >= rank) {
      p99 = error;
      break;
    }
  }
  return _Metrics(sum / actual.length, maxError, p99, outside, alpha);
}
