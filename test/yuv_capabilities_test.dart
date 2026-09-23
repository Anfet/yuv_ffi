import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_operation.dart';
import 'package:yuv_ffi/src/yuv_capabilities.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Verifies REL-09: an immutable [YuvCapabilities] snapshot that answers
/// whether dispatch exists for an operation and format pair -- never whether
/// arbitrary input to it is valid -- and that a negative capability rejects
/// before any backend dispatch (`doc/api-abi-0.4-design.md` section 7).
///
/// This suite exercises the pure Dart layer ([YuvCapabilitiesSnapshot],
/// [yuvAbiV1FormatPairSupported], [yuvAvailableOperations]) directly, so it
/// runs on every host regardless of whether a native library or a WASM
/// runtime is available. IO- and Web-specific "real symbols" wiring is
/// covered by `loader_io_test.dart`/`yuv_ffi_initializer_test.dart` (IO) and
/// `wasm_loader_lifecycle_test.dart`-style Web suites, which are skip-guarded
/// for their own runtime.
void main() {
  group('YuvCapabilitiesSnapshot.supports -- full operation x format table', () {
    // Section 11's "Format, layout, and geometry matrix": every operation
    // except convert and chromaSwap accepts every YuvPixelFormat as a
    // same-format source/destination pair; chromaSwap accepts only NV12;
    // convert accepts every format as both source and destination, but only
    // when a destinationFormat is actually supplied.
    const sameFormatOperations = <YuvOperation>[
      YuvOperation.blackWhite,
      YuvOperation.grayscale,
      YuvOperation.negate,
      YuvOperation.gaussianBlur,
      YuvOperation.meanBlur,
      YuvOperation.boxBlur,
      YuvOperation.crop,
      YuvOperation.flipHorizontal,
      YuvOperation.flipVertical,
      YuvOperation.rotate,
    ];

    test('every same-format operation supports every YuvPixelFormat as source, with no destinationFormat', () {
      final capabilities = YuvCapabilitiesSnapshot(YuvOperation.values);
      for (final operation in sameFormatOperations) {
        for (final format in YuvPixelFormat.values) {
          expect(capabilities.supports(operation, sourceFormat: format), isTrue, reason: '$operation must support $format per section 11');
        }
      }
    });

    test('a same-format operation queried with an explicit destinationFormat is a malformed query and returns false', () {
      final capabilities = YuvCapabilitiesSnapshot(YuvOperation.values);
      for (final operation in sameFormatOperations) {
        for (final format in YuvPixelFormat.values) {
          expect(
            capabilities.supports(operation, sourceFormat: format, destinationFormat: format),
            isFalse,
            reason: '$operation must not accept a destinationFormat (section 7: "must be omitted for all other operations")',
          );
        }
      }
    });

    test('convert supports every source/destination pair when destinationFormat is supplied', () {
      final capabilities = YuvCapabilitiesSnapshot(YuvOperation.values);
      for (final source in YuvPixelFormat.values) {
        for (final destination in YuvPixelFormat.values) {
          expect(
            capabilities.supports(YuvOperation.convert, sourceFormat: source, destinationFormat: destination),
            isTrue,
            reason: 'convert $source -> $destination must be supported per section 11',
          );
        }
      }
    });

    test('convert queried without destinationFormat is a malformed query and returns false', () {
      final capabilities = YuvCapabilitiesSnapshot(YuvOperation.values);
      for (final source in YuvPixelFormat.values) {
        expect(
          capabilities.supports(YuvOperation.convert, sourceFormat: source),
          isFalse,
          reason: 'convert requires destinationFormat (section 7: "destinationFormat is required for convert")',
        );
      }
    });

    test('chromaSwap supports only NV12 and rejects I420/BGRA8888', () {
      final capabilities = YuvCapabilitiesSnapshot(YuvOperation.values);
      expect(capabilities.supports(YuvOperation.chromaSwap, sourceFormat: YuvPixelFormat.nv12), isTrue);
      expect(capabilities.supports(YuvOperation.chromaSwap, sourceFormat: YuvPixelFormat.i420), isFalse);
      expect(capabilities.supports(YuvOperation.chromaSwap, sourceFormat: YuvPixelFormat.bgra8888), isFalse);
    });

    test('an operation absent from the snapshot is unsupported for every format, regardless of the matrix', () {
      final capabilities = YuvCapabilitiesSnapshot(const <YuvOperation>[]);
      for (final operation in YuvOperation.values) {
        for (final format in YuvPixelFormat.values) {
          expect(capabilities.supports(operation, sourceFormat: format, destinationFormat: format), isFalse);
          expect(capabilities.supports(operation, sourceFormat: format), isFalse);
        }
      }
    });

    test('the snapshot is unmodifiable: mutating the input iterable afterwards does not change it', () {
      final source = <YuvOperation>[YuvOperation.negate];
      final capabilities = YuvCapabilitiesSnapshot(source);
      source.add(YuvOperation.crop);

      expect(capabilities.supports(YuvOperation.crop, sourceFormat: YuvPixelFormat.i420), isFalse);
      expect(() => capabilities.availableOperations.add(YuvOperation.crop), throwsUnsupportedError);
    });
  });

  group('yuvAvailableOperations', () {
    test('names exactly the operations whose required symbol is available', () {
      final available = yuvAvailableOperations((symbol) => symbol == yuvAbiV1SymbolForOperation(YuvOperation.grayscale));
      expect(available, {YuvOperation.grayscale});
    });

    test('flipHorizontal and flipVertical share yuv_flip_v1, so one predicate answer covers both', () {
      final available = yuvAvailableOperations((symbol) => symbol == yuvAbiV1SymbolForOperation(YuvOperation.flipHorizontal));
      expect(available, {YuvOperation.flipHorizontal, YuvOperation.flipVertical});
    });

    test('an always-false predicate yields an empty set, not a hardcoded default', () {
      expect(yuvAvailableOperations((_) => false), isEmpty);
    });

    test('an always-true predicate yields every operation', () {
      expect(yuvAvailableOperations((_) => true).toSet(), YuvOperation.values.toSet());
    });
  });

  group('yuvRequireCapability', () {
    test('returns normally for a supported operation/format pair', () {
      final capabilities = YuvCapabilitiesSnapshot(YuvOperation.values);
      expect(() => yuvRequireCapability(capabilities, YuvOperation.grayscale, sourceFormat: YuvPixelFormat.nv12), returnsNormally);
    });

    test('throws UnsupportedError for an operation missing from the snapshot, before any caller state could change', () {
      final capabilities = YuvCapabilitiesSnapshot(const <YuvOperation>[]);
      int mutationsAttempted = 0;

      void dispatch() {
        yuvRequireCapability(capabilities, YuvOperation.grayscale, sourceFormat: YuvPixelFormat.nv12);
        // Unreachable when the capability is rejected: proves the throw
        // happens strictly before any backend dispatch or state mutation.
        mutationsAttempted++;
      }

      expect(dispatch, throwsUnsupportedError);
      expect(mutationsAttempted, 0, reason: 'a rejected capability must not reach backend dispatch');
    });

    test('throws UnsupportedError for chromaSwap on a non-NV12 source even when chromaSwap itself is available', () {
      final capabilities = YuvCapabilitiesSnapshot(YuvOperation.values);
      expect(() => yuvRequireCapability(capabilities, YuvOperation.chromaSwap, sourceFormat: YuvPixelFormat.i420), throwsUnsupportedError);
    });

    test('throws UnsupportedError for convert missing a destinationFormat', () {
      final capabilities = YuvCapabilitiesSnapshot(YuvOperation.values);
      expect(() => yuvRequireCapability(capabilities, YuvOperation.convert, sourceFormat: YuvPixelFormat.i420), throwsUnsupportedError);
    });
  });
}
