@Tags(['probe'])
library;
import 'package:flutter_test/flutter_test.dart';

import 'probe_selection.dart';

void main() {
  test('selects exact operation and format tokens in matrix order', () {
    final selection = ProbeSelection.fromSelectors(operationSelector: 'crop,gray,gray', formatSelector: 'nv12,i420,nv12');

    expect(selection.operations, ['gray', 'crop']);
    expect(selection.formats, ['i420', 'nv12']);
    expect(selection.caseIds, everyElement(contains(RegExp(r'^(i420|nv12) '))));
    expect(selection.caseIds, everyElement(contains(RegExp(r' (gray|crop)$'))));
  });

  test('reports the gray slice and VM dart defines override environment', () {
    final selection = ProbeSelection.fromSelectors(operationSelector: 'gray', formatSelector: null);
    final selectors = probeSelectorsForVm(
      dartOperationsDefined: true,
      dartOperations: 'gray',
      dartFormatsDefined: false,
      dartFormats: '',
      environment: const {'PROBE_OPS': 'crop', 'PROBE_FORMATS': 'i420'},
    );

    expect(selection.caseIds, hasLength(54));
    expect(selection.scope, 'PROBE scope: ops=gray formats=all cases=54/1188');
    expect(selectors.operations, 'gray');
    expect(selectors.formats, 'i420');
  });

  test('rejects invalid and empty selectors', () {
    expect(() => ProbeSelection.fromSelectors(operationSelector: 'unknown', formatSelector: null), throwsArgumentError);
    expect(() => ProbeSelection.fromSelectors(operationSelector: 'all', formatSelector: null), throwsArgumentError);
    expect(() => ProbeSelection.fromSelectors(operationSelector: null, formatSelector: 'all'), throwsArgumentError);
    expect(() => ProbeSelection.fromSelectors(operationSelector: '', formatSelector: null), throwsArgumentError);
    expect(
      () => ProbeSelection.fromSelectors(operationSelector: 'gray', formatSelector: 'bgra8888', cases: const ['i420 1x1 tight gray']),
      throwsArgumentError,
    );
  });
}
