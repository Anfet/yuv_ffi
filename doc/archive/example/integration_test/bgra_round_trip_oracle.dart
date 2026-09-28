import 'dart:typed_data';

/// Independent oracle for the `applyRgbaBytes()` -> `toBgraBytes()` round
/// trip that `bgra00_stage_breakdown_pixel3_test.dart` and
/// `bgra04_copy_out_pixel3_test.dart` check every timed sample against.
///
/// A naive RGBA<->BGRA byte-order permutation is **not** a valid oracle for
/// that round trip: `applyRgbaBytes()` (`YuvImageImpl.legacyFromRgba8888`,
/// `lib/src/yuv/impl/io/yuv_image.dart`) converts the caller's RGBA bytes
/// into this image's own YUV storage format through `YuvAbiV1Runner.convert`,
/// which dispatches to native `yuv_convert_from_packed`
/// (`src/yuv/abi/yuv_convert_v1.c`) -- a lossy BT.601 RGB->YUV *encode* with
/// 2x2 chroma block averaging -- and `toBgraBytes()` afterwards decodes that
/// YUV back to BGRA through `yuv_convert_to_bgra`'s own BT.601 formula. Two
/// different coefficient sets and a lossy 4:2:0 chroma subsampling step sit
/// between the two calls, so round-tripping a non-uniform RGBA image through
/// them does not reproduce the original bytes: an earlier draft of these two
/// files compared `toBgraBytes()`'s result directly against the input RGBA
/// (permuted to BGRA order) and would have failed on the first real device
/// run, without measuring anything -- verified empirically against the same
/// deterministic input this file's generator produces (a throwaway
/// comparison found 79 of 128 sampled bytes differed).
///
/// This oracle instead walks the same two steps in pure Dart, matching
/// `src/yuv/abi/yuv_convert_v1.c` literally:
///
/// 1. [encodeRgbaToYuv420] -- `yuv_convert_from_packed`'s
///    `YUV_CONVERT_PACKED_SAMPLE` macro (luma per pixel: `(66r + 129g + 25b +
///    128) >> 8 + 16`) and its 2x2 block-averaged chroma (`u = (-38r' - 74g' +
///    112b' + 128) >> 8 + 128`, `v = (112r' - 94g' - 18b' + 128) >> 8 + 128`,
///    where `r'/g'/b'` are the block's integer-truncated average -- `red /
///    count` in C using `int32_t` division, i.e. truncating, not rounding).
/// 2. [decodeYuv420ToBgra] -- the same decode formula
///    `speed_00_dart_ffi/test/yuv_convert_v1_bgra_stages_test.dart`'s
///    `_pixel`/`_oracleBgra` already use, and that `yuv_convert_v1.c`'s
///    `yuv_convert_store_bgra`/`yuv_convert_clip` implement: `c298 = 298 *
///    (Y - 16)`, `d = U - 128`, `e = V - 128`, clip8`((c298 + 409e + 128) >>
///    8)` for R, `((c298 - 100d - 208e + 128) >> 8)` for G, `((c298 + 516d +
///    128) >> 8)` for B, alpha 255, BGRA byte order.
///
/// Both source chroma layouts this package exposes through `YuvImage.nv12()`/
/// `YuvImage.i420()` (interleaved UV vs. separate U/V planes) carry the same
/// U/V *values* -- only their storage differs -- so one oracle path covers
/// both `toBgraBytes()` targets; the tests using this file convert straight
/// to BGRA and never re-inspect the intermediate YUV planes, so no NV12/I420
/// branching is needed here at all.
int _clip8(int value) => value < 0 ? 0 : (value > 255 ? 255 : value);

/// Per-2x2-block Y/U/V produced by [encodeRgbaToYuv420], returned as three
/// flat planes at full luma resolution for Y and half resolution (rounded up)
/// for U/V -- the same geometry `YuvAbiV1Runner`'s I420/NV12 destination
/// layouts use.
class Yuv420Planes {
  Yuv420Planes(this.y, this.u, this.v, this.chromaWidth, this.chromaHeight);
  final Uint8List y;
  final Uint8List u;
  final Uint8List v;
  final int chromaWidth;
  final int chromaHeight;
}

/// Encodes tightly packed RGBA8888 [rgba] ([width]x[height]) into BT.601
/// limited-range YUV 4:2:0, replicating `yuv_convert_from_packed`'s luma and
/// 2x2-block-averaged chroma formulas exactly, including its integer
/// (truncating) block average and the `>> 8` fixed-point rounding shared with
/// the decode side.
Yuv420Planes encodeRgbaToYuv420(Uint8List rgba, int width, int height) {
  final y = Uint8List(width * height);
  final chromaWidth = (width + 1) ~/ 2;
  final chromaHeight = (height + 1) ~/ 2;
  final u = Uint8List(chromaWidth * chromaHeight);
  final v = Uint8List(chromaWidth * chromaHeight);

  int sampleLuma(int px, int py) {
    final i = (py * width + px) * 4;
    final r = rgba[i];
    final g = rgba[i + 1];
    final b = rgba[i + 2];
    final luma = ((66 * r + 129 * g + 25 * b + 128) >> 8) + 16;
    y[py * width + px] = luma;
    return luma;
  }

  for (var by = 0; by < chromaHeight; by++) {
    final y0 = by * 2;
    final hasSecondRow = y0 + 1 < height;
    for (var bx = 0; bx < chromaWidth; bx++) {
      final x0 = bx * 2;
      final hasSecondCol = x0 + 1 < width;

      var redSum = 0, greenSum = 0, blueSum = 0, count = 0;
      void accumulate(int px, int py) {
        final i = (py * width + px) * 4;
        redSum += rgba[i];
        greenSum += rgba[i + 1];
        blueSum += rgba[i + 2];
        count++;
      }

      sampleLuma(x0, y0);
      accumulate(x0, y0);
      if (hasSecondCol) {
        sampleLuma(x0 + 1, y0);
        accumulate(x0 + 1, y0);
      }
      if (hasSecondRow) {
        sampleLuma(x0, y0 + 1);
        accumulate(x0, y0 + 1);
        if (hasSecondCol) {
          sampleLuma(x0 + 1, y0 + 1);
          accumulate(x0 + 1, y0 + 1);
        }
      }

      // C's `int32_t` division on non-negative operands truncates toward
      // zero, same as Dart's `~/`.
      final r = redSum ~/ count;
      final g = greenSum ~/ count;
      final b = blueSum ~/ count;
      final uu = ((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128;
      final vv = ((112 * r - 94 * g - 18 * b + 128) >> 8) + 128;
      u[by * chromaWidth + bx] = uu & 0xFF;
      v[by * chromaWidth + bx] = vv & 0xFF;
    }
  }

  return Yuv420Planes(y, u, v, chromaWidth, chromaHeight);
}

/// Decodes [planes] (as produced by [encodeRgbaToYuv420]) into tightly
/// packed BGRA8888, replicating `yuv_convert_to_bgra`/`yuv_convert_store_bgra`'s
/// BT.601 limited-range formula exactly -- the same formula
/// `yuv_convert_v1_bgra_stages_test.dart`'s `_pixel` oracle already uses.
Uint8List decodeYuv420ToBgra(Yuv420Planes planes, int width, int height) {
  final bgra = Uint8List(width * height * 4);
  for (var py = 0; py < height; py++) {
    final cy = py ~/ 2;
    for (var px = 0; px < width; px++) {
      final cx = px ~/ 2;
      final yy = planes.y[py * width + px];
      final uu = planes.u[cy * planes.chromaWidth + cx];
      final vv = planes.v[cy * planes.chromaWidth + cx];

      final c298 = 298 * (yy - 16);
      final d = uu - 128;
      final e = vv - 128;
      final bTerm = 516 * d + 128;
      final gTerm = -100 * d - 208 * e + 128;
      final rTerm = 409 * e + 128;

      final offset = (py * width + px) * 4;
      bgra[offset] = _clip8((c298 + bTerm) >> 8);
      bgra[offset + 1] = _clip8((c298 + gTerm) >> 8);
      bgra[offset + 2] = _clip8((c298 + rTerm) >> 8);
      bgra[offset + 3] = 255;
    }
  }
  return bgra;
}

/// Runs the full oracle round trip: RGBA -> BT.601 YUV 4:2:0 encode -> BT.601
/// BGRA decode. This is the value `toBgraBytes()`/`toBgra()` must byte-exact
/// match after `applyRgbaBytes(rgba)` on a freshly allocated NV12 or I420
/// image of the same [width]/[height] -- both source chroma layouts encode to
/// the same U/V values (see this library's doc comment), so one oracle call
/// covers both.
Uint8List oracleRgbaThroughYuv420ToBgra(Uint8List rgba, int width, int height) {
  final planes = encodeRgbaToYuv420(rgba, width, height);
  return decodeYuv420ToBgra(planes, width, height);
}
