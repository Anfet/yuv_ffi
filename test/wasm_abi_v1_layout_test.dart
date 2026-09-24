import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/src/yuv/impl/web/abi/yuv_abi_v1_wasm_layout.dart';

/// YUV-51: the wasm32 struct layout the Web runner writes into WASM linear
/// memory must be the layout ABI v1 declares.
///
/// The IO backend cannot get this wrong -- `dart:ffi` derives every offset from
/// the generated struct definitions -- but the Web backend writes raw bytes at
/// hand-written offsets, so nothing but a test stands between a wrong constant
/// and descriptors the WASM module misreads silently.
///
/// Two independent checks are made for every struct:
///
///  1. against the literal offset tables of `doc/api-abi-0.4-design.md`
///     sections 9 and 10, spelled out here rather than imported, so this file
///     is a second source rather than a restatement of the one being tested;
///  2. against `src/yuv/abi/h/yuv_abi_v1.h`'s own `YUV_ABI_STATIC_ASSERT`
///     lines, parsed from the header, so a header change that the Dart
///     constants were not updated for fails here rather than at runtime in a
///     browser.
///
/// The second check is what makes the first one more than a copy: the header
/// assertions are compiled on every native target, so agreeing with them means
/// agreeing with what the C compiler actually laid out.
const _headerPath = 'src/yuv/abi/h/yuv_abi_v1.h';

/// `offsetof(<struct>, <member>) == <value>` from the header's static
/// assertions, keyed `<struct>.<member>`.
Map<String, int> _headerOffsets() {
  final content = File(_headerPath).readAsStringSync();
  final regex = RegExp(r'YUV_ABI_STATIC_ASSERT\(offsetof\((\w+),\s*(\w+)\)\s*==\s*(\d+)');
  return {for (final m in regex.allMatches(content)) '${m.group(1)}.${m.group(2)}': int.parse(m.group(3)!)};
}

/// `sizeof(<struct>) == <value>` from the header's static assertions.
Map<String, int> _headerSizes() {
  final content = File(_headerPath).readAsStringSync();
  final regex = RegExp(r'YUV_ABI_STATIC_ASSERT\(sizeof\((\w+)\)\s*==\s*(\d+)');
  return {for (final m in regex.allMatches(content)) m.group(1)!: int.parse(m.group(2)!)};
}

void main() {
  late Map<String, int> headerOffsets;
  late Map<String, int> headerSizes;

  setUpAll(() {
    headerOffsets = _headerOffsets();
    headerSizes = _headerSizes();
    // Guards the parser itself: if the regexes stopped matching, every
    // comparison below would trivially pass against an empty map.
    expect(headerOffsets, isNotEmpty, reason: 'no offsetof assertions parsed from $_headerPath');
    expect(headerSizes, isNotEmpty, reason: 'no sizeof assertions parsed from $_headerPath');
  });

  group('plane descriptor', () {
    test('offsets and size match the section 9 table', () {
      expect(YuvWasmPlaneV1.offsetLength, 0);
      expect(YuvWasmPlaneV1.offsetRowStride, 8);
      expect(YuvWasmPlaneV1.offsetPixelStride, 16);
      expect(YuvWasmPlaneV1.offsetSampleBytes, 20);
      expect(YuvWasmPlaneV1.offsetData, 24);
      expect(YuvWasmPlaneV1.sizeBytes, 32);
    });

    test('agrees with the C header for both the const and mutable form', () {
      for (final struct in ['YuvConstPlaneV1', 'YuvMutablePlaneV1']) {
        final prefix = struct == 'YuvConstPlaneV1' ? 'YuvConstPlaneV1' : 'YuvMutablePlaneV1';
        expect(headerOffsets['$prefix.length'], YuvWasmPlaneV1.offsetLength);
        expect(headerOffsets['$prefix.rowStride'], YuvWasmPlaneV1.offsetRowStride);
        expect(headerOffsets['$prefix.pixelStride'], YuvWasmPlaneV1.offsetPixelStride);
        expect(headerOffsets['$prefix.sampleBytes'], YuvWasmPlaneV1.offsetSampleBytes);
        expect(headerOffsets['$prefix.data'], YuvWasmPlaneV1.offsetData);
        expect(headerSizes[struct], YuvWasmPlaneV1.sizeBytes);
      }
    });

    test('the 4-byte wasm32 pointer does not shrink the struct', () {
      // `data` is the last member and the struct is 8-byte aligned because of
      // its uint64 members, so a 4-byte pointer is padded back out to the same
      // 32 bytes a native64 build produces. This is the single member whose
      // width legitimately differs between the two targets, and the reason the
      // frame descriptor below is 160 bytes on both.
      const int pointerEnd = YuvWasmPlaneV1.offsetData + 4;
      expect(pointerEnd, 28);
      expect(YuvWasmPlaneV1.sizeBytes, 32, reason: 'wasm32 plane must stay 32 bytes despite its 4-byte data pointer');
    });
  });

  group('frame descriptor', () {
    test('offsets and size match the section 9 table', () {
      expect(YuvWasmFrameV1.offsetStructSize, 0);
      expect(YuvWasmFrameV1.offsetAbiVersion, 4);
      expect(YuvWasmFrameV1.offsetFormat, 8);
      expect(YuvWasmFrameV1.offsetPlaneCount, 12);
      expect(YuvWasmFrameV1.offsetWidth, 16);
      expect(YuvWasmFrameV1.offsetHeight, 20);
      expect(YuvWasmFrameV1.offsetColorMatrix, 24);
      expect(YuvWasmFrameV1.offsetColorRange, 28);
      expect(YuvWasmFrameV1.offsetPlanes, 32);
      expect(YuvWasmFrameV1.offsetReserved, 128);
      expect(YuvWasmFrameV1.sizeBytes, 160);
    });

    test('agrees with the C header for both the const and mutable form', () {
      for (final struct in ['YuvConstFrameV1', 'YuvMutableFrameV1']) {
        expect(headerOffsets['$struct.structSize'], YuvWasmFrameV1.offsetStructSize);
        expect(headerOffsets['$struct.abiVersion'], YuvWasmFrameV1.offsetAbiVersion);
        expect(headerOffsets['$struct.format'], YuvWasmFrameV1.offsetFormat);
        expect(headerOffsets['$struct.planeCount'], YuvWasmFrameV1.offsetPlaneCount);
        expect(headerOffsets['$struct.width'], YuvWasmFrameV1.offsetWidth);
        expect(headerOffsets['$struct.height'], YuvWasmFrameV1.offsetHeight);
        expect(headerOffsets['$struct.colorMatrix'], YuvWasmFrameV1.offsetColorMatrix);
        expect(headerOffsets['$struct.colorRange'], YuvWasmFrameV1.offsetColorRange);
        expect(headerOffsets['$struct.planes'], YuvWasmFrameV1.offsetPlanes);
        expect(headerOffsets['$struct.reserved'], YuvWasmFrameV1.offsetReserved);
        expect(headerSizes[struct], YuvWasmFrameV1.sizeBytes);
      }
    });

    test('plane slots are contiguous at 32-byte spacing, as the header asserts', () {
      // The header asserts planes[1]/planes[2] through
      // `offsetof(planes) + n * sizeof(plane)` rather than offsetof on the
      // element, so this mirrors that same arithmetic.
      expect(YuvWasmFrameV1.offsetOfPlane(0), 32);
      expect(YuvWasmFrameV1.offsetOfPlane(1), 64);
      expect(YuvWasmFrameV1.offsetOfPlane(2), 96);
      expect(YuvWasmFrameV1.planeSlots, 3);
      // The three slots must end exactly where the reserved tail begins, or a
      // plane write would run into it.
      expect(YuvWasmFrameV1.offsetOfPlane(YuvWasmFrameV1.planeSlots - 1) + YuvWasmPlaneV1.sizeBytes, YuvWasmFrameV1.offsetReserved);
    });

    test('the reserved tail is four uint64 and closes the struct', () {
      expect(YuvWasmFrameV1.offsetReserved + 4 * 8, YuvWasmFrameV1.sizeBytes);
    });
  });

  group('options structs', () {
    test('region offsets and size match the section 10 table and the header', () {
      expect(YuvWasmRegionOptionsV1.offsetStructSize, 0);
      expect(YuvWasmRegionOptionsV1.offsetAbiVersion, 4);
      expect(YuvWasmRegionOptionsV1.offsetLeft, 8);
      expect(YuvWasmRegionOptionsV1.offsetTop, 12);
      expect(YuvWasmRegionOptionsV1.offsetRight, 16);
      expect(YuvWasmRegionOptionsV1.offsetBottom, 20);
      expect(YuvWasmRegionOptionsV1.offsetEnabled, 24);
      expect(YuvWasmRegionOptionsV1.offsetReserved0, 28);
      expect(YuvWasmRegionOptionsV1.sizeBytes, 32);

      expect(headerOffsets['YuvRegionOptionsV1.left'], YuvWasmRegionOptionsV1.offsetLeft);
      expect(headerOffsets['YuvRegionOptionsV1.top'], YuvWasmRegionOptionsV1.offsetTop);
      expect(headerOffsets['YuvRegionOptionsV1.right'], YuvWasmRegionOptionsV1.offsetRight);
      expect(headerOffsets['YuvRegionOptionsV1.bottom'], YuvWasmRegionOptionsV1.offsetBottom);
      expect(headerOffsets['YuvRegionOptionsV1.enabled'], YuvWasmRegionOptionsV1.offsetEnabled);
      expect(headerOffsets['YuvRegionOptionsV1.reserved0'], YuvWasmRegionOptionsV1.offsetReserved0);
      expect(headerSizes['YuvRegionOptionsV1'], YuvWasmRegionOptionsV1.sizeBytes);
    });

    test('blur offsets and size match the section 10 table and the header', () {
      expect(YuvWasmBlurOptionsV1.offsetRadius, 8);
      expect(YuvWasmBlurOptionsV1.offsetBorderMode, 12);
      expect(YuvWasmBlurOptionsV1.offsetSigma, 16);
      expect(YuvWasmBlurOptionsV1.offsetRegion, 24);
      expect(YuvWasmBlurOptionsV1.offsetReserved, 56);
      expect(YuvWasmBlurOptionsV1.sizeBytes, 72);

      expect(headerOffsets['YuvBlurOptionsV1.radius'], YuvWasmBlurOptionsV1.offsetRadius);
      expect(headerOffsets['YuvBlurOptionsV1.borderMode'], YuvWasmBlurOptionsV1.offsetBorderMode);
      expect(headerOffsets['YuvBlurOptionsV1.sigma'], YuvWasmBlurOptionsV1.offsetSigma);
      expect(headerOffsets['YuvBlurOptionsV1.region'], YuvWasmBlurOptionsV1.offsetRegion);
      expect(headerOffsets['YuvBlurOptionsV1.reserved'], YuvWasmBlurOptionsV1.offsetReserved);
      expect(headerSizes['YuvBlurOptionsV1'], YuvWasmBlurOptionsV1.sizeBytes);
    });

    test('the embedded region occupies exactly the gap the enclosing structs leave for it', () {
      // The one layout mistake size-and-offset checks alone would miss: a
      // region written at the right offset but with the wrong extent would
      // overwrite the reserved tail that follows it.
      expect(YuvWasmBlurOptionsV1.offsetRegion + YuvWasmRegionOptionsV1.sizeBytes, YuvWasmBlurOptionsV1.offsetReserved);
      expect(YuvWasmEffectOptionsV1.offsetRegion + YuvWasmRegionOptionsV1.sizeBytes, YuvWasmEffectOptionsV1.offsetReserved);
    });

    test('effect offsets and size match the section 10 table and the header', () {
      expect(YuvWasmEffectOptionsV1.offsetRegion, 8);
      expect(YuvWasmEffectOptionsV1.offsetReserved, 40);
      expect(YuvWasmEffectOptionsV1.sizeBytes, 56);

      expect(headerOffsets['YuvEffectOptionsV1.region'], YuvWasmEffectOptionsV1.offsetRegion);
      expect(headerOffsets['YuvEffectOptionsV1.reserved'], YuvWasmEffectOptionsV1.offsetReserved);
      expect(headerSizes['YuvEffectOptionsV1'], YuvWasmEffectOptionsV1.sizeBytes);
    });

    test('convert offsets and size match the section 10 table and the header', () {
      expect(YuvWasmConvertOptionsV1.offsetReserved, 8);
      expect(YuvWasmConvertOptionsV1.sizeBytes, 32);

      expect(headerOffsets['YuvConvertOptionsV1.reserved'], YuvWasmConvertOptionsV1.offsetReserved);
      expect(headerSizes['YuvConvertOptionsV1'], YuvWasmConvertOptionsV1.sizeBytes);
    });

    test('crop offsets and size match the section 10 table and the header', () {
      expect(YuvWasmCropOptionsV1.offsetLeft, 8);
      expect(YuvWasmCropOptionsV1.offsetTop, 12);
      expect(YuvWasmCropOptionsV1.offsetWidth, 16);
      expect(YuvWasmCropOptionsV1.offsetHeight, 20);
      expect(YuvWasmCropOptionsV1.offsetReserved, 24);
      expect(YuvWasmCropOptionsV1.sizeBytes, 32);

      expect(headerOffsets['YuvCropOptionsV1.left'], YuvWasmCropOptionsV1.offsetLeft);
      expect(headerOffsets['YuvCropOptionsV1.top'], YuvWasmCropOptionsV1.offsetTop);
      expect(headerOffsets['YuvCropOptionsV1.width'], YuvWasmCropOptionsV1.offsetWidth);
      expect(headerOffsets['YuvCropOptionsV1.height'], YuvWasmCropOptionsV1.offsetHeight);
      expect(headerOffsets['YuvCropOptionsV1.reserved'], YuvWasmCropOptionsV1.offsetReserved);
      expect(headerSizes['YuvCropOptionsV1'], YuvWasmCropOptionsV1.sizeBytes);
    });

    test('flip offsets and size match the section 10 table and the header', () {
      expect(YuvWasmFlipOptionsV1.offsetDirection, 8);
      expect(YuvWasmFlipOptionsV1.offsetReserved0, 12);
      expect(YuvWasmFlipOptionsV1.offsetReserved, 16);
      expect(YuvWasmFlipOptionsV1.sizeBytes, 32);

      expect(headerOffsets['YuvFlipOptionsV1.direction'], YuvWasmFlipOptionsV1.offsetDirection);
      expect(headerOffsets['YuvFlipOptionsV1.reserved0'], YuvWasmFlipOptionsV1.offsetReserved0);
      expect(headerOffsets['YuvFlipOptionsV1.reserved'], YuvWasmFlipOptionsV1.offsetReserved);
      expect(headerSizes['YuvFlipOptionsV1'], YuvWasmFlipOptionsV1.sizeBytes);
    });

    test('rotate offsets and size match the section 10 table and the header', () {
      expect(YuvWasmRotateOptionsV1.offsetRotationDegrees, 8);
      expect(YuvWasmRotateOptionsV1.offsetReserved0, 12);
      expect(YuvWasmRotateOptionsV1.offsetReserved, 16);
      expect(YuvWasmRotateOptionsV1.sizeBytes, 32);

      expect(headerOffsets['YuvRotateOptionsV1.rotationDegrees'], YuvWasmRotateOptionsV1.offsetRotationDegrees);
      expect(headerOffsets['YuvRotateOptionsV1.reserved0'], YuvWasmRotateOptionsV1.offsetReserved0);
      expect(headerOffsets['YuvRotateOptionsV1.reserved'], YuvWasmRotateOptionsV1.offsetReserved);
      expect(headerSizes['YuvRotateOptionsV1'], YuvWasmRotateOptionsV1.sizeBytes);
    });

    test('every ABI v1 struct the header sizes is covered by a Dart constant', () {
      // Negative control for the whole group: a struct added to the header
      // without a Dart layout would otherwise be silently unstaged rather than
      // caught. `YuvConstFrameV1`/`YuvMutableFrameV1` and the two plane forms
      // share one Dart constant each, which is why the map is keyed by C name.
      const covered = <String, int>{
        'YuvConstPlaneV1': YuvWasmPlaneV1.sizeBytes,
        'YuvMutablePlaneV1': YuvWasmPlaneV1.sizeBytes,
        'YuvConstFrameV1': YuvWasmFrameV1.sizeBytes,
        'YuvMutableFrameV1': YuvWasmFrameV1.sizeBytes,
        'YuvRegionOptionsV1': YuvWasmRegionOptionsV1.sizeBytes,
        'YuvBlurOptionsV1': YuvWasmBlurOptionsV1.sizeBytes,
        'YuvEffectOptionsV1': YuvWasmEffectOptionsV1.sizeBytes,
        'YuvConvertOptionsV1': YuvWasmConvertOptionsV1.sizeBytes,
        'YuvCropOptionsV1': YuvWasmCropOptionsV1.sizeBytes,
        'YuvRotateOptionsV1': YuvWasmRotateOptionsV1.sizeBytes,
        'YuvFlipOptionsV1': YuvWasmFlipOptionsV1.sizeBytes,
      };

      // `sizeof(uint64_t)` is asserted in the header as an alignment probe, not
      // as an ABI struct, so it is not expected to have a Dart layout.
      final structsInHeader = headerSizes.keys.where((name) => name.startsWith('Yuv')).toSet();
      expect(structsInHeader.difference(covered.keys.toSet()), isEmpty, reason: 'a header struct has no Dart wasm32 layout constant');

      for (final entry in covered.entries) {
        expect(headerSizes[entry.key], entry.value, reason: '${entry.key} size disagrees with the header');
      }
    });
  });
}
