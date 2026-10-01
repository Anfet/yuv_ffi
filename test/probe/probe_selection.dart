import 'cases.dart';
import 'probe_support.dart';

class ProbeSelectorValues {
  const ProbeSelectorValues({this.operations, this.formats});

  final String? operations;
  final String? formats;

  bool get hasSelectors => operations != null || formats != null;
}

ProbeSelectorValues probeSelectorsForVm({
  required bool dartOperationsDefined,
  required String dartOperations,
  required bool dartFormatsDefined,
  required String dartFormats,
  required Map<String, String> environment,
}) => ProbeSelectorValues(
  operations: dartOperationsDefined ? dartOperations : environment['PROBE_OPS'],
  formats: dartFormatsDefined ? dartFormats : environment['PROBE_FORMATS'],
);

class ProbeSelection {
  ProbeSelection._({required this.caseIds, required this.operations, required this.formats, required this.hasSelectors});

  factory ProbeSelection.fromSelectors({required String? operationSelector, required String? formatSelector, Iterable<String>? cases}) {
    final matrix = cases ?? probeCaseIds;
    final knownOperations = <String>{for (final id in matrix) ProbeCase(id).operation};
    const knownFormats = {'i420', 'nv12', 'bgra8888'};
    final operations = _parseSelector(operationSelector, name: 'PROBE_OPS', known: knownOperations);
    final formats = _parseSelector(formatSelector, name: 'PROBE_FORMATS', known: knownFormats);
    final caseIds = matrix
        .where((id) {
          final probeCase = ProbeCase(id);
          return (operations == null || operations.contains(probeCase.operation)) && (formats == null || formats.contains(probeCase.format));
        })
        .toList(growable: false);
    if (caseIds.isEmpty) {
      throw ArgumentError('PROBE_OPS and PROBE_FORMATS selected no probe cases.');
    }
    return ProbeSelection._(
      caseIds: caseIds,
      operations: _scopeTokens(operations, knownOperations),
      formats: _scopeTokens(formats, knownFormats),
      hasSelectors: operationSelector != null || formatSelector != null,
    );
  }

  final List<String> caseIds;
  final List<String>? operations;
  final List<String>? formats;
  final bool hasSelectors;

  String get scope =>
      'PROBE scope: ops=${operations?.join(',') ?? 'all'} '
      'formats=${formats?.join(',') ?? 'all'} '
      'cases=${caseIds.length}/${probeCaseIds.length}';
}

Set<String>? _parseSelector(String? raw, {required String name, required Set<String> known}) {
  if (raw == null || raw == 'all') return null;
  final tokens = raw.split(',');
  for (final token in tokens) {
    if (token.isEmpty) {
      throw ArgumentError('$name contains an empty token.');
    }
    if (!known.contains(token)) {
      throw ArgumentError('$name contains an unknown token: $token.');
    }
  }
  return tokens.toSet();
}

List<String>? _scopeTokens(Set<String>? selected, Set<String> known) =>
    selected == null ? null : known.where(selected.contains).toList(growable: false);
