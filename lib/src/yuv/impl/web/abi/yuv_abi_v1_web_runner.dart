// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:typed_data';

import 'package:yuv_ffi/src/yuv/impl/web/abi/yuv_abi_v1_wasm_layout.dart';
import 'package:yuv_ffi/src/yuv/impl/web/abi/yuv_abi_v1_wasm_memory.dart';
import 'package:yuv_ffi/src/yuv/impl/web/yuv_abi_v1_dispatch_web.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_abi_v1_constants.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_abi_v1_frame.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_abi_v1_symbols.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_native_status.dart';

/// Typed Web runner for the ABI v1 `yuv_*_v1` symbols (YUV-51).
///
/// The Web counterpart of `YuvAbiV1Runner`: same public method set, same
/// arguments, same [YuvAbiV1FrameResult], same status-to-exception mapping
/// through [yuvThrowForStatus]. The difference is only where the descriptors
/// are staged -- WASM linear memory through a [WasmArena], rather than native
/// memory through `dart:ffi` -- so the two backends cannot diverge in what they
/// ask the ABI for, only in how they reach it.
///
/// Every method follows section 13's numbered steps exactly as the IO runner
/// documents them:
///
///  1. validate public arguments -- the caller has already done so, and the
///     plane count is re-checked here before any allocation;
///  2. allocate/copy read-only source staging;
///  3. allocate and seed destination staging -- ROI effects and blur seed the
///     destination with source samples so bytes outside the ROI survive;
///     every other operation replaces the whole destination, so its zeroed
///     buffer is the correct seed;
///  4. allocate versioned options;
///  5. invoke exactly one format-independent symbol through
///     [YuvAbiV1WebDispatch];
///  6. map a non-zero status to a Dart exception before reading any
///     destination byte back;
///  7. copy the destination into a Dart draft;
///  8. publishing is the caller's job;
///  9. release every WASM allocation in `finally`.
///
/// Staging into WASM is not free of a concern the IO side does not have: the
/// module is built with `ALLOW_MEMORY_GROWTH`, so an allocation can detach the
/// `ArrayBuffer` every previously taken `HEAPU8` view refers to. [WasmArena]
/// therefore re-reads the heap view on every access, and this runner never
/// holds one across an allocation.
abstract final class YuvAbiV1WebRunner {
  /// Runs `yuv_convert_v1`. [destinationLayout] carries the target format.
  static YuvAbiV1FrameResult convert({
    required Object module,
    required YuvAbiV1FrameInput source,
    required YuvAbiV1DestinationLayout destinationLayout,
  }) {
    return _run(
      module: module,
      operation: yuvSymbolConvertV1,
      source: source,
      destinationLayout: destinationLayout,
      allocateOptions: (arena) {
        final ptr = arena.allocateZeroed(YuvWasmConvertOptionsV1.sizeBytes);
        arena.writeUint32(ptr, YuvWasmConvertOptionsV1.offsetStructSize, YuvWasmConvertOptionsV1.sizeBytes);
        arena.writeUint32(ptr, YuvWasmConvertOptionsV1.offsetAbiVersion, yuvAbiVersion1);
        return ptr;
      },
    );
  }

  /// Runs `yuv_black_white_v1`. [region] selects the ROI, or `null` for the
  /// whole frame.
  static YuvAbiV1FrameResult blackWhite({required Object module, required YuvAbiV1FrameInput source, YuvAbiV1Region? region}) =>
      _runEffect(module: module, operation: yuvSymbolBlackWhiteV1, source: source, region: region);

  /// Runs `yuv_grayscale_v1`. [region] selects the ROI, or `null` for the whole
  /// frame.
  static YuvAbiV1FrameResult grayscale({required Object module, required YuvAbiV1FrameInput source, YuvAbiV1Region? region}) =>
      _runEffect(module: module, operation: yuvSymbolGrayscaleV1, source: source, region: region);

  /// Runs `yuv_negate_v1`. [region] selects the ROI, or `null` for the whole
  /// frame.
  static YuvAbiV1FrameResult negate({required Object module, required YuvAbiV1FrameInput source, YuvAbiV1Region? region}) =>
      _runEffect(module: module, operation: yuvSymbolNegateV1, source: source, region: region);

  /// Runs `yuv_chroma_swap_v1`.
  ///
  /// Takes no region: ABI v1 requires its region disabled (section 10), so
  /// there is no value that would produce anything but `INVALID_ARGUMENT`.
  static YuvAbiV1FrameResult chromaSwap({required Object module, required YuvAbiV1FrameInput source}) =>
      _runEffect(module: module, operation: yuvSymbolChromaSwapV1, source: source, region: null);

  /// Runs one of `yuv_gaussian_blur_v1`, `yuv_mean_blur_v1` or
  /// `yuv_box_blur_v1`, selected by [kind].
  ///
  /// [sigma] is required for [YuvAbiV1BlurKind.gaussian] and must be `0.0` for
  /// the two uniform-weight kinds (section 10).
  static YuvAbiV1FrameResult blur({
    required Object module,
    required YuvAbiV1BlurKind kind,
    required YuvAbiV1FrameInput source,
    required int radius,
    double sigma = 0.0,
    YuvAbiV1Region? region,
  }) {
    final String operation = switch (kind) {
      YuvAbiV1BlurKind.gaussian => yuvSymbolGaussianBlurV1,
      YuvAbiV1BlurKind.mean => yuvSymbolMeanBlurV1,
      YuvAbiV1BlurKind.box => yuvSymbolBoxBlurV1,
    };

    return _run(
      module: module,
      operation: operation,
      source: source,
      destinationLayout: _sameGeometryDestination(source),
      allocateOptions: (arena) {
        final ptr = arena.allocateZeroed(YuvWasmBlurOptionsV1.sizeBytes);
        arena.writeUint32(ptr, YuvWasmBlurOptionsV1.offsetStructSize, YuvWasmBlurOptionsV1.sizeBytes);
        arena.writeUint32(ptr, YuvWasmBlurOptionsV1.offsetAbiVersion, yuvAbiVersion1);
        arena.writeUint32(ptr, YuvWasmBlurOptionsV1.offsetRadius, radius);
        arena.writeUint32(ptr, YuvWasmBlurOptionsV1.offsetBorderMode, yuvBorderClamp);
        arena.writeFloat64(ptr, YuvWasmBlurOptionsV1.offsetSigma, sigma);
        _writeRegion(arena, ptr + YuvWasmBlurOptionsV1.offsetRegion, region);
        return ptr;
      },
      preserveOutsideRoi: region != null,
    );
  }

  /// Runs `yuv_crop_v1` into a [width] x [height] destination.
  static YuvAbiV1FrameResult crop({
    required Object module,
    required YuvAbiV1FrameInput source,
    required int left,
    required int top,
    required int width,
    required int height,
  }) {
    return _run(
      module: module,
      operation: yuvSymbolCropV1,
      source: source,
      destinationLayout: _destinationWithGeometry(source, width: width, height: height),
      allocateOptions: (arena) {
        final ptr = arena.allocateZeroed(YuvWasmCropOptionsV1.sizeBytes);
        arena.writeUint32(ptr, YuvWasmCropOptionsV1.offsetStructSize, YuvWasmCropOptionsV1.sizeBytes);
        arena.writeUint32(ptr, YuvWasmCropOptionsV1.offsetAbiVersion, yuvAbiVersion1);
        arena.writeInt32(ptr, YuvWasmCropOptionsV1.offsetLeft, left);
        arena.writeInt32(ptr, YuvWasmCropOptionsV1.offsetTop, top);
        arena.writeUint32(ptr, YuvWasmCropOptionsV1.offsetWidth, width);
        arena.writeUint32(ptr, YuvWasmCropOptionsV1.offsetHeight, height);
        return ptr;
      },
    );
  }

  /// Runs `yuv_flip_v1`. [direction] is [yuvFlipHorizontal] or
  /// [yuvFlipVertical].
  static YuvAbiV1FrameResult flip({required Object module, required YuvAbiV1FrameInput source, required int direction}) {
    return _run(
      module: module,
      operation: yuvSymbolFlipV1,
      source: source,
      destinationLayout: _sameGeometryDestination(source),
      allocateOptions: (arena) {
        final ptr = arena.allocateZeroed(YuvWasmFlipOptionsV1.sizeBytes);
        arena.writeUint32(ptr, YuvWasmFlipOptionsV1.offsetStructSize, YuvWasmFlipOptionsV1.sizeBytes);
        arena.writeUint32(ptr, YuvWasmFlipOptionsV1.offsetAbiVersion, yuvAbiVersion1);
        arena.writeUint32(ptr, YuvWasmFlipOptionsV1.offsetDirection, direction);
        return ptr;
      },
    );
  }

  /// Runs `yuv_rotate_v1` by [rotationDegrees], a multiple of 90.
  ///
  /// 90 and 270 transpose the destination geometry, exactly as the IO runner
  /// does.
  static YuvAbiV1FrameResult rotate({required Object module, required YuvAbiV1FrameInput source, required int rotationDegrees}) {
    final bool swapSize = rotationDegrees == 90 || rotationDegrees == 270;
    final int destinationWidth = swapSize ? source.height : source.width;
    final int destinationHeight = swapSize ? source.width : source.height;

    return _run(
      module: module,
      operation: yuvSymbolRotateV1,
      source: source,
      destinationLayout: _destinationWithGeometry(source, width: destinationWidth, height: destinationHeight),
      allocateOptions: (arena) {
        final ptr = arena.allocateZeroed(YuvWasmRotateOptionsV1.sizeBytes);
        arena.writeUint32(ptr, YuvWasmRotateOptionsV1.offsetStructSize, YuvWasmRotateOptionsV1.sizeBytes);
        arena.writeUint32(ptr, YuvWasmRotateOptionsV1.offsetAbiVersion, yuvAbiVersion1);
        arena.writeUint32(ptr, YuvWasmRotateOptionsV1.offsetRotationDegrees, rotationDegrees);
        return ptr;
      },
    );
  }

  static YuvAbiV1FrameResult _runEffect({
    required Object module,
    required String operation,
    required YuvAbiV1FrameInput source,
    required YuvAbiV1Region? region,
  }) {
    return _run(
      module: module,
      operation: operation,
      source: source,
      destinationLayout: _sameGeometryDestination(source),
      allocateOptions: (arena) {
        final ptr = arena.allocateZeroed(YuvWasmEffectOptionsV1.sizeBytes);
        arena.writeUint32(ptr, YuvWasmEffectOptionsV1.offsetStructSize, YuvWasmEffectOptionsV1.sizeBytes);
        arena.writeUint32(ptr, YuvWasmEffectOptionsV1.offsetAbiVersion, yuvAbiVersion1);
        _writeRegion(arena, ptr + YuvWasmEffectOptionsV1.offsetRegion, region);
        return ptr;
      },
      preserveOutsideRoi: region != null,
    );
  }

  /// The one staging/invoke/copy-back body every operation above shares.
  ///
  /// [allocateOptions] runs after both frames are staged, so a growth it
  /// triggers cannot detach a view either frame still needed; the frames only
  /// ever hold integer pointers, which survive a growth unchanged.
  static YuvAbiV1FrameResult _run({
    required Object module,
    required String operation,
    required YuvAbiV1FrameInput source,
    required YuvAbiV1DestinationLayout destinationLayout,
    required int Function(WasmArena arena) allocateOptions,
    bool preserveOutsideRoi = false,
  }) {
    final int expectedPlaneCount = yuvAbiV1PlaneCount(source.format);
    if (source.planes.length != expectedPlaneCount) {
      // Step 1 (defensive): reject a caller mistake before any allocation, the
      // same way the IO runner does. Native validation would report this as
      // INVALID_ARGUMENT, but only after a pointless source copy.
      throw ArgumentError.value(source.planes.length, 'source.planes.length', 'format ${source.format} requires $expectedPlaneCount plane(s)');
    }

    // A module missing a v1 symbol is reported by name here rather than as an
    // opaque failure inside `ccall`.
    YuvAbiV1WebDispatch.requireComplete(module);

    final arena = WasmArena(module);
    try {
      // Step 2: read-only source staging.
      final int sourceFrame = _stageConstFrame(arena, source);

      // Step 3: destination staging, seeded from the source only where the ROI
      // requires bytes outside it to survive; otherwise the zeroed buffer is
      // the correct seed.
      final _StagedDestination destination = _stageMutableFrame(arena, destinationLayout, seedFromSource: preserveOutsideRoi ? source : null);

      // Step 4: versioned options.
      final int options = allocateOptions(arena);

      // Step 5: exactly one format-independent symbol.
      final int status = YuvAbiV1WebDispatch.call(
        module,
        operation,
        argTypes: const <String>['number', 'number', 'number'],
        args: <Object?>[sourceFrame, destination.framePtr, options],
      );

      // Step 6: map a non-zero status before reading any destination byte.
      if (status != yuvStatusOk) {
        yuvThrowForStatus(status: status, operation: operation);
      }

      // Step 7: copy the destination into Dart-owned buffers, while the WASM
      // allocations are still alive.
      return YuvAbiV1FrameResult([
        for (int i = 0; i < destination.planePointers.length; i++) arena.read(destination.planePointers[i], destination.planeLengths[i]),
      ]);
    } finally {
      // Step 9: release everything this call allocated, whatever the outcome.
      arena.freeAll();
    }
  }

  /// Stages a `YuvConstFrameV1` plus one buffer per source plane.
  static int _stageConstFrame(WasmArena arena, YuvAbiV1FrameInput source) {
    // Plane buffers are allocated before the frame so the frame's own pointer
    // writes are the last thing to touch the heap. Each buffer's address is an
    // integer, unaffected by any later growth.
    final planePointers = <int>[for (final plane in source.planes) arena.allocateBytes(plane.bytes)];

    final int framePtr = arena.allocateZeroed(YuvWasmFrameV1.sizeBytes);
    arena.writeUint32(framePtr, YuvWasmFrameV1.offsetStructSize, YuvWasmFrameV1.sizeBytes);
    arena.writeUint32(framePtr, YuvWasmFrameV1.offsetAbiVersion, yuvAbiVersion1);
    arena.writeUint32(framePtr, YuvWasmFrameV1.offsetFormat, source.format);
    arena.writeUint32(framePtr, YuvWasmFrameV1.offsetPlaneCount, source.planes.length);
    arena.writeUint32(framePtr, YuvWasmFrameV1.offsetWidth, source.width);
    arena.writeUint32(framePtr, YuvWasmFrameV1.offsetHeight, source.height);
    arena.writeUint32(framePtr, YuvWasmFrameV1.offsetColorMatrix, yuvAbiV1ColorMatrixFor(source.format));
    arena.writeUint32(framePtr, YuvWasmFrameV1.offsetColorRange, yuvAbiV1ColorRangeFor(source.format));

    for (int i = 0; i < source.planes.length; i++) {
      final YuvAbiV1PlaneInput plane = source.planes[i];
      final int planeOffset = framePtr + YuvWasmFrameV1.offsetOfPlane(i);
      arena.writeUint64(planeOffset, YuvWasmPlaneV1.offsetLength, plane.bytes.length);
      arena.writeUint64(planeOffset, YuvWasmPlaneV1.offsetRowStride, plane.rowStride);
      arena.writeUint32(planeOffset, YuvWasmPlaneV1.offsetPixelStride, plane.pixelStride);
      arena.writeUint32(planeOffset, YuvWasmPlaneV1.offsetSampleBytes, yuvAbiV1SampleBytes(source.format, i));
      arena.writePointer(planeOffset, YuvWasmPlaneV1.offsetData, planePointers[i]);
    }
    // Slots past planeCount stay as `allocateZeroed` left them: zero-filled
    // descriptors with a null `data`, per section 9.

    return framePtr;
  }

  /// Stages a `YuvMutableFrameV1` plus one buffer per destination plane.
  static _StagedDestination _stageMutableFrame(WasmArena arena, YuvAbiV1DestinationLayout layout, {YuvAbiV1FrameInput? seedFromSource}) {
    final int planeCount = yuvAbiV1PlaneCount(layout.format);
    final planePointers = <int>[];
    final planeLengths = <int>[];

    for (int i = 0; i < planeCount; i++) {
      final int rowStride = layout.planeRowStrides[i];
      final int planeHeight = i == 0 ? layout.height : yuvAbiV1ChromaExtent(layout.height);
      final int length = rowStride * planeHeight;
      planeLengths.add(length);

      if (seedFromSource == null) {
        planePointers.add(arena.allocateZeroed(length));
        continue;
      }

      // An ROI operation only writes inside the region, so the destination
      // starts as a copy of the source's samples -- built in Dart and uploaded
      // as one buffer, rather than written sample-by-sample through the heap
      // view, which a growth could detach mid-loop.
      final int planeWidth = i == 0 ? layout.width : yuvAbiV1ChromaExtent(layout.width);
      planePointers.add(
        arena.allocateBytes(
          _seededPlane(
            length: length,
            destinationRowStride: rowStride,
            destinationPixelStride: layout.planePixelStrides[i],
            source: seedFromSource.planes[i].bytes,
            sourceRowStride: seedFromSource.planes[i].rowStride,
            sourcePixelStride: seedFromSource.planes[i].pixelStride,
            planeWidth: planeWidth,
            planeHeight: planeHeight,
            sampleBytes: yuvAbiV1SampleBytes(layout.format, i),
          ),
        ),
      );
    }

    final int framePtr = arena.allocateZeroed(YuvWasmFrameV1.sizeBytes);
    arena.writeUint32(framePtr, YuvWasmFrameV1.offsetStructSize, YuvWasmFrameV1.sizeBytes);
    arena.writeUint32(framePtr, YuvWasmFrameV1.offsetAbiVersion, yuvAbiVersion1);
    arena.writeUint32(framePtr, YuvWasmFrameV1.offsetFormat, layout.format);
    arena.writeUint32(framePtr, YuvWasmFrameV1.offsetPlaneCount, planeCount);
    arena.writeUint32(framePtr, YuvWasmFrameV1.offsetWidth, layout.width);
    arena.writeUint32(framePtr, YuvWasmFrameV1.offsetHeight, layout.height);
    arena.writeUint32(framePtr, YuvWasmFrameV1.offsetColorMatrix, yuvAbiV1ColorMatrixFor(layout.format));
    arena.writeUint32(framePtr, YuvWasmFrameV1.offsetColorRange, yuvAbiV1ColorRangeFor(layout.format));

    for (int i = 0; i < planeCount; i++) {
      final int planeOffset = framePtr + YuvWasmFrameV1.offsetOfPlane(i);
      arena.writeUint64(planeOffset, YuvWasmPlaneV1.offsetLength, planeLengths[i]);
      arena.writeUint64(planeOffset, YuvWasmPlaneV1.offsetRowStride, layout.planeRowStrides[i]);
      arena.writeUint32(planeOffset, YuvWasmPlaneV1.offsetPixelStride, layout.planePixelStrides[i]);
      arena.writeUint32(planeOffset, YuvWasmPlaneV1.offsetSampleBytes, yuvAbiV1SampleBytes(layout.format, i));
      arena.writePointer(planeOffset, YuvWasmPlaneV1.offsetData, planePointers[i]);
    }

    return _StagedDestination(framePtr: framePtr, planePointers: planePointers, planeLengths: planeLengths);
  }

  /// A destination plane pre-filled with [source]'s logical samples.
  ///
  /// Mirrors the IO runner's `_seedPlaneFromSource`: only the active
  /// `planeWidth x planeHeight` samples are copied, through both sides' own
  /// strides, and every padding byte stays zero.
  static Uint8List _seededPlane({
    required int length,
    required int destinationRowStride,
    required int destinationPixelStride,
    required Uint8List source,
    required int sourceRowStride,
    required int sourcePixelStride,
    required int planeWidth,
    required int planeHeight,
    required int sampleBytes,
  }) {
    final out = Uint8List(length);
    for (int row = 0; row < planeHeight; row++) {
      final int destinationRowStart = row * destinationRowStride;
      final int sourceRowStart = row * sourceRowStride;
      for (int col = 0; col < planeWidth; col++) {
        final int destinationOffset = destinationRowStart + col * destinationPixelStride;
        final int sourceOffset = sourceRowStart + col * sourcePixelStride;
        for (int b = 0; b < sampleBytes; b++) {
          out[destinationOffset + b] = source[sourceOffset + b];
        }
      }
    }
    return out;
  }

  /// Writes a `YuvRegionOptionsV1` at absolute address [address].
  ///
  /// A `null` region writes the disabled form: every coordinate zeroed, per
  /// section 10 ("when 0, all four coordinates and reserved0 must be zero").
  /// The surrounding struct was zero-filled at allocation, so this only has to
  /// write the header for that case -- but it writes the coordinates anyway,
  /// so the disabled form does not depend on the allocator's behaviour.
  static void _writeRegion(WasmArena arena, int address, YuvAbiV1Region? region) {
    arena.writeUint32(address, YuvWasmRegionOptionsV1.offsetStructSize, YuvWasmRegionOptionsV1.sizeBytes);
    arena.writeUint32(address, YuvWasmRegionOptionsV1.offsetAbiVersion, yuvAbiVersion1);
    arena.writeUint32(address, YuvWasmRegionOptionsV1.offsetEnabled, region == null ? 0 : 1);
    arena.writeInt32(address, YuvWasmRegionOptionsV1.offsetLeft, region?.left ?? 0);
    arena.writeInt32(address, YuvWasmRegionOptionsV1.offsetTop, region?.top ?? 0);
    arena.writeInt32(address, YuvWasmRegionOptionsV1.offsetRight, region?.right ?? 0);
    arena.writeInt32(address, YuvWasmRegionOptionsV1.offsetBottom, region?.bottom ?? 0);
    arena.writeUint32(address, YuvWasmRegionOptionsV1.offsetReserved0, 0);
  }

  static YuvAbiV1DestinationLayout _sameGeometryDestination(YuvAbiV1FrameInput source) =>
      _destinationWithGeometry(source, width: source.width, height: source.height);

  /// A tight destination layout in [source]'s format at [width] x [height].
  ///
  /// Identical to the IO runner's helper of the same name: the destination is
  /// always tight, and preserving a padded receiver's layout is the transport's
  /// job, not the runner's.
  static YuvAbiV1DestinationLayout _destinationWithGeometry(YuvAbiV1FrameInput source, {required int width, required int height}) {
    final int planeCount = yuvAbiV1PlaneCount(source.format);
    final rowStrides = <int>[];
    final pixelStrides = <int>[];
    for (int i = 0; i < planeCount; i++) {
      final int sampleBytes = yuvAbiV1SampleBytes(source.format, i);
      final int planeWidth = i == 0 ? width : yuvAbiV1ChromaExtent(width);
      pixelStrides.add(sampleBytes);
      rowStrides.add(planeWidth * sampleBytes);
    }
    return YuvAbiV1DestinationLayout(
      format: source.format,
      width: width,
      height: height,
      planeRowStrides: rowStrides,
      planePixelStrides: pixelStrides,
    );
  }
}

/// The staged destination frame and the plane buffers to read results back
/// from, kept together so `_run` does not have to re-derive the lengths it
/// already computed while staging.
class _StagedDestination {
  const _StagedDestination({required this.framePtr, required this.planePointers, required this.planeLengths});

  /// Address of the `YuvMutableFrameV1`.
  final int framePtr;

  /// Address of each destination plane buffer, in ABI plane order.
  final List<int> planePointers;

  /// Byte length of each destination plane buffer, in ABI plane order.
  final List<int> planeLengths;
}

/// Which blur `yuv_*_v1` symbol [YuvAbiV1WebRunner.blur] dispatches to.
///
/// Deliberately a separate enum from the IO runner's: that one lives beside
/// `dart:ffi` code a Web compilation cannot import. The two are kept in step by
/// the shared symbol manifest they both resolve names from.
enum YuvAbiV1BlurKind {
  /// `yuv_gaussian_blur_v1`.
  gaussian,

  /// `yuv_mean_blur_v1`.
  mean,

  /// `yuv_box_blur_v1`.
  box,
}
