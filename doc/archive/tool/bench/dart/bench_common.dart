import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// A public API call is timed; image creation and checksums stay outside it.
abstract interface class BenchAdapter {
  String get version;
  Future<void> initialize();
  Object create(Scenario scenario, InputFrame input);
  Object call(Scenario scenario, Object image, InputFrame input);
  Uint8List bytes(Object result);
}

final class Scenario {
  Scenario(this.id)
    : parts = id.split('.'),
      operation = id.split('.').first,
      sourceFormat = id == 'SWAP.NV12' ? 'NV12' : id.split('.')[1],
      destinationFormat = id.startsWith('CVT.') ? id.split('.')[2] : (id == 'SWAP.NV12' ? 'NV12' : id.split('.')[1]) {
    final p = parts;
    final valid = switch (operation) {
      'CVT' =>
        p.length == 3 &&
            <String>{'I420', 'NV12', 'BGRA', 'RGBA'}.contains(sourceFormat) &&
            <String>{'I420', 'NV12', 'BGRA'}.contains(destinationFormat),
      'FLIP' => p.length == 3 && <String>{'H', 'V'}.contains(p[2]) && _imageFormat,
      'ROT' => p.length == 3 && <String>{'0', '90', '180', '270'}.contains(p[2]) && _imageFormat,
      'CROP' => p.length == 3 && <String>{'EVEN', 'ODD'}.contains(p[2]) && _imageFormat,
      'GRAY' || 'BW' || 'NEG' => p.length == 3 && <String>{'FULL', 'ROI'}.contains(p[2]) && _imageFormat,
      'SWAP' => id == 'SWAP.NV12',
      'BOX' || 'MEAN' =>
        (p.length == 3 || p.length == 4) &&
            <String>{'R1', 'R10', 'R256'}.contains(p[2]) &&
            (p.length == 3 || (p[2] == 'R10' && p[3] == 'ROI')) &&
            _imageFormat,
      'GAUSS' => p.length == 3 && <String>{'R2S2', 'R10S10'}.contains(p[2]) && _imageFormat,
      _ => false,
    };
    if (!valid) throw FormatException('Unknown scenario: $id');
  }

  final String id;
  final List<String> parts;
  final String operation;
  final String sourceFormat;
  final String destinationFormat;

  bool get _imageFormat => <String>{'I420', 'NV12', 'BGRA'}.contains(sourceFormat);
  bool get roi => parts.last == 'ROI';
  bool get publicAvailable => !(<String>{'GRAY', 'BW', 'NEG'}.contains(operation) && roi);
  int get radius => parts.length > 2 && parts[2].startsWith('R') ? int.parse(parts[2].substring(1).split('S').first) : 0;
  int get sigma => operation == 'GAUSS' ? int.parse(parts[2].split('S').last) : 0;
  int get degrees => operation == 'ROT' ? int.parse(parts[2]) : 0;

  String params(int width, int height) => switch (operation) {
    'FLIP' => 'direction=${parts[2]}',
    'ROT' => 'degrees=$degrees',
    'CROP' =>
      'left=${width ~/ 4 + (parts[2] == 'ODD' ? 1 : 0)};top=${height ~/ 4 + (parts[2] == 'ODD' ? 1 : 0)};width=${width ~/ 2 - (parts[2] == 'ODD' ? 1 : 0)};height=${height ~/ 2 - (parts[2] == 'ODD' ? 1 : 0)}',
    'BOX' || 'MEAN' => 'radius=$radius;region=${roi ? '${width ~/ 4}:${height ~/ 4}:${3 * width ~/ 4}:${3 * height ~/ 4}' : 'off'}',
    'GAUSS' => 'radius=$radius;sigma=$sigma',
    'GRAY' || 'BW' || 'NEG' => 'region=${roi ? 'on' : 'off'}',
    _ => '-',
  };
}

final class InputFrame {
  InputFrame(this.format, this.width, this.height, this.planes);

  final String format;
  final int width;
  final int height;
  final List<Uint8List> planes;

  String get checksum {
    final bytes = BytesBuilder(copy: false);
    for (final plane in planes) {
      bytes.add(plane);
    }
    return sha256.convert(bytes.takeBytes()).toString();
  }

  static InputFrame generate(String format, int width, int height) {
    final ySize = width * height;
    final cSize = ((width + 1) ~/ 2) * ((height + 1) ~/ 2);
    final planes = switch (format) {
      'I420' => <Uint8List>[_fill(ySize, 0x2026A001), _fill(cSize, 0x2026A002), _fill(cSize, 0x2026A003)],
      'NV12' => _nv12(ySize, cSize),
      'BGRA' || 'RGBA' => <Uint8List>[_rgba(width * height, format == 'RGBA')],
      _ => throw ArgumentError.value(format),
    };
    final frame = InputFrame(format, width, height, planes);
    final key = '${format.toLowerCase()}_${width}x$height';
    final expected = _inputSha[key];
    if (expected == null || frame.checksum != expected) {
      throw StateError('Input checksum for $key: ${frame.checksum}, expected $expected');
    }
    return frame;
  }

  static List<Uint8List> _nv12(int ySize, int cSize) {
    final u = _fill(cSize, 0x2026A002);
    final v = _fill(cSize, 0x2026A003);
    final uv = Uint8List(cSize * 2);
    for (var i = 0; i < cSize; i++) {
      uv[2 * i] = u[i];
      uv[2 * i + 1] = v[i];
    }
    return <Uint8List>[_fill(ySize, 0x2026A001), uv];
  }

  static Uint8List _fill(int length, int seed) {
    final bytes = Uint8List(length);
    var state = seed;
    for (var i = 0; i < length; i++) {
      state ^= (state << 13) & 0xffffffff;
      state ^= state >> 17;
      state ^= (state << 5) & 0xffffffff;
      state &= 0xffffffff;
      bytes[i] = state >> 24;
    }
    return bytes;
  }

  static Uint8List _rgba(int pixels, bool rgba) {
    final data = Uint8List(pixels * 4);
    var state = 0x2026A004;
    int next() {
      state ^= (state << 13) & 0xffffffff;
      state ^= state >> 17;
      state ^= (state << 5) & 0xffffffff;
      state &= 0xffffffff;
      return state >> 24;
    }

    for (var i = 0; i < pixels; i++) {
      final b = next();
      final g = next();
      final r = next();
      data[4 * i] = rgba ? r : b;
      data[4 * i + 1] = g;
      data[4 * i + 2] = rgba ? b : r;
      data[4 * i + 3] = 255;
    }
    return data;
  }
}

const _inputSha = <String, String>{
  'i420_1920x1080': '71c06f9341e998b2308625dedffb1555a57cacdb4b1479630039dab4febfc0b4',
  'nv12_1920x1080': 'c08dec9993df462f7d96eb3e765ab97b2ac69d86f7bf13e60740ce5c3d4ee652',
  'bgra_1920x1080': '4a107f2e1d3895761980b2c7e5eecc1a587bffc27626b96868c9c94306dc22a9',
  'rgba_1920x1080': '1484337a8687599525ff9941412f83613e25e64b32cb9906f2cdf34f0d4238d7',
  'i420_4000x3000': '282dc210cc232feb071c75483df66bc14373c7c90d1842a8c9136a3778ceb287',
  'nv12_4000x3000': 'cf70f5e6e0ccee46a5615ba49318d698600ec6a569280d4cc881f38be966d0aa',
  'bgra_4000x3000': '46cc62c75007006f05e66a39eaf8257a90091f9a97617ca16676a043a5d75146',
  'rgba_4000x3000': '7775779ef9d1ad4c02c11b50d26cec342666863bdb4a1019b6317bb802ad0328',
};

const csvHeader =
    'platform,machine,round,version,sha,src_tree_id,scenario_id,op,src_fmt,dst_fmt,width,height,params,layout,level,status,reason,warmup,n,min_ms,median_ms,p95_or_max_ms,upper_kind,mean_ms,stdev_ms,spread,checksum_sha256,raw_ms,started_at,finished_at,compiler,flags,power_plan,affinity';

Future<int> runBench(List<String> args, BenchAdapter adapter) async {
  final options = <String, String>{};
  for (var i = 0; i < args.length; i += 2) {
    if (i + 1 >= args.length || !args[i].startsWith('--')) throw FormatException('Expected --key value pairs');
    options[args[i].substring(2)] = args[i + 1];
  }
  String required(String key) => options[key] ?? (throw FormatException('Missing --$key'));
  final scenario = Scenario(required('scenario'));
  final size = required('size').split('x').map(int.parse).toList();
  if (size.length != 2 || size.any((v) => v <= 0)) throw FormatException('Invalid --size');
  final width = size[0];
  final height = size[1];
  if (scenario.radius == 256 && (width != 1920 || height != 1080)) throw FormatException('R256 is 1080p only');
  final input = InputFrame.generate(scenario.sourceFormat, width, height);
  await adapter.initialize();
  final started = DateTime.now().toUtc();
  stderr.writeln('ready');
  var status = 'OK';
  var reason = '';
  var warmup = 0;
  final samples = <double>[];
  var checksum = '';
  if (!scenario.publicAvailable) {
    status = 'N/A';
    reason = 'public API has no region parameter for this effect';
  } else {
    double iterate({bool hash = false}) {
      final image = adapter.create(scenario, input);
      final watch = Stopwatch()..start();
      final result = adapter.call(scenario, image, input);
      watch.stop();
      if (hash) {
        final current = sha256.convert(adapter.bytes(result)).toString();
        if (checksum.isEmpty) {
          checksum = current;
        } else if (checksum != current) {
          throw StateError('Output changed: $checksum -> $current');
        }
      }
      return watch.elapsedMicroseconds / 1000;
    }

    try {
      final calibration = iterate();
      warmup = 1;
      if (calibration > 120000) {
        status = 'TIMEOUT';
        reason = 'calibration exceeded 120 s';
      } else {
        final extra = calibration < 5
            ? 10
            : calibration < 100
            ? 5
            : calibration < 2000
            ? 2
            : calibration < 30000
            ? 1
            : 0;
        final n = calibration < 5
            ? 50
            : calibration < 100
            ? 30
            : calibration < 2000
            ? 15
            : calibration < 30000
            ? 5
            : 3;
        stderr.writeln('calibrated t1_ms=$calibration warmup=$extra n=$n');
        for (var i = 0; i < extra; i++) {
          iterate();
        }
        warmup += extra;
        for (var i = 0; i < n; i++) {
          samples.add(iterate(hash: i == 0 || i == n - 1));
        }
      }
    } on UnsupportedError catch (error) {
      status = 'UNSUPPORTED';
      reason = error.toString();
    } catch (error) {
      status = 'ERROR:call';
      reason = error.toString();
    }
  }

  final sorted = samples.toList()..sort();
  final n = sorted.length;
  final median = n == 0
      ? 0.0
      : n.isOdd
      ? sorted[n ~/ 2]
      : (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
  final mean = n == 0 ? 0.0 : sorted.reduce((a, b) => a + b) / n;
  final stdev = n < 2 ? 0.0 : math.sqrt(sorted.map((v) => math.pow(v - mean, 2)).reduce((a, b) => a + b) / (n - 1));
  final upper = n == 0
      ? 0.0
      : n >= 20
      ? sorted[(0.95 * n).ceil() - 1]
      : sorted.last;
  String ms(double value) => value.toStringAsFixed(4);
  final fields = <String>[
    options['platform'] ?? 'windows',
    options['machine'] ?? Platform.localHostname,
    required('round'),
    adapter.version,
    required('sha'),
    required('tree'),
    scenario.id,
    scenario.operation.toLowerCase(),
    scenario.sourceFormat,
    scenario.destinationFormat,
    '$width',
    '$height',
    scenario.params(width, height),
    'tight',
    'dart',
    status,
    reason,
    '$warmup',
    '$n',
    n == 0 ? '' : ms(sorted.first),
    n == 0 ? '' : ms(median),
    n == 0 ? '' : ms(upper),
    n == 0
        ? ''
        : n >= 20
        ? 'p95'
        : 'max',
    n == 0 ? '' : ms(mean),
    n == 0 ? '' : ms(stdev),
    n == 0 ? '' : ms(median == 0 ? 0 : (upper - median) / median),
    checksum,
    samples.map(ms).join(';'),
    started.toIso8601String(),
    DateTime.now().toUtc().toIso8601String(),
    options['compiler'] ?? 'Flutter AOT',
    options['flags'] ?? 'release',
    options['power-plan'] ?? '',
    options['affinity'] ?? '',
  ];
  final line = fields.map((f) => f.replaceAll(RegExp(r'[,"\r\n]'), ';')).join(',');
  final output = File(required('out'));
  await output.parent.create(recursive: true);
  if (!await output.exists()) await output.writeAsString('$csvHeader\n');
  await output.writeAsString('$line\n', mode: FileMode.append);
  stdout.writeln(line);
  return status == 'OK' || status == 'N/A' || status == 'UNSUPPORTED' ? 0 : 1;
}
