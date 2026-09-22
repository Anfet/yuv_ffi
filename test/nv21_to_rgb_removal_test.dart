@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/src/loader/impl/loader_io.dart' as loader_io;
import 'package:yuv_ffi/yuv_ffi.dart';

/// YUV-29 characterization: the orphan `nv21_to_rgb` declaration is gone, and
/// the NV21 operations that do exist are untouched.
///
/// `nv21_to_rgb` was declared in `src/yuv/nv21/h/nv21_to_rgb.h` and included
/// from `src/yuv/nv21.h` with no `.c` implementation anywhere. FFI symbol
/// lookup is lazy, so a declaration with no definition stays invisible until
/// something calls it — which is what let the mismatch survive.
///
/// Absence is asserted against the *loaded binary* via `providesSymbol`, not by
/// reading `ffigen.yaml` or grepping the generated bindings. Config text only
/// says what was requested; the library says what was actually built. An
/// assertion phrased against the config would keep passing if someone added a
/// real `nv21_to_rgb` implementation, which is precisely the regression worth
/// catching. BUT `providesSymbol` alone does not discriminate the fix from the
/// defect here: `nv21_to_rgb` was already unresolvable before the header was
/// deleted, because a declaration with no implementation exports no symbol
/// either way. So this suite also inspects the SOURCE/HEADER surface on disk
/// directly (see below), which is the only thing that actually changed.
void main() {
  test('nv21_to_rgb is absent from the native library while the real NV21 symbols resolve', () async {
    // Loud on failure, never skipped: a run where this silently skipped would
    // be indistinguishable from a run that proved something.
    await YuvFfi.ensureInitialized();

    final library = loader_io.library;

    expect(
      library.providesSymbol('nv21_to_bgra8888'),
      isTrue,
      reason:
          'the supported NV21 conversion must still be exported; if this is false the '
          'probe is wrong and the absence assertion below would pass vacuously',
    );

    expect(library.providesSymbol('nv21_to_rgb'), isFalse, reason: 'nv21_to_rgb has no implementation and must not be exported');
  });

  test('a real NV21 to BGRA8888 conversion still runs after the header removal', () async {
    await YuvFfi.ensureInitialized();

    const width = 8;
    const height = 8;

    // Deterministic and non-uniform, so a backend returning zeroes or echoing
    // its input could not pass by coincidence.
    final rgba = Uint8List(width * height * 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = (y * width + x) * 4;
        rgba[i] = (x * 30 + 10) & 0xFF;
        rgba[i + 1] = (y * 30 + 20) & 0xFF;
        rgba[i + 2] = (x * 10 + y * 10 + 30) & 0xFF;
        rgba[i + 3] = 255;
      }
    }

    final image = YuvImage.nv21(width, height)..fromRgba8888(rgba);
    final bgra = image.toBgra8888();

    expect(bgra.length, width * height * 4, reason: 'toBgra8888 must return a tightly packed buffer');
    expect(bgra.any((byte) => byte != 0), isTrue, reason: 'an all-zero result means the native NV21 symbols did not run');
  });

  test('the NV21 interleaved chroma contract is unchanged', () {
    final image = YuvImage.nv21(8, 8);

    expect(image.format, YuvFileFormat.nv21);
    expect(image.uPlane.pixelStride, 2, reason: 'NV21 keeps its interleaved chroma plane; the header removal must not alter geometry');
  });

  group('source/header surface (the actual discriminating probe)', () {
    // This group reads the C source tree from disk, not the loaded binary.
    // `providesSymbol` cannot discriminate the fix from the defect for
    // `nv21_to_rgb`: a header declaration with no `.c` implementation exports
    // no symbol either way, so `providesSymbol('nv21_to_rgb')` was already
    // `false` before `src/yuv/nv21/h/nv21_to_rgb.h` existed as a problem, is
    // `false` while the header (and its include line) are present and broken,
    // and stays `false` after the fix removes them. Reading the header/source
    // surface directly is the only formulation that goes red when someone
    // restores `nv21_to_rgb.h` and its include line, because that restoration
    // is the only thing that actually changed on disk.
    //
    // Each format directory under src/yuv/ (bgra8888, nv21, yuv420) declares
    // its operations as one header + one matching .c file per operation, with
    // an exact 1:1 correspondence between src/yuv/<format>/h/*.h and
    // src/yuv/<format>/*.c. `nv21_to_rgb.h` violated exactly this
    // correspondence: a header with no matching .c. `src/yuv/utils/h/`
    // deliberately does NOT follow this pattern (it holds header-only
    // utilities: log.h and yuv_utils.h have no matching .c, only gauss.c/
    // gauss.h form a pair) so utils is excluded rather than folded into a
    // single blanket rule across all of src/yuv/**/h/, which would produce
    // false failures on log.h and yuv_utils.h that no one asked to fix.
    const formatDirectories = ['bgra8888', 'nv21', 'yuv420'];

    for (final format in formatDirectories) {
      test('every header in src/yuv/$format/h/ has a matching .c implementation', () {
        final headerDir = Directory('src/yuv/$format/h');
        final sourceDir = Directory('src/yuv/$format');

        expect(headerDir.existsSync(), isTrue, reason: 'src/yuv/$format/h must exist');

        final headerNames = headerDir
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.h'))
            .map((file) => file.uri.pathSegments.last.replaceAll(RegExp(r'\.h$'), ''))
            .toSet();
        final sourceNames = sourceDir
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.c'))
            .map((file) => file.uri.pathSegments.last.replaceAll(RegExp(r'\.c$'), ''))
            .toSet();

        expect(
          headerNames,
          equals(sourceNames),
          reason:
              'src/yuv/$format/h declarations and src/yuv/$format implementations must correspond '
              '1:1; a header with no matching .c (such as the removed nv21_to_rgb.h) fails this check',
        );
      });
    }

    test('nv21_to_rgb.h is absent from src/yuv/nv21/h and not included from src/yuv/nv21.h', () {
      // Targeted, name-specific checks in addition to the general 1:1 rule
      // above: these are what actually goes red if someone restores exactly
      // the file and include line the reviewer described, even before
      // re-running the general correspondence check.
      final headerFile = File('src/yuv/nv21/h/nv21_to_rgb.h');
      final aggregatorSource = File('src/yuv/nv21.h').readAsStringSync();

      expect(
        headerFile.existsSync(),
        isFalse,
        reason:
            'src/yuv/nv21/h/nv21_to_rgb.h must stay deleted; its restoration is the exact regression '
            'this card guards against',
      );
      expect(aggregatorSource, isNot(contains('nv21_to_rgb.h')), reason: 'src/yuv/nv21.h must not include nv21_to_rgb.h again');
      expect(
        aggregatorSource,
        isNot(contains(RegExp(r'\bnv21_to_rgb\b'))),
        reason: 'src/yuv/nv21.h must not reference nv21_to_rgb by name in any form',
      );
    });
  });
}
