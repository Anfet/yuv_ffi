import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:yuv_ffi/src/functions/bindings/yuv_ffi_bingings.dart';
import 'package:yuv_ffi/src/loader/loader.dart';
import 'package:yuv_ffi/src/yuv/impl/io/defs/native_allocator.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_abi_v1_constants.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_abi_v1_frame.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_abi_v1_symbols.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_native_status.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_operation.dart';

/// Typed IO runner for the ABI v1 `yuv_*_v1` symbols
/// (`doc/api-abi-0.4-design.md` sections 9, 11, 13).
///
/// This is the internal transport path YUV-36d owns: it stages source and
/// destination native descriptors, invokes exactly one ABI v1 symbol, maps
/// its `YuvStatus` to the Dart result, and releases every allocation it made.
/// It is not the public Dart API -- that redesign, with the public
/// `apply*`/`to*` surface calling through this runner, is YUV-28.
///
/// Every method follows section 13's numbered steps literally:
///
///  1. validate public arguments and capability -- done by the caller before
///     reaching this runner, and defensively re-checked here (plane counts,
///     geometry) before any allocation;
///  2. allocate/copy read-only source staging;
///  3. allocate and seed destination staging where preservation is required
///     -- ROI effects/blur seed the destination with source samples so bytes
///     outside the ROI survive; every other operation replaces the whole
///     destination, so "seeding" there means zero-filling through `calloc`;
///  4. allocate versioned options;
///  5. invoke exactly one format-independent symbol;
///  6. map non-zero status to a Dart exception without publishing the
///     destination -- the exception is thrown before any destination bytes
///     are read back;
///  7. copy destination into a Dart draft;
///  8. atomic replace / new object is the caller's job (YUV-28's `apply*` vs
///     `to*` split); this runner always returns a fresh [YuvAbiV1FrameResult]
///     and lets the caller decide what to do with it;
///  9. dispose options, destination, and source in `finally`.
class YuvAbiV1Runner {
  const YuvAbiV1Runner._();

  /// Test-only override for the native `invoke` step (section 13, step 5),
  /// used by YUV-36k's success-path regression to exercise the real
  /// destination-seeding/copy-back path through the public runner methods
  /// without `yuv_ffi.dll`: it is called with the exact same arguments
  /// `_run` would otherwise pass to the real `ffiBingings.yuv_*_v1` symbol
  /// (source frame, destination frame, format-specific options -- all
  /// already staged and, for ROI effects/blur, already seeded), and its
  /// return value flows through the same status-mapping/copy-back/cleanup
  /// steps a real native return value would. `null` (the default) means "use
  /// the real native call" -- production code never sets this.
  ///
  /// A test that sets this must reset it to `null` in the same test (or a
  /// `tearDown`), since it is process-global static state; leaving it set
  /// would silently redirect every later test's native calls.
  @visibleForTesting
  static int Function(ffi.Pointer<YuvConstFrameV1>, ffi.Pointer<YuvMutableFrameV1>, ffi.Pointer<ffi.NativeType>)? debugInvokeOverride;

  /// Runs `yuv_convert_v1`. [destinationLayout] carries the target format;
  /// [options] is currently unused (`YuvConvertOptionsV1` has no operation
  /// fields in ABI v1, only the shared struct header and reserved padding).
  static YuvAbiV1FrameResult convert({required YuvAbiV1FrameInput source, required YuvAbiV1DestinationLayout destinationLayout}) {
    return _run(
      operation: YuvOperation.convert,
      nativeSymbol: yuvSymbolConvertV1,
      source: source,
      destinationLayout: destinationLayout,
      allocateOptions: (allocator) => _allocateConvertOptions(allocator).cast(),
      freeOptions: (allocator, options) => allocator.free(options.cast()),
      invoke: (src, dst, options) => ffiBingings.yuv_convert_v1(src, dst, options.cast()),
    );
  }

  /// Runs `yuv_black_white_v1`. [region] selects the ROI, or `null` for the
  /// whole frame.
  static YuvAbiV1FrameResult blackWhite({required YuvAbiV1FrameInput source, YuvAbiV1Region? region}) {
    return _runEffect(
      YuvOperation.blackWhite,
      yuvSymbolBlackWhiteV1,
      source,
      region,
      (src, dst, options) => ffiBingings.yuv_black_white_v1(src, dst, options),
    );
  }

  /// Runs `yuv_grayscale_v1`. [region] selects the ROI, or `null` for the
  /// whole frame.
  static YuvAbiV1FrameResult grayscale({required YuvAbiV1FrameInput source, YuvAbiV1Region? region}) {
    return _runEffect(
      YuvOperation.grayscale,
      yuvSymbolGrayscaleV1,
      source,
      region,
      (src, dst, options) => ffiBingings.yuv_grayscale_v1(src, dst, options),
    );
  }

  /// Runs `yuv_negate_v1`. [region] selects the ROI, or `null` for the whole
  /// frame.
  static YuvAbiV1FrameResult negate({required YuvAbiV1FrameInput source, YuvAbiV1Region? region}) {
    return _runEffect(YuvOperation.negate, yuvSymbolNegateV1, source, region, (src, dst, options) => ffiBingings.yuv_negate_v1(src, dst, options));
  }

  /// Runs `yuv_chroma_swap_v1`. ABI v1 requires its region disabled (section
  /// 10: "regional chroma swap is not a public 0.3.0 operation"), so this
  /// method takes no [YuvAbiV1Region] parameter at all -- there is no value
  /// that would produce anything other than `INVALID_ARGUMENT`.
  static YuvAbiV1FrameResult chromaSwap({required YuvAbiV1FrameInput source}) {
    return _runEffect(
      YuvOperation.chromaSwap,
      yuvSymbolChromaSwapV1,
      source,
      null,
      (src, dst, options) => ffiBingings.yuv_chroma_swap_v1(src, dst, options),
    );
  }

  /// Runs one of `yuv_gaussian_blur_v1`, `yuv_mean_blur_v1`, or
  /// `yuv_box_blur_v1`, selected by [kind]. [radius] `0` is a defined no-op at
  /// the ABI level -- validated and dispatched like any other accepted
  /// radius, per section 10 ("radius == 0 is a no-op") -- but produces a
  /// destination identical to the source rather than skipping the native
  /// call. [sigma] is required for [YuvAbiV1BlurKind.gaussian] and must be
  /// `0.0` for the two uniform-weight kinds (section 10).
  static YuvAbiV1FrameResult blur({
    required YuvAbiV1BlurKind kind,
    required YuvAbiV1FrameInput source,
    required int radius,
    double sigma = 0.0,
    YuvAbiV1Region? region,
  }) {
    final String nativeSymbol = switch (kind) {
      YuvAbiV1BlurKind.gaussian => yuvSymbolGaussianBlurV1,
      YuvAbiV1BlurKind.mean => yuvSymbolMeanBlurV1,
      YuvAbiV1BlurKind.box => yuvSymbolBoxBlurV1,
    };
    final YuvOperation operation = switch (kind) {
      YuvAbiV1BlurKind.gaussian => YuvOperation.gaussianBlur,
      YuvAbiV1BlurKind.mean => YuvOperation.meanBlur,
      YuvAbiV1BlurKind.box => YuvOperation.boxBlur,
    };

    final YuvAbiV1DestinationLayout destinationLayout = _sameGeometryDestination(source);
    return _run(
      operation: operation,
      nativeSymbol: nativeSymbol,
      source: source,
      destinationLayout: destinationLayout,
      allocateOptions: (allocator) =>
          _allocateBlurOptions(allocator, radius: radius, sigma: sigma, region: region, width: source.width, height: source.height).cast(),
      freeOptions: (allocator, options) => allocator.free(options.cast()),
      // Dispatched by kind inside the closure (rather than a tear-off picked
      // eagerly outside it) so `ffiBingings` -- and the `yuv_ffi.dll` load it
      // triggers -- is only touched when this closure actually runs, not
      // whenever `blur` is called. That matters when debugInvokeOverride
      // (YUV-36k) is set: `_run` never calls this closure at all in that
      // case, so the real kernel symbol (and the library behind it) is never
      // looked up.
      invoke: (src, dst, options) => switch (kind) {
        YuvAbiV1BlurKind.gaussian => ffiBingings.yuv_gaussian_blur_v1(src, dst, options.cast()),
        YuvAbiV1BlurKind.mean => ffiBingings.yuv_mean_blur_v1(src, dst, options.cast()),
        YuvAbiV1BlurKind.box => ffiBingings.yuv_box_blur_v1(src, dst, options.cast()),
      },
      preserveOutsideRoi: region != null,
    );
  }

  /// Runs `yuv_crop_v1`. The destination is exactly `width x height`
  /// starting at `(left, top)` in source visible-pixel coordinates (section
  /// 11): unlike every other operation, its geometry is NOT the source
  /// geometry.
  static YuvAbiV1FrameResult crop({
    required YuvAbiV1FrameInput source,
    required int left,
    required int top,
    required int width,
    required int height,
  }) {
    final YuvAbiV1DestinationLayout destinationLayout = _destinationWithGeometry(source, width: width, height: height);
    return _run(
      operation: YuvOperation.crop,
      nativeSymbol: yuvSymbolCropV1,
      source: source,
      destinationLayout: destinationLayout,
      allocateOptions: (allocator) => _allocateCropOptions(allocator, left: left, top: top, width: width, height: height).cast(),
      freeOptions: (allocator, options) => allocator.free(options.cast()),
      invoke: (src, dst, options) => ffiBingings.yuv_crop_v1(src, dst, options.cast()),
    );
  }

  /// Runs `yuv_flip_v1`. [direction] is one of [yuvFlipHorizontal] /
  /// [yuvFlipVertical] (`yuv_abi_v1_constants.dart`); ABI v1 has no combined
  /// direction value. [operation] must be the matching
  /// [YuvOperation.flipHorizontal] / [YuvOperation.flipVertical], since both
  /// directions share this one native symbol and only the caller knows which
  /// was requested.
  static YuvAbiV1FrameResult flip({required YuvAbiV1FrameInput source, required int direction, required YuvOperation operation}) {
    final YuvAbiV1DestinationLayout destinationLayout = _sameGeometryDestination(source);
    return _run(
      operation: operation,
      nativeSymbol: yuvSymbolFlipV1,
      source: source,
      destinationLayout: destinationLayout,
      allocateOptions: (allocator) => _allocateFlipOptions(allocator, direction: direction).cast(),
      freeOptions: (allocator, options) => allocator.free(options.cast()),
      invoke: (src, dst, options) => ffiBingings.yuv_flip_v1(src, dst, options.cast()),
    );
  }

  /// Runs `yuv_rotate_v1`. [rotationDegrees] must be `0`, `90`, `180`, or
  /// `270`; `90`/`270` transpose the destination geometry (section 11), which
  /// this method computes for the caller.
  static YuvAbiV1FrameResult rotate({required YuvAbiV1FrameInput source, required int rotationDegrees}) {
    final bool transposed = rotationDegrees == 90 || rotationDegrees == 270;
    final YuvAbiV1DestinationLayout destinationLayout = transposed
        ? _destinationWithGeometry(source, width: source.height, height: source.width, transposedStrides: true)
        : _sameGeometryDestination(source);
    return _run(
      operation: YuvOperation.rotate,
      nativeSymbol: yuvSymbolRotateV1,
      source: source,
      destinationLayout: destinationLayout,
      allocateOptions: (allocator) => _allocateRotateOptions(allocator, rotationDegrees: rotationDegrees).cast(),
      freeOptions: (allocator, options) => allocator.free(options.cast()),
      invoke: (src, dst, options) => ffiBingings.yuv_rotate_v1(src, dst, options.cast()),
    );
  }

  static YuvAbiV1FrameResult _runEffect(
    YuvOperation operation,
    String nativeSymbol,
    YuvAbiV1FrameInput source,
    YuvAbiV1Region? region,
    int Function(ffi.Pointer<YuvConstFrameV1>, ffi.Pointer<YuvMutableFrameV1>, ffi.Pointer<YuvEffectOptionsV1>) invoke,
  ) {
    final YuvAbiV1DestinationLayout destinationLayout = _sameGeometryDestination(source);
    return _run(
      operation: operation,
      nativeSymbol: nativeSymbol,
      source: source,
      destinationLayout: destinationLayout,
      allocateOptions: (allocator) => _allocateEffectOptions(allocator, region: region, width: source.width, height: source.height).cast(),
      freeOptions: (allocator, options) => allocator.free(options.cast()),
      invoke: (src, dst, options) => invoke(src, dst, options.cast()),
      preserveOutsideRoi: region != null,
    );
  }

  /// A destination with the source's own geometry and each plane's row/pixel
  /// stride left tight (no caller-supplied padding): every operation except
  /// crop and 90/270 rotation uses this.
  static YuvAbiV1DestinationLayout _sameGeometryDestination(YuvAbiV1FrameInput source) {
    return _destinationWithGeometry(source, width: source.width, height: source.height);
  }

  /// Builds a tight-stride destination layout for [width]/[height] using
  /// [source]'s format. `transposedStrides` exists only for readability at
  /// call sites (rotate 90/270): the tight-stride formula already depends on
  /// the destination width it is given, so no extra logic is needed for it.
  static YuvAbiV1DestinationLayout _destinationWithGeometry(
    YuvAbiV1FrameInput source, {
    required int width,
    required int height,
    bool transposedStrides = false,
  }) {
    final int planeCount = yuvAbiV1PlaneCount(source.format);
    final List<int> rowStrides = <int>[];
    final List<int> pixelStrides = <int>[];
    for (int planeIndex = 0; planeIndex < planeCount; planeIndex++) {
      final int sampleBytes = yuvAbiV1SampleBytes(source.format, planeIndex);
      final int planeWidth = planeIndex == 0 ? width : yuvAbiV1ChromaExtent(width);
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

  static YuvAbiV1FrameResult _run({
    required YuvOperation operation,
    required String nativeSymbol,
    required YuvAbiV1FrameInput source,
    required YuvAbiV1DestinationLayout destinationLayout,
    required ffi.Pointer<ffi.NativeType> Function(NativeAllocator allocator) allocateOptions,
    required void Function(NativeAllocator allocator, ffi.Pointer<ffi.NativeType> options) freeOptions,
    required int Function(ffi.Pointer<YuvConstFrameV1>, ffi.Pointer<YuvMutableFrameV1>, ffi.Pointer<ffi.NativeType>) invoke,
    bool preserveOutsideRoi = false,
  }) {
    final int expectedPlaneCount = yuvAbiV1PlaneCount(source.format);
    if (source.planes.length != expectedPlaneCount) {
      // Step 1 (defensive): reject a caller mistake before any allocation.
      // Native validation would also catch this as INVALID_ARGUMENT, but
      // that costs a source-plane copy first for no benefit.
      throw ArgumentError.value(source.planes.length, 'source.planes.length', 'format ${source.format} requires $expectedPlaneCount plane(s)');
    }

    final NativeAllocator allocator = NativeAllocator.instance;

    // Every allocation this method makes is reachable afterwards from
    // exactly one place: the plane pointers live inside the frame struct
    // just allocated for them, and `options` is held directly. `finally`
    // below walks those same structures to free everything -- there is
    // deliberately no separate side list of allocations to keep in sync with
    // them, which would risk exactly the double-free it would be meant to
    // guard against.
    ffi.Pointer<YuvConstFrameV1>? sourceFrame;
    ffi.Pointer<YuvMutableFrameV1>? destinationFrame;
    ffi.Pointer<ffi.NativeType>? options;

    try {
      // Step 2: allocate/copy read-only source staging.
      sourceFrame = _allocateConstFrame(allocator, source);

      // Step 3: allocate and seed destination staging. ROI effects/blur need
      // the destination pre-populated with source samples so bytes outside
      // the ROI survive untouched (section 11: "ROI effects seed the
      // destination from source..."); every other operation replaces the
      // whole destination, so a zero-filled buffer is the correct seed.
      destinationFrame = _allocateMutableFrame(allocator, destinationLayout, seedFromSource: preserveOutsideRoi ? source : null);

      // Step 4: allocate versioned options.
      options = allocateOptions(allocator);

      // Step 5: invoke exactly one format-independent symbol -- or, in a
      // test that has set debugInvokeOverride (YUV-36k), that override
      // instead, so the destination-seeding and copy-back steps around it
      // are exercised for real without requiring yuv_ffi.dll.
      final int status = (debugInvokeOverride ?? invoke)(sourceFrame, destinationFrame, options);

      // Step 6: map non-zero status to a Dart exception before any
      // destination byte is read back.
      if (status != yuvStatusOk) {
        yuvThrowForStatus(status: status, operation: operation, nativeSymbol: nativeSymbol);
      }

      // Step 7: copy destination into a Dart draft.
      final List<Uint8List> resultPlanes = _copyDestinationPlanes(destinationFrame, destinationLayout);
      return YuvAbiV1FrameResult(resultPlanes);
    } finally {
      // Step 9: dispose options, destination, and source, in a single
      // `finally` regardless of outcome, in reverse allocation order. Each
      // helper is itself defensive against a partially constructed frame --
      // see `_allocateConstFrame`/`_allocateMutableFrame` -- so this is safe
      // to call even when construction threw partway through.
      if (options != null) {
        freeOptions(allocator, options);
      }
      _freeMutableFrame(allocator, destinationFrame, destinationLayout);
      _freeConstFrame(allocator, sourceFrame, source);
    }
  }

  /// Allocates the source frame struct and one native buffer per source
  /// plane, copying [source]'s bytes into each.
  ///
  /// Transactional: if any
  /// allocation or copy throws partway through, every pointer this call
  /// itself created earlier is freed here, before the exception propagates.
  /// The caller's `finally` therefore only ever calls [_freeConstFrame] on a
  /// value this method fully completed -- never on a partially built one --
  /// which is what makes it safe for [_freeConstFrame] to assume every
  /// non-null plane pointer it walks is either real or `calloc`-zeroed
  /// `nullptr`, with no partially-constructed frame in between.
  static ffi.Pointer<YuvConstFrameV1> _allocateConstFrame(NativeAllocator allocator, YuvAbiV1FrameInput source) {
    final ffi.Pointer<YuvConstFrameV1> frame = allocator.allocate<YuvConstFrameV1>(ffi.sizeOf<YuvConstFrameV1>());

    try {
      frame.ref.structSize = ffi.sizeOf<YuvConstFrameV1>();
      frame.ref.abiVersion = yuvAbiVersion1;
      frame.ref.format = source.format;
      frame.ref.planeCount = source.planes.length;
      frame.ref.width = source.width;
      frame.ref.height = source.height;
      frame.ref.colorMatrix = yuvAbiV1ColorMatrixFor(source.format);
      frame.ref.colorRange = yuvAbiV1ColorRangeFor(source.format);

      for (int i = 0; i < source.planes.length; i++) {
        final YuvAbiV1PlaneInput plane = source.planes[i];
        final ffi.Pointer<ffi.Uint8> data = allocator.allocate<ffi.Uint8>(plane.bytes.length);
        // Written to the struct immediately, before the byte copy: if the
        // copy itself throws, `_freeConstFrame`'s walk over
        // `frame.ref.planes[*].data` below still finds and frees `data`.
        frame.ref.planes[i].data = data;
        data.asTypedList(plane.bytes.length).setAll(0, plane.bytes);

        final YuvConstPlaneV1 target = frame.ref.planes[i];
        target.length = plane.bytes.length;
        target.rowStride = plane.rowStride;
        target.pixelStride = plane.pixelStride;
        target.sampleBytes = yuvAbiV1SampleBytes(source.format, i);
      }
      // Unused plane slots (fewer than 3 required by format) are left
      // zero-filled by `calloc`, matching "Unused planes are zero-filled
      // descriptors with null data" (section 9).
    } catch (_) {
      _freeConstFrame(allocator, frame, source);
      rethrow;
    }

    return frame;
  }

  static void _freeConstFrame(NativeAllocator allocator, ffi.Pointer<YuvConstFrameV1>? frame, YuvAbiV1FrameInput source) {
    if (frame == null) return;
    for (int i = 0; i < source.planes.length; i++) {
      final ffi.Pointer<ffi.Uint8> data = frame.ref.planes[i].data;
      if (data != ffi.nullptr) {
        allocator.free(data);
      }
    }
    allocator.free(frame);
  }

  /// Allocates the destination frame struct and one native buffer per
  /// destination plane, per [layout].
  ///
  /// When [seedFromSource] is `null`, each buffer is `calloc`-zeroed: every
  /// non-ROI operation replaces the whole destination, so a zeroed buffer is
  /// the correct starting state. When it is given (ROI effects/blur only --
  /// callers pass it exactly when [preserveOutsideRoi] told [_run] the
  /// operation has an enabled ROI), each buffer is instead seeded with
  /// [seedFromSource]'s samples so bytes outside the ROI the native call
  /// writes remain the source's exact values (section 11: "ROI effects seed
  /// the destination from source..."). [seedFromSource] and [layout] always
  /// share geometry here -- every ROI-capable call uses
  /// [_sameGeometryDestination] -- but their row/pixel strides may still
  /// differ, so seeding copies sample-by-sample through both planes' strides
  /// rather than a raw byte copy.
  ///
  /// Transactional in the same sense as [_allocateConstFrame]: any throw
  /// partway through is caught, everything allocated so far is freed through
  /// [_freeMutableFrame], and the exception is rethrown.
  static ffi.Pointer<YuvMutableFrameV1> _allocateMutableFrame(
    NativeAllocator allocator,
    YuvAbiV1DestinationLayout layout, {
    YuvAbiV1FrameInput? seedFromSource,
  }) {
    final ffi.Pointer<YuvMutableFrameV1> frame = allocator.allocate<YuvMutableFrameV1>(ffi.sizeOf<YuvMutableFrameV1>());
    final int planeCount = yuvAbiV1PlaneCount(layout.format);

    try {
      frame.ref.structSize = ffi.sizeOf<YuvMutableFrameV1>();
      frame.ref.abiVersion = yuvAbiVersion1;
      frame.ref.format = layout.format;
      frame.ref.planeCount = planeCount;
      frame.ref.width = layout.width;
      frame.ref.height = layout.height;
      frame.ref.colorMatrix = yuvAbiV1ColorMatrixFor(layout.format);
      frame.ref.colorRange = yuvAbiV1ColorRangeFor(layout.format);

      for (int i = 0; i < planeCount; i++) {
        final int rowStride = layout.planeRowStrides[i];
        final int planeWidth = i == 0 ? layout.width : yuvAbiV1ChromaExtent(layout.width);
        final int planeHeight = i == 0 ? layout.height : yuvAbiV1ChromaExtent(layout.height);
        final int length = rowStride * planeHeight;

        final ffi.Pointer<ffi.Uint8> data = allocator.allocate<ffi.Uint8>(length);
        frame.ref.planes[i].data = data;

        final YuvMutablePlaneV1 target = frame.ref.planes[i];
        target.length = length;
        target.rowStride = rowStride;
        target.pixelStride = layout.planePixelStrides[i];
        final int sampleBytes = yuvAbiV1SampleBytes(layout.format, i);
        target.sampleBytes = sampleBytes;

        if (seedFromSource != null) {
          _seedPlaneFromSource(
            destination: data.asTypedList(length),
            destinationRowStride: rowStride,
            destinationPixelStride: layout.planePixelStrides[i],
            source: seedFromSource.planes[i].bytes,
            sourceRowStride: seedFromSource.planes[i].rowStride,
            sourcePixelStride: seedFromSource.planes[i].pixelStride,
            planeWidth: planeWidth,
            planeHeight: planeHeight,
            sampleBytes: sampleBytes,
          );
        }
        // else: `calloc` already zero-filled `data`, which is the seed for
        // every non-ROI operation.
      }
    } catch (_) {
      _freeMutableFrame(allocator, frame, layout);
      rethrow;
    }

    return frame;
  }

  /// Copies [source] into [destination] sample-by-sample, in logical
  /// `(row, sample)` coordinates, using each side's own row/pixel stride.
  /// Row and pixel padding in [destination] outside the copied samples is
  /// left as `calloc` zeroed it -- only the active `planeWidth x planeHeight`
  /// samples are the destination's seeded content.
  static void _seedPlaneFromSource({
    required Uint8List destination,
    required int destinationRowStride,
    required int destinationPixelStride,
    required Uint8List source,
    required int sourceRowStride,
    required int sourcePixelStride,
    required int planeWidth,
    required int planeHeight,
    required int sampleBytes,
  }) {
    for (int row = 0; row < planeHeight; row++) {
      final int destinationRowStart = row * destinationRowStride;
      final int sourceRowStart = row * sourceRowStride;
      for (int col = 0; col < planeWidth; col++) {
        final int destinationOffset = destinationRowStart + col * destinationPixelStride;
        final int sourceOffset = sourceRowStart + col * sourcePixelStride;
        for (int b = 0; b < sampleBytes; b++) {
          destination[destinationOffset + b] = source[sourceOffset + b];
        }
      }
    }
  }

  static void _freeMutableFrame(NativeAllocator allocator, ffi.Pointer<YuvMutableFrameV1>? frame, YuvAbiV1DestinationLayout layout) {
    if (frame == null) return;
    final int planeCount = yuvAbiV1PlaneCount(layout.format);
    for (int i = 0; i < planeCount; i++) {
      final ffi.Pointer<ffi.Uint8> data = frame.ref.planes[i].data;
      if (data != ffi.nullptr) {
        allocator.free(data);
      }
    }
    allocator.free(frame);
  }

  static List<Uint8List> _copyDestinationPlanes(ffi.Pointer<YuvMutableFrameV1> frame, YuvAbiV1DestinationLayout layout) {
    final int planeCount = yuvAbiV1PlaneCount(layout.format);
    final List<Uint8List> result = <Uint8List>[];
    for (int i = 0; i < planeCount; i++) {
      final YuvMutablePlaneV1 plane = frame.ref.planes[i];
      // Copies out of native memory into a Dart-owned buffer before the
      // native allocation is freed in the runner's `finally` block.
      result.add(Uint8List.fromList(plane.data.asTypedList(plane.length)));
    }
    return result;
  }

  static ffi.Pointer<YuvConvertOptionsV1> _allocateConvertOptions(NativeAllocator allocator) {
    final ffi.Pointer<YuvConvertOptionsV1> options = allocator.allocate<YuvConvertOptionsV1>(ffi.sizeOf<YuvConvertOptionsV1>());
    options.ref.structSize = ffi.sizeOf<YuvConvertOptionsV1>();
    options.ref.abiVersion = yuvAbiVersion1;
    return options;
  }

  static ffi.Pointer<YuvEffectOptionsV1> _allocateEffectOptions(
    NativeAllocator allocator, {
    required YuvAbiV1Region? region,
    required int width,
    required int height,
  }) {
    final ffi.Pointer<YuvEffectOptionsV1> options = allocator.allocate<YuvEffectOptionsV1>(ffi.sizeOf<YuvEffectOptionsV1>());
    options.ref.structSize = ffi.sizeOf<YuvEffectOptionsV1>();
    options.ref.abiVersion = yuvAbiVersion1;
    _writeRegion(options.ref.region, region, width: width, height: height);
    return options;
  }

  static ffi.Pointer<YuvBlurOptionsV1> _allocateBlurOptions(
    NativeAllocator allocator, {
    required int radius,
    required double sigma,
    required YuvAbiV1Region? region,
    required int width,
    required int height,
  }) {
    final ffi.Pointer<YuvBlurOptionsV1> options = allocator.allocate<YuvBlurOptionsV1>(ffi.sizeOf<YuvBlurOptionsV1>());
    options.ref.structSize = ffi.sizeOf<YuvBlurOptionsV1>();
    options.ref.abiVersion = yuvAbiVersion1;
    options.ref.radius = radius;
    options.ref.borderMode = yuvBorderClamp;
    options.ref.sigma = sigma;
    _writeRegion(options.ref.region, region, width: width, height: height);
    return options;
  }

  static ffi.Pointer<YuvCropOptionsV1> _allocateCropOptions(
    NativeAllocator allocator, {
    required int left,
    required int top,
    required int width,
    required int height,
  }) {
    final ffi.Pointer<YuvCropOptionsV1> options = allocator.allocate<YuvCropOptionsV1>(ffi.sizeOf<YuvCropOptionsV1>());
    options.ref.structSize = ffi.sizeOf<YuvCropOptionsV1>();
    options.ref.abiVersion = yuvAbiVersion1;
    options.ref.left = left;
    options.ref.top = top;
    options.ref.width = width;
    options.ref.height = height;
    return options;
  }

  static ffi.Pointer<YuvFlipOptionsV1> _allocateFlipOptions(NativeAllocator allocator, {required int direction}) {
    final ffi.Pointer<YuvFlipOptionsV1> options = allocator.allocate<YuvFlipOptionsV1>(ffi.sizeOf<YuvFlipOptionsV1>());
    options.ref.structSize = ffi.sizeOf<YuvFlipOptionsV1>();
    options.ref.abiVersion = yuvAbiVersion1;
    options.ref.direction = direction;
    return options;
  }

  static ffi.Pointer<YuvRotateOptionsV1> _allocateRotateOptions(NativeAllocator allocator, {required int rotationDegrees}) {
    final ffi.Pointer<YuvRotateOptionsV1> options = allocator.allocate<YuvRotateOptionsV1>(ffi.sizeOf<YuvRotateOptionsV1>());
    options.ref.structSize = ffi.sizeOf<YuvRotateOptionsV1>();
    options.ref.abiVersion = yuvAbiVersion1;
    options.ref.rotationDegrees = rotationDegrees;
    return options;
  }

  /// Writes [region] into [target] (already-allocated struct memory, either
  /// standalone or, more commonly, the embedded `region` field of a blur or
  /// effect options struct). A `null` region writes the disabled form: every
  /// coordinate zeroed, per section 10 ("when 0, all four coordinates and
  /// reserved0 must be zero").
  static void _writeRegion(YuvRegionOptionsV1 target, YuvAbiV1Region? region, {required int width, required int height}) {
    target.structSize = ffi.sizeOf<YuvRegionOptionsV1>();
    target.abiVersion = yuvAbiVersion1;
    if (region == null) {
      target.enabled = 0;
      target.left = 0;
      target.top = 0;
      target.right = 0;
      target.bottom = 0;
      target.reserved0 = 0;
      return;
    }
    target.enabled = 1;
    target.left = region.left;
    target.top = region.top;
    target.right = region.right;
    target.bottom = region.bottom;
    target.reserved0 = 0;
  }
}

/// Which uniform- or Gaussian-weighted blur `yuv_*_v1` symbol
/// [YuvAbiV1Runner.blur] dispatches to.
enum YuvAbiV1BlurKind {
  /// `yuv_gaussian_blur_v1`.
  gaussian,

  /// `yuv_mean_blur_v1`.
  mean,

  /// `yuv_box_blur_v1`.
  box,
}
