import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as image;
import 'package:yuv_ffi/yuv_ffi.dart';

const _operation = String.fromEnvironment('BLUR_OPERATION');
const _packageSha = String.fromEnvironment('BLUR_PACKAGE_SHA');
const _sourceSha = String.fromEnvironment('BLUR_SOURCE_SHA');
const _buildParameters = String.fromEnvironment('BLUR_BUILD_PARAMETERS');
const _variant = String.fromEnvironment('BLUR_VARIANT');
const _candidateSourceSha = String.fromEnvironment('BLUR_CANDIDATE_SOURCE_SHA');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _stage('startup operation=$_operation');
  try {
    final results = await _run();
    for (final result in results) {
      _log('YUV_BLUR_RESULT:${jsonEncode(result)}');
    }
    runApp(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Text(jsonEncode(results)),
      ),
    );
  } catch (error, stack) {
    _log(
      'YUV_BLUR_ERROR:${jsonEncode(<String, String>{'error': '$error', 'stack': '$stack'})}',
    );
    runApp(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Text('YUV_BLUR_ERROR: $error'),
      ),
    );
  }
}

Future<List<Map<String, Object>>> _run() async {
  if (!const <String>{'box', 'mean', 'gaussian'}.contains(_operation)) {
    throw ArgumentError.value(
      _operation,
      'BLUR_OPERATION',
      'must be box, mean, or gaussian',
    );
  }
  _stage('initialize');
  await YuvFfi.initialize();
  _stage('load_png');
  final png = (await rootBundle.load(
    'assets/blur_reference_1477x1065.png',
  )).buffer.asUint8List();
  final decoded = image.decodePng(png);
  if (decoded == null || decoded.width != 1477 || decoded.height != 1065) {
    throw StateError('Expected a 1477x1065 PNG fixture.');
  }

  final inputs = <String, image.Image>{
    'reference_1477x1065': decoded,
    'derived_720x360': image.copyResize(
      image.copyCrop(decoded, x: 0, y: 163, width: 1476, height: 738),
      width: 720,
      height: 360,
      interpolation: image.Interpolation.linear,
    ),
  };
  final datasets = <Map<String, Object>>[];
  for (final entry in inputs.entries) {
    _stage('prepare_nv21 ${entry.key}');
    final rgba = Uint8List.fromList(
      entry.value.getBytes(order: image.ChannelOrder.rgba),
    );
    // This package's legacy nv21 constructor deliberately stores U,V bytes and
    // reports nv12. These fixture bytes are selected explicitly; no camera
    // buffer or CameraX format label is used as evidence for their order.
    // ignore: deprecated_member_use
    final source = YuvImage.nv21(entry.value.width, entry.value.height)
      ..applyRgbaBytes(rgba);
    final sourceChecksum = sha256.convert(source.toBytes()).toString();
    final warmup = <double>[];
    final samples = <double>[];
    String? resultChecksum;
    YuvImage? visualResult;
    for (var index = 0; index < 9; index++) {
      _stage('${entry.key} ${index < 2 ? 'warmup' : 'sample'} $index clone');
      final candidate = source.copy();
      final stopwatch = Stopwatch()..start();
      _apply(candidate);
      stopwatch.stop();
      _stage('${entry.key} ${index < 2 ? 'warmup' : 'sample'} $index done');
      final elapsed = stopwatch.elapsedMicroseconds / 1000.0;
      final checksum = sha256.convert(candidate.toBytes()).toString();
      if (entry.key == 'reference_1477x1065' && index == 8) {
        visualResult = candidate;
      }
      resultChecksum ??= checksum;
      if (checksum != resultChecksum) {
        throw StateError(
          'Non-deterministic output for ${entry.key}: $checksum != $resultChecksum',
        );
      }
      (index < 2 ? warmup : samples).add(elapsed);
    }
    final sorted = List<double>.from(samples)..sort();
    if (_operation == 'gaussian' && visualResult != null) {
      await _writeVisual(visualResult);
    }
    datasets.add(<String, Object>{
      'id': entry.key,
      'width': entry.value.width,
      'height': entry.value.height,
      'public_format': source.format.name,
      'source_constructor': 'YuvImage.nv21',
      'selected_chroma_byte_order': 'UV',
      'packed_layout': 'Y + interleaved UV chroma',
      'source_sha256': sourceChecksum,
      'result_sha256': resultChecksum!,
      'warmup_ms': warmup,
      'raw_ms': samples,
      'median_ms': sorted[sorted.length ~/ 2],
      'min_ms': sorted.first,
      'max_ms': sorted.last,
      'spread_ms': sorted.last - sorted.first,
    });
  }
  return datasets
      .map(
        (dataset) => <String, Object>{
          'schema': 1,
          'operation': _operation,
          'radius': 10,
          if (_operation == 'gaussian') 'sigma': 10,
          'warmup_count': 2,
          'sample_count': 7,
          'package_sha': _packageSha,
          'source_sha': _sourceSha,
          'build_parameters': _buildParameters,
          'variant': _variant,
          'candidate_source_sha256': _candidateSourceSha,
          ...dataset,
        },
      )
      .toList(growable: false);
}

Future<void> _writeVisual(YuvImage result) async {
  final bytes = result.toBgraBytes();
  final frame = image.Image.fromBytes(
    width: result.width,
    height: result.height,
    bytes: bytes.buffer,
    numChannels: 4,
    order: image.ChannelOrder.bgra,
  );
  const channel = MethodChannel('blur_runner/files');
  final directory = await channel.invokeMethod<String>('externalFilesDir');
  if (directory == null) throw StateError('externalFilesDir unavailable');
  final path = '$directory/blur03_gaussian_$_variant.png';
  await File(path).writeAsBytes(image.encodePng(frame));
  _stage('visual $path');
}

void _apply(YuvImage image) {
  switch (_operation) {
    case 'box':
      image.applyBoxBlur(radius: 10);
    case 'mean':
      image.applyMeanBlur(radius: 10);
    case 'gaussian':
      image.applyGaussianBlur(radius: 10, sigma: 10);
  }
}

void _stage(String value) => _log('YUV_BLUR_STAGE:$value');
// ignore: avoid_print
void _log(String value) => print(value);
