import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/reference/test_pattern_reference.dart';

const _manifestPath = 'test/reference/test_pattern_512/manifest.json';
const _sourcePath = 'test/assets/test_pattern_512.png';

void main() {
  group('YUV-10 test_pattern_512 reference manifest', () {
    late Map<String, dynamic> manifest;

    setUpAll(() async {
      manifest = jsonDecode(await File(_manifestPath).readAsString()) as Map<String, dynamic>;
    });

    test('pins the source asset hash and decoded RGBA dimensions', () async {
      final source = manifest['source'] as Map<String, dynamic>;
      final sourceBytes = await File(_sourcePath).readAsBytes();
      final decoded = decodePng(sourceBytes);

      expect(source['sha256'], sha256Hex(sourceBytes));
      expect(decoded.width, source['decoded']['width']);
      expect(decoded.height, source['decoded']['height']);
      expect(source['decoded']['pixelFormat'], 'RGBA8888');
      expect(source['decoded']['colorSpaceAssumption'], contains('sRGB'));
    });

    test('pins every referenced artifact by path, length, and SHA-256', () async {
      final artifacts = manifest['artifacts'] as Map<String, dynamic>;
      expect(artifacts, isNotEmpty);

      for (final entry in artifacts.entries) {
        final metadata = entry.value as Map<String, dynamic>;
        final file = File('test/reference/test_pattern_512/${metadata['path']}');
        final bytes = await file.readAsBytes();
        expect(file.existsSync(), isTrue, reason: entry.key);
        expect(bytes.length, metadata['byteLength'], reason: entry.key);
        expect(sha256Hex(bytes), metadata['sha256'], reason: entry.key);
      }
      final artifactFiles = Directory(
        'test/reference/test_pattern_512/artifacts',
      ).listSync(recursive: true).whereType<File>().map((file) => file.uri.pathSegments.last).toSet();
      expect(artifactFiles, equals(artifacts.keys.toSet()));
    });

    test('covers each mandatory matrix group with stable unique case IDs', () {
      final cases = (manifest['cases'] as List<dynamic>).cast<Map<String, dynamic>>();
      final ids = cases.map((entry) => entry['id'] as String).toList();
      final groups = cases.map((entry) => entry['group']).toSet();
      final requiredGroups = <String>{
        'Construction',
        'Input',
        'Output',
        'Format',
        'Chroma',
        'Geometry',
        'Effect',
        'Blur',
        'State',
        'Bytes',
        'I/O',
        'Flutter',
      };

      expect(ids.toSet(), hasLength(ids.length));
      expect(groups, containsAll(requiredGroups));
      expect(cases, hasLength(greaterThanOrEqualTo(100)));
      expect(
        cases.map((entry) => entry['operation']).toSet(),
        containsAll(<String>{
          'YuvImage.bgra',
          'YuvImage.i420',
          'YuvImage.nv21',
          'fromRgba8888',
          'toBgra8888',
          'toYuvBgra8888',
          'toYuvI420',
          'toYuvNv21',
          'swapNv',
          'crop',
          'rotate',
          'flipHorizontally',
          'flipVertically',
          'grayscale',
          'blackwhite',
          'negate',
          'gaussianBlur',
          'boxBlur',
          'meanBlur',
          'copy',
          'getBytes',
          'save/load',
          'toImage',
        }),
      );
      expect(manifest['coverage']['requiredMatrixRows'], 18);
      expect(manifest['coverage']['caseCount'], cases.length);
    });

    test('predeclares comparison tolerances and raw plane references for every case', () {
      final tolerances = manifest['tolerances'] as Map<String, dynamic>;
      final artifacts = manifest['artifacts'] as Map<String, dynamic>;
      final cases = (manifest['cases'] as List<dynamic>).cast<Map<String, dynamic>>();

      for (final caseEntry in cases) {
        final comparison = caseEntry['comparison'] as String;
        final expected = caseEntry['expected'] as Map<String, dynamic>;
        final rawPlaneReference = expected['rawPlaneReference'] as Map<String, dynamic>;
        final planes = rawPlaneReference['planes'] as List<dynamic>;

        expect(tolerances[comparison], isA<Map<String, dynamic>>(), reason: caseEntry['id']);
        expect(expected['dimensions']['width'], greaterThan(0), reason: caseEntry['id']);
        expect(expected['dimensions']['height'], greaterThan(0), reason: caseEntry['id']);
        expect(artifacts, contains(expected['artifact']), reason: caseEntry['id']);
        expect(planes, isNotEmpty, reason: caseEntry['id']);
        for (final plane in planes.cast<Map<String, dynamic>>()) {
          expect(plane['sha256'], hasLength(64), reason: caseEntry['id']);
          expect(plane['byteLength'], greaterThan(0), reason: caseEntry['id']);
        }
      }
    });

    test('links raw plane geometry and special operations to their own expected data', () {
      final cases = (manifest['cases'] as List<dynamic>).cast<Map<String, dynamic>>();
      Map<String, dynamic> byId(String id) => cases.singleWhere((entry) => entry['id'] == id);
      List<Map<String, dynamic>> planes(Map<String, dynamic> entry) =>
          (entry['expected']['rawPlaneReference']['planes'] as List<dynamic>).cast<Map<String, dynamic>>();

      for (final entry in cases) {
        final expected = entry['expected'] as Map<String, dynamic>;
        final dimensions = expected['dimensions'] as Map<String, dynamic>;
        final width = dimensions['width'] as int;
        final height = dimensions['height'] as int;
        final outputPlanes = planes(entry);
        expect(outputPlanes.first['height'], height, reason: entry['id']);
        for (final plane in outputPlanes) {
          expect(plane['byteLength'], plane['height'] * plane['rowStride'], reason: entry['id']);
        }
        if (expected['format'] == 'i420') {
          expect(outputPlanes, hasLength(3), reason: entry['id']);
          expect(outputPlanes[1]['height'], (height + 1) ~/ 2, reason: entry['id']);
          expect(outputPlanes[2]['height'], (height + 1) ~/ 2, reason: entry['id']);
        }
        if (expected['format'] == 'nv21') {
          expect(outputPlanes, hasLength(2), reason: entry['id']);
          expect(outputPlanes[1]['height'], (height + 1) ~/ 2, reason: entry['id']);
          expect(outputPlanes[1]['pixelStride'], 2, reason: entry['id']);
        }
        expect(outputPlanes.first['rowStride'], greaterThanOrEqualTo(width), reason: entry['id']);
      }

      final sourceNv = planes(byId('INPUT-FROM-RGBA-NV21'));
      final once = planes(byId('CHROMA-SWAP-NV21-1'));
      final twice = planes(byId('CHROMA-SWAP-NV21-2'));
      expect(once.first['sha256'], sourceNv.first['sha256']);
      expect(once[1]['sha256'], isNot(sourceNv[1]['sha256']));
      expect(twice[1]['sha256'], sourceNv[1]['sha256']);

      final sourceI420 = planes(byId('INPUT-FROM-RGBA-I420'));
      List<dynamic> hashes(List<Map<String, dynamic>> references) => references.map((plane) => plane['sha256']).toList();
      for (final layout in <String>['TIGHT', 'PADDED']) {
        expect(hashes(planes(byId('FORMAT-TO-I420-NV21-$layout'))), hashes(sourceI420));
        expect(hashes(planes(byId('FORMAT-TO-NV21-I420-$layout'))), hashes(sourceNv));
      }

      for (final format in <String>['BGRA8888', 'I420', 'NV21']) {
        final blank = byId('STATE-COPY-$format-BLANK')['expected']['rawPlaneReference'] as Map<String, dynamic>;
        expect(blank['isZeroFilled'], isTrue);
        for (final plane in (blank['planes'] as List<dynamic>).cast<Map<String, dynamic>>()) {
          expect(plane['sha256'], sha256Hex(Uint8List(plane['byteLength'] as int)));
        }
      }

      final crop = byId('GEOMETRY-CROP-BGRA8888-INNER')['expected'] as Map<String, dynamic>;
      expect(crop['dimensions'], <String, dynamic>{'width': 256, 'height': 320});
      expect(planes(byId('GEOMETRY-CROP-BGRA8888-INNER')).first['height'], 320);

      final sourceBgraHash = planes(byId('INPUT-FROM-RGBA-BGRA8888')).first['sha256'];
      for (final id in <String>[
        'GEOMETRY-ROTATE-BGRA8888-90',
        'GEOMETRY-FLIP-H-BGRA8888',
        'EFFECT-GRAYSCALE-BGRA8888',
        'EFFECT-BLACKWHITE-BGRA8888',
        'EFFECT-NEGATE-BGRA8888',
        'BLUR-GAUSSIANBLUR-BGRA8888-GAUSSIAN_DEFAULT',
        'BLUR-BOXBLUR-BGRA8888-BOX_DEFAULT',
        'BLUR-MEANBLUR-BGRA8888-MEAN_DEFAULT',
      ]) {
        expect(planes(byId(id)).first['sha256'], isNot(sourceBgraHash), reason: id);
      }

      for (final size in <String>['1X1', '3X5', '127X255']) {
        for (final format in <String>['BGRA8888', 'I420', 'NV21']) {
          final oddCase = byId('INPUT-ODD-CUSTOM-STRIDE-$format-$size');
          expect(oddCase['input']['layout'], 'customStride');
          expect(oddCase['input']['dimensions'], oddCase['expected']['dimensions']);
        }
      }
    });

    test('pins the F-011/F-012 planar tolerance sections and their case assignment (YUV-49)', () {
      final tolerances = manifest['tolerances'] as Map<String, dynamic>;
      final cases = (manifest['cases'] as List<dynamic>).cast<Map<String, dynamic>>();
      Map<String, dynamic> byId(String id) => cases.singleWhere((entry) => entry['id'] == id);

      expect(tolerances['blurPlanar'], isA<Map<String, dynamic>>());
      expect(tolerances['blurPlanar']['rationale'], contains('F-011'));
      expect(tolerances['effectPlanar'], isA<Map<String, dynamic>>());
      expect(tolerances['effectPlanar']['rationale'], contains('F-012'));

      const blurArtifactsByOperation = <String, List<String>>{
        'GAUSSIANBLUR': <String>['GAUSSIAN_DEFAULT', 'GAUSSIAN_R3_S2'],
        'BOXBLUR': <String>['BOX_DEFAULT', 'BOX_FULL', 'BOX_RECT'],
        'MEANBLUR': <String>['MEAN_DEFAULT', 'MEAN_FULL', 'MEAN_RECT'],
      };
      final expectedBlurPlanarIds = <String>{
        for (final entry in blurArtifactsByOperation.entries)
          for (final artifact in entry.value)
            for (final format in <String>['I420', 'NV21']) 'BLUR-${entry.key}-$format-$artifact',
      };

      const expectedEffectPlanarIds = <String>{'EFFECT-BLACKWHITE-I420', 'EFFECT-BLACKWHITE-NV21', 'EFFECT-NEGATE-I420', 'EFFECT-NEGATE-NV21'};

      expect(expectedBlurPlanarIds, hasLength(16));
      for (final id in expectedBlurPlanarIds) {
        expect(byId(id)['comparison'], 'blurPlanar', reason: id);
      }
      for (final id in expectedEffectPlanarIds) {
        expect(byId(id)['comparison'], 'effectPlanar', reason: id);
      }

      final actualBlurPlanarIds = cases.where((entry) => entry['comparison'] == 'blurPlanar').map((entry) => entry['id'] as String).toSet();
      final actualEffectPlanarIds = cases.where((entry) => entry['comparison'] == 'effectPlanar').map((entry) => entry['id'] as String).toSet();
      expect(actualBlurPlanarIds, expectedBlurPlanarIds);
      expect(actualEffectPlanarIds, expectedEffectPlanarIds);

      for (final id in <String>[
        'BLUR-GAUSSIANBLUR-BGRA8888-GAUSSIAN_DEFAULT',
        'BLUR-BOXBLUR-BGRA8888-BOX_DEFAULT',
        'BLUR-MEANBLUR-BGRA8888-MEAN_DEFAULT',
      ]) {
        expect(byId(id)['comparison'], 'blur', reason: id);
      }
      for (final id in <String>['EFFECT-BLACKWHITE-BGRA8888', 'EFFECT-NEGATE-BGRA8888']) {
        expect(byId(id)['comparison'], 'exact', reason: id);
      }
      for (final id in <String>['EFFECT-GRAYSCALE-I420', 'EFFECT-GRAYSCALE-NV21']) {
        expect(byId(id)['comparison'], 'yuvRoundTrip', reason: id);
      }
    });

    test('generator and helper remain independent from the package under test', () async {
      final generator = await File('tool/reference/generate_test_pattern_references.dart').readAsString();
      final helper = await File('test/helpers/reference/test_pattern_reference.dart').readAsString();
      final combined = '$generator\n$helper';

      expect(combined, isNot(contains(RegExp("^import\\s+['\"]package:yuv_ffi", multiLine: true))));
      expect(combined, isNot(contains(RegExp("^import\\s+['\"]dart:ffi", multiLine: true))));
      expect(combined, isNot(contains(RegExp("^import\\s+['\"]dart:js", multiLine: true))));
      expect(manifest['generator']['independence'], contains('pure Dart'));
    });
  });
}
