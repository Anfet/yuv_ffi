/// The names of the eleven ABI v1 processing symbols
/// (`src/yuv/abi/h/yuv_ops_v1.h`, `doc/api-abi-0.4-design.md` section 11), as
/// the Dart side of the package names them.
///
/// This is the Dart-dispatch side of the four-way symbol-manifest gate (YUV-28):
/// `test/abi_symbol_manifest_test.dart` requires exact agreement between the C
/// header, the ffigen allowlist, the WASM `EXPORTED_FUNCTIONS` list, and this
/// file -- and requires that every name here is actually reached from dispatch
/// code rather than only declared. A symbol that is missing from any one of the
/// four, or declared here but never dispatched, fails that test.
///
/// It lives in `shared/` deliberately: both the native runner
/// (`impl/io/abi/yuv_abi_v1_runner.dart`) and the Web backend
/// (`impl/web/yuv_web.dart`) name their ABI v1 entry points from this one list,
/// so the two backends cannot drift onto different spellings of the same ABI.
/// Being able to name a symbol is not the same as supporting the operation: Web
/// remains a partial WASM backend.
library;

/// `yuv_convert_v1` -- format conversion.
const String yuvSymbolConvertV1 = 'yuv_convert_v1';

/// `yuv_black_white_v1` -- threshold to black and white.
const String yuvSymbolBlackWhiteV1 = 'yuv_black_white_v1';

/// `yuv_grayscale_v1` -- drop chroma.
const String yuvSymbolGrayscaleV1 = 'yuv_grayscale_v1';

/// `yuv_negate_v1` -- invert samples.
const String yuvSymbolNegateV1 = 'yuv_negate_v1';

/// `yuv_gaussian_blur_v1` -- Gaussian-weighted blur.
const String yuvSymbolGaussianBlurV1 = 'yuv_gaussian_blur_v1';

/// `yuv_mean_blur_v1` -- uniform-weight mean blur.
const String yuvSymbolMeanBlurV1 = 'yuv_mean_blur_v1';

/// `yuv_box_blur_v1` -- uniform-weight box blur.
const String yuvSymbolBoxBlurV1 = 'yuv_box_blur_v1';

/// `yuv_crop_v1` -- crop to a sub-rectangle.
const String yuvSymbolCropV1 = 'yuv_crop_v1';

/// `yuv_flip_v1` -- mirror horizontally or vertically.
const String yuvSymbolFlipV1 = 'yuv_flip_v1';

/// `yuv_rotate_v1` -- rotate by a multiple of 90 degrees.
const String yuvSymbolRotateV1 = 'yuv_rotate_v1';

/// `yuv_chroma_swap_v1` -- swap interleaved chroma order.
const String yuvSymbolChromaSwapV1 = 'yuv_chroma_swap_v1';

/// Every ABI v1 processing symbol, in `doc/api-abi-0.4-design.md` section 11
/// order.
///
/// The manifest gate asserts this holds exactly eleven distinct names, so a
/// symbol added to the header without being added here -- or the reverse --
/// fails rather than being silently half-wired.
const List<String> yuvAbiV1Symbols = <String>[
  yuvSymbolConvertV1,
  yuvSymbolBlackWhiteV1,
  yuvSymbolGrayscaleV1,
  yuvSymbolNegateV1,
  yuvSymbolGaussianBlurV1,
  yuvSymbolMeanBlurV1,
  yuvSymbolBoxBlurV1,
  yuvSymbolCropV1,
  yuvSymbolFlipV1,
  yuvSymbolRotateV1,
  yuvSymbolChromaSwapV1,
];
