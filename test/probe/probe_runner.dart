import 'dart:io';
import 'dart:math' as math;

typedef ProbeInvocationFactory = PreparedProbeInvocation Function();

/// A fresh source and one public operation invocation prepared outside timing.
class PreparedProbeInvocation {
  const PreparedProbeInvocation({required this.call, required this.hash});

  final Object Function() call;
  final String Function(Object result) hash;
}

/// Timing parameters owned by the benchmark executor, never production code.
class ProbeTimingConfig {
  const ProbeTimingConfig({required this.warmups, required this.samples, required this.strict, this.injectedDelay = Duration.zero})
    : assert(warmups >= 0),
      assert(samples > 0);

  final int warmups;
  final int samples;
  final bool strict;

  /// Test-only delay for the regression control; it is outside `lib/`.
  final Duration injectedDelay;
}

class ProbeBaseline {
  const ProbeBaseline({required this.hash, required this.medianMicros, required this.spreadPercent});

  factory ProbeBaseline.fromJson(Map<String, dynamic> json) => ProbeBaseline(
    hash: json['hash']! as String,
    medianMicros: json['medianMicros']! as int,
    spreadPercent: (json['spreadPercent']! as num).toDouble(),
  );

  final String hash;
  final int medianMicros;
  final double spreadPercent;

  Map<String, Object> toJson() => {'hash': hash, 'medianMicros': medianMicros, 'spreadPercent': spreadPercent};
}

class ProbeRun {
  const ProbeRun({
    required this.operation,
    required this.scenario,
    required this.width,
    required this.height,
    required this.hash,
    required this.samplesMicros,
    required this.sampleHashes,
    required this.medianMicros,
    required this.spreadPercent,
    required this.verdict,
    required this.comparison,
    required this.deltaPercent,
    required this.thresholdPercent,
    required this.baseline,
  });

  final String operation;
  final String scenario;
  final int width;
  final int height;
  final String hash;
  final List<int> samplesMicros;
  final List<String> sampleHashes;
  final int medianMicros;
  final double spreadPercent;
  final String verdict;
  final String comparison;
  final double? deltaPercent;
  final double? thresholdPercent;
  final ProbeBaseline? baseline;

  String get id => '$operation/$scenario/${width}x$height';

  String get line {
    final baselineText = baseline == null ? 'baseline none' : 'baseline ${(baseline!.medianMicros / 1000).toStringAsFixed(3)}';
    final spreadText = spreadPercent.toStringAsFixed(1);
    return 'PROBE $operation $scenario ${width}x$height $verdict ${(medianMicros / 1000).toStringAsFixed(3)} ms ($baselineText, ±$spreadText%) $comparison';
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'operation': operation,
    'scenario': scenario,
    'size': {'width': width, 'height': height},
    'hash': hash,
    'samplesMicros': samplesMicros,
    'sampleHashes': sampleHashes,
    'medianMicros': medianMicros,
    'spreadPercent': spreadPercent,
    'verdict': verdict,
    'comparison': comparison,
    'deltaPercent': deltaPercent,
    'thresholdPercent': thresholdPercent,
    'baseline': baseline?.toJson(),
  };
}

/// Runs warmups and samples, then compares a scenario with its recorded base.
///
/// Operations live in [ProbeInvocationFactory] providers; this executor only measures,
/// hashes, sorts samples, and decides the timing verdict.
ProbeRun runProbe({
  required String operation,
  required String scenario,
  required int width,
  required int height,
  required ProbeInvocationFactory prepare,
  required ProbeTimingConfig config,
  ProbeBaseline? baseline,
}) {
  final correctnessInvocation = prepare();
  final hash = correctnessInvocation.hash(correctnessInvocation.call());
  for (var index = 0; index < config.warmups; index++) {
    prepare().call();
  }

  final samples = <int>[];
  final sampleHashes = <String>[];
  for (var index = 0; index < config.samples; index++) {
    final invocation = prepare();
    final watch = Stopwatch()..start();
    final result = invocation.call();
    if (config.injectedDelay > Duration.zero) {
      _sleep(config.injectedDelay);
    }
    watch.stop();
    samples.add(watch.elapsedMicroseconds);
    sampleHashes.add(invocation.hash(result));
  }
  samples.sort();
  final median = samples[samples.length ~/ 2];
  final spread = _spreadPercent(samples, median);

  final hashMatches = baseline == null || baseline.hash == hash;
  final sampleHashesMatch = sampleHashes.every((sampleHash) => sampleHash == hash);
  if (!sampleHashesMatch) {
    return ProbeRun(
      operation: operation,
      scenario: scenario,
      width: width,
      height: height,
      hash: hash,
      samplesMicros: samples,
      sampleHashes: sampleHashes,
      medianMicros: median,
      spreadPercent: spread,
      verdict: 'FAIL',
      comparison: 'SAMPLE-HASH-MISMATCH',
      deltaPercent: null,
      thresholdPercent: null,
      baseline: baseline,
    );
  }
  if (!hashMatches) {
    return ProbeRun(
      operation: operation,
      scenario: scenario,
      width: width,
      height: height,
      hash: hash,
      samplesMicros: samples,
      sampleHashes: sampleHashes,
      medianMicros: median,
      spreadPercent: spread,
      verdict: 'FAIL',
      comparison: 'HASH-MISMATCH',
      deltaPercent: null,
      thresholdPercent: null,
      baseline: baseline,
    );
  }
  if (baseline == null) {
    return ProbeRun(
      operation: operation,
      scenario: scenario,
      width: width,
      height: height,
      hash: hash,
      samplesMicros: samples,
      sampleHashes: sampleHashes,
      medianMicros: median,
      spreadPercent: spread,
      verdict: 'PASS',
      comparison: 'NO-BASELINE',
      deltaPercent: null,
      thresholdPercent: null,
      baseline: null,
    );
  }

  final baselineMedian = math.max(1, baseline.medianMicros);
  final delta = (median - baselineMedian) * 100 / baselineMedian;
  final threshold = math.max(15, 2 * math.max(spread, baseline.spreadPercent)).toDouble();
  final comparison = delta > threshold
      ? 'SLOWER'
      : delta < -threshold
      ? 'FASTER'
      : 'SAME';
  return ProbeRun(
    operation: operation,
    scenario: scenario,
    width: width,
    height: height,
    hash: hash,
    samplesMicros: samples,
    sampleHashes: sampleHashes,
    medianMicros: median,
    spreadPercent: spread,
    verdict: comparison == 'SLOWER' && config.strict ? 'FAIL' : 'PASS',
    comparison: comparison,
    deltaPercent: delta,
    thresholdPercent: threshold,
    baseline: baseline,
  );
}

double _spreadPercent(List<int> samples, int median) {
  if (median == 0) return 0;
  return (samples.last - samples.first) * 100 / median;
}

void _sleep(Duration duration) => sleep(duration);
