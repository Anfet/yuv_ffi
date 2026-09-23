import 'package:yuv_ffi/src/yuv/shared/yuv_abi_v1_symbols.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_pixel_format.dart';

/// The exhaustive public processing operations a backend can expose
/// capabilities for (`doc/api-abi-0.4-design.md` section 7).
///
/// Every member maps to exactly one required ABI v1 processing export (the
/// "Required processing export" table in section 7); [YuvCapabilities]
/// answers whether that export resolved on the currently loaded backend, not
/// whether arbitrary input to the operation is valid.
enum YuvOperation {
  /// `to*`, `applyFormat`, and RGBA import -- dispatched through
  /// `yuv_convert_v1`.
  convert,

  /// Threshold black/white effect -- `yuv_black_white_v1`.
  blackWhite,

  /// Grayscale effect -- `yuv_grayscale_v1`.
  grayscale,

  /// Visible-RGB negate effect -- `yuv_negate_v1`.
  negate,

  /// Gaussian-weighted blur -- `yuv_gaussian_blur_v1`.
  gaussianBlur,

  /// Uniform mean blur -- `yuv_mean_blur_v1`.
  meanBlur,

  /// Normalized box blur -- `yuv_box_blur_v1`.
  boxBlur,

  /// Crop to destination geometry -- `yuv_crop_v1`.
  crop,

  /// Horizontal flip -- `yuv_flip_v1`.
  flipHorizontal,

  /// Vertical flip -- `yuv_flip_v1`.
  flipVertical,

  /// 0/90/180/270 rotation -- `yuv_rotate_v1`.
  rotate,

  /// Swap U/V sample values without changing the NV12 format --
  /// `yuv_chroma_swap_v1`.
  chromaSwap,
}

/// The single ABI v1 processing symbol [operation] dispatches through
/// (section 7's "Required processing export" table). Horizontal and vertical
/// flip share `yuv_flip_v1`, and both blurs plus Gaussian each own their own
/// `yuv_*_blur_v1` export.
String yuvAbiV1SymbolForOperation(YuvOperation operation) => switch (operation) {
  YuvOperation.convert => yuvSymbolConvertV1,
  YuvOperation.blackWhite => yuvSymbolBlackWhiteV1,
  YuvOperation.grayscale => yuvSymbolGrayscaleV1,
  YuvOperation.negate => yuvSymbolNegateV1,
  YuvOperation.gaussianBlur => yuvSymbolGaussianBlurV1,
  YuvOperation.meanBlur => yuvSymbolMeanBlurV1,
  YuvOperation.boxBlur => yuvSymbolBoxBlurV1,
  YuvOperation.crop => yuvSymbolCropV1,
  YuvOperation.flipHorizontal => yuvSymbolFlipV1,
  YuvOperation.flipVertical => yuvSymbolFlipV1,
  YuvOperation.rotate => yuvSymbolRotateV1,
  YuvOperation.chromaSwap => yuvSymbolChromaSwapV1,
};

/// Every [YuvOperation] whose required ABI v1 export [symbolIsAvailable]
/// reports as resolved.
///
/// Shared by both backends' initializers so IO (`dlsym`/`providesSymbol`) and
/// Web (WASM module export lookup) compute their capability snapshot the same
/// way: from the real presence of each operation's required symbol, never a
/// hardcoded "everything is supported" assumption.
Set<YuvOperation> yuvAvailableOperations(bool Function(String symbol) symbolIsAvailable) => {
  for (final operation in YuvOperation.values)
    if (symbolIsAvailable(yuvAbiV1SymbolForOperation(operation))) operation,
};

/// Whether [operation] accepts [sourceFormat] as input and, for [convert]
/// only, produces [destinationFormat].
///
/// Encodes the "Format, layout, and geometry matrix" table
/// (`doc/api-abi-0.4-design.md` section 11): [convert] accepts any of I420,
/// NV12, BGRA8888 as both source and destination (RGBA8888 import is a
/// distinct one-plane source not modeled by [YuvPixelFormat] and is not a
/// query this method answers); every effect, blur, geometric transform, and
/// crop is same-format in and out; [chromaSwap] accepts only NV12.
///
/// [destinationFormat] is required for [YuvOperation.convert] and ignored for
/// every other operation, which the design doc mandates to be same-format.
bool yuvAbiV1FormatPairSupported(YuvOperation operation, {required YuvPixelFormat sourceFormat, YuvPixelFormat? destinationFormat}) {
  switch (operation) {
    case YuvOperation.convert:
      if (destinationFormat == null) {
        return false;
      }
      return true;
    case YuvOperation.chromaSwap:
      return sourceFormat == YuvPixelFormat.nv12;
    case YuvOperation.blackWhite:
    case YuvOperation.grayscale:
    case YuvOperation.negate:
    case YuvOperation.gaussianBlur:
    case YuvOperation.meanBlur:
    case YuvOperation.boxBlur:
    case YuvOperation.crop:
    case YuvOperation.flipHorizontal:
    case YuvOperation.flipVertical:
    case YuvOperation.rotate:
      // Every YuvPixelFormat value (I420, NV12, BGRA8888) is a valid
      // same-format source/destination pair per section 11's matrix.
      return true;
  }
}
