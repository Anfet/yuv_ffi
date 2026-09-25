import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const benchCsvHeader =
    'platform,machine,round,version,sha,src_tree_id,scenario_id,op,src_fmt,dst_fmt,width,height,params,layout,level,status,reason,warmup,n,min_ms,median_ms,p95_or_max_ms,upper_kind,mean_ms,stdev_ms,spread,checksum_sha256,raw_ms,started_at,finished_at,compiler,flags,power_plan,affinity';

/// The three public calls selected for the MEAS-02 smoke matrix.
const benchScenarios = <BenchScenario>[
  BenchScenario('FLIP.I420.V', 'I420'),
  BenchScenario('FLIP.NV12.V', 'NV12'),
  BenchScenario('FLIP.BGRA.V', 'BGRA'),
];

const benchSizes = <BenchSize>[BenchSize(1920, 1080), BenchSize(4000, 3000)];
const benchRounds = <int>[1, 2, 3];

final class BenchScenario {
  const BenchScenario(this.id, this.format);

  final String id;
  final String format;
}

final class BenchSize {
  const BenchSize(this.width, this.height);

  final int width;
  final int height;
}

/// Platform code supplies only public API construction, invocation and packing.
abstract interface class MatrixAdapter {
  String get version;

  Future<void> initialize();
  Object create(BenchScenario scenario, BenchInput input);
  Object flipVertical(Object image);
  Uint8List packActiveSamples(Object result);
}

final class MatrixMetadata {
  const MatrixMetadata({
    required this.platform,
    required this.machine,
    required this.sha,
    required this.tree,
    required this.compiler,
    required this.flags,
    this.powerPlan = '',
    this.affinity = '',
  });

  final String platform;
  final String machine;
  final String sha;
  final String tree;
  final String compiler;
  final String flags;
  final String powerPlan;
  final String affinity;
}

final class BenchInput {
  BenchInput(this.format, this.width, this.height, this.planes);

  final String format;
  final int width;
  final int height;
  final List<Uint8List> planes;

  String get checksum {
    final joined = BytesBuilder(copy: false);
    for (final plane in planes) {
      joined.add(plane);
    }
    return sha256.convert(joined.takeBytes()).toString();
  }

  static BenchInput generate(String format, int width, int height) {
    final lumaLength = width * height;
    final chromaLength = ((width + 1) ~/ 2) * ((height + 1) ~/ 2);
    final planes = switch (format) {
      'I420' => <Uint8List>[_bytes(lumaLength, 0x2026A001), _bytes(chromaLength, 0x2026A002), _bytes(chromaLength, 0x2026A003)],
      'NV12' => _nv12(lumaLength, chromaLength),
      'BGRA' => <Uint8List>[_bgra(width * height)],
      _ => throw ArgumentError.value(format, 'format'),
    };
    final input = BenchInput(format, width, height, planes);
    final key = '${format.toLowerCase()}_${width}x$height';
    final expected = _inputSha[key];
    if (expected == null || input.checksum != expected) {
      throw StateError('Input checksum mismatch for $key: ${input.checksum}; expected $expected');
    }
    return input;
  }

  static List<Uint8List> _nv12(int lumaLength, int chromaLength) {
    final u = _bytes(chromaLength, 0x2026A002);
    final v = _bytes(chromaLength, 0x2026A003);
    final uv = Uint8List(chromaLength * 2);
    for (var index = 0; index < chromaLength; index++) {
      uv[2 * index] = u[index];
      uv[2 * index + 1] = v[index];
    }
    return <Uint8List>[_bytes(lumaLength, 0x2026A001), uv];
  }

  static Uint8List _bytes(int length, int seed) {
    final output = Uint8List(length);
    var state = seed;
    for (var index = 0; index < length; index++) {
      state ^= (state << 13) & 0xffffffff;
      state ^= state >> 17;
      state ^= (state << 5) & 0xffffffff;
      state &= 0xffffffff;
      output[index] = state >> 24;
    }
    return output;
  }

  static Uint8List _bgra(int pixels) {
    final output = Uint8List(pixels * 4);
    var state = 0x2026A004;
    int next() {
      state ^= (state << 13) & 0xffffffff;
      state ^= state >> 17;
      state ^= (state << 5) & 0xffffffff;
      state &= 0xffffffff;
      return state >> 24;
    }

    for (var pixel = 0; pixel < pixels; pixel++) {
      output[4 * pixel] = next();
      output[4 * pixel + 1] = next();
      output[4 * pixel + 2] = next();
      output[4 * pixel + 3] = 255;
    }
    return output;
  }
}

/// Runs all 18 fixed MEAS-02 rows without using platform libraries.
Future<List<String>> runMeas02Matrix(MatrixAdapter adapter, MatrixMetadata metadata) async {
  await adapter.initialize();
  final rows = <String>[];
  for (final round in benchRounds) {
    for (final size in benchSizes) {
      for (final scenario in benchScenarios) {
        final input = BenchInput.generate(scenario.format, size.width, size.height);
        rows.add(_runRow(adapter, metadata, round, scenario, input));
      }
    }
  }
  return rows;
}

String _runRow(MatrixAdapter adapter, MatrixMetadata metadata, int round, BenchScenario scenario, BenchInput input) {
  final started = DateTime.now().toUtc();
  var status = 'OK';
  var reason = '';
  var warmup = 0;
  var checksum = '';
  final samples = <double>[];
  try {
    double invoke({bool checksumOutput = false}) {
      // The fresh image must be outside the measured public call.
      final image = adapter.create(scenario, input);
      final stopwatch = Stopwatch()..start();
      final result = adapter.flipVertical(image);
      stopwatch.stop();
      if (checksumOutput) {
        final current = sha256.convert(adapter.packActiveSamples(result)).toString();
        if (checksum.isEmpty) {
          checksum = current;
        } else if (checksum != current) {
          throw StateError('nondeterministic output: $checksum -> $current');
        }
      }
      return stopwatch.elapsedMicroseconds / 1000;
    }

    final calibration = invoke();
    warmup = 1;
    if (calibration > 120000) {
      status = 'TIMEOUT';
      reason = 'calibration exceeded 120 s';
    } else {
      final extraWarmup = calibration < 5
          ? 10
          : calibration < 100
          ? 5
          : calibration < 2000
          ? 2
          : calibration < 30000
          ? 1
          : 0;
      final count = calibration < 5
          ? 50
          : calibration < 100
          ? 30
          : calibration < 2000
          ? 15
          : calibration < 30000
          ? 5
          : 3;
      for (var index = 0; index < extraWarmup; index++) {
        invoke();
      }
      warmup += extraWarmup;
      for (var index = 0; index < count; index++) {
        samples.add(invoke(checksumOutput: index == 0 || index == count - 1));
      }
    }
  } on UnsupportedError catch (error) {
    status = 'UNSUPPORTED';
    reason = error.toString();
  } catch (error) {
    status = 'ERROR:call';
    reason = error.toString();
  }

  final sorted = samples.toList()..sort();
  final count = sorted.length;
  final median = count == 0
      ? 0.0
      : count.isOdd
      ? sorted[count ~/ 2]
      : (sorted[count ~/ 2 - 1] + sorted[count ~/ 2]) / 2;
  final mean = count == 0 ? 0.0 : sorted.reduce((a, b) => a + b) / count;
  final variance = count < 2 ? 0.0 : sorted.map((value) => math.pow(value - mean, 2)).reduce((a, b) => a + b) / (count - 1);
  final upper = count == 0
      ? 0.0
      : count >= 20
      ? sorted[(count * 0.95).ceil() - 1]
      : sorted.last;
  String milliseconds(double value) => value.toStringAsFixed(4);
  return _csv(<String>[
    metadata.platform,
    metadata.machine,
    '$round',
    adapter.version,
    metadata.sha,
    metadata.tree,
    scenario.id,
    'flip',
    scenario.format,
    scenario.format,
    '${input.width}',
    '${input.height}',
    'direction=V',
    'tight',
    'dart',
    status,
    reason,
    '$warmup',
    '$count',
    count > 0 ? milliseconds(sorted.first) : '',
    count > 0 ? milliseconds(median) : '',
    count > 0 ? milliseconds(upper) : '',
    count > 0 ? (count >= 20 ? 'p95' : 'max') : '',
    count > 0 ? milliseconds(mean) : '',
    count > 0 ? milliseconds(math.sqrt(variance)) : '',
    count > 0 ? milliseconds(median == 0 ? 0 : (upper - median) / median) : '',
    checksum,
    samples.map(milliseconds).join(';'),
    started.toIso8601String(),
    DateTime.now().toUtc().toIso8601String(),
    metadata.compiler,
    metadata.flags,
    metadata.powerPlan,
    metadata.affinity,
  ]);
}

String _csv(List<String> fields) {
  if (fields.length != 34) throw StateError('Expected 34 CSV fields, got ${fields.length}');
  return fields.map((field) => field.replaceAll(RegExp(r'[,\r\n"]'), ';')).join(',');
}

const _inputSha = <String, String>{
  'i420_1920x1080': '71c06f9341e998b2308625dedffb1555a57cacdb4b1479630039dab4febfc0b4',
  'nv12_1920x1080': 'c08dec9993df462f7d96eb3e765ab97b2ac69d86f7bf13e60740ce5c3d4ee652',
  'bgra_1920x1080': '4a107f2e1d3895761980b2c7e5eecc1a587bffc27626b96868c9c94306dc22a9',
  'i420_4000x3000': '282dc210cc232feb071c75483df66bc14373c7c90d1842a8c9136a3778ceb287',
  'nv12_4000x3000': 'cf70f5e6e0ccee46a5615ba49318d698600ec6a569280d4cc881f38be966d0aa',
  'bgra_4000x3000': '46cc62c75007006f05e66a39eaf8257a90091f9a97617ca16676a043a5d75146',
};
