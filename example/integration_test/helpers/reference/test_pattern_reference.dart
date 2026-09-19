/// Pure-Dart reference primitives for the YUV-10 fixture generator.
///
/// This library deliberately has no dependency on `yuv_ffi`, FFI, or WASM.
/// It models BT.601 limited-range 4:2:0 conversion and RGB operations so the
/// generated files remain an independent oracle for both package backends.
///
/// YUV-12 note: this is a verbatim copy of `test/helpers/reference/
/// test_pattern_reference.dart` (the root package's copy), not a symlink or
/// a cross-package relative import. It has to live inside the `example`
/// package because the dartdevc/DDC Web compiler resolves `org-dartlang-app:/`
/// relative imports rooted at the importing package and cannot escape that
/// package's own directory tree to reach `../../test/...` in a sibling
/// package -- that import style compiles fine under `flutter analyze` (which
/// just resolves file paths) but fails the real Web build. If the root copy
/// changes, re-copy it here; do not let the two drift silently.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as image;

const int referenceWidth = 512;
const int referenceHeight = 512;

String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

class RgbaFrame {
  RgbaFrame(this.width, this.height, Uint8List bytes) : bytes = Uint8List.fromList(bytes) {
    if (bytes.length != width * height * 4) {
      throw ArgumentError.value(bytes.length, 'bytes', 'must be tightly packed RGBA');
    }
  }

  final int width;
  final int height;
  final Uint8List bytes;

  Uint8List toBgra() {
    final result = Uint8List(bytes.length);
    for (var index = 0; index < bytes.length; index += 4) {
      result[index] = bytes[index + 2];
      result[index + 1] = bytes[index + 1];
      result[index + 2] = bytes[index];
      result[index + 3] = bytes[index + 3];
    }
    return result;
  }

  RgbaFrame transformPixels(int Function(int x, int y) sourceX, int Function(int x, int y) sourceY, int outputWidth, int outputHeight) {
    final result = Uint8List(outputWidth * outputHeight * 4);
    for (var y = 0; y < outputHeight; y++) {
      for (var x = 0; x < outputWidth; x++) {
        final source = (sourceY(x, y) * width + sourceX(x, y)) * 4;
        final destination = (y * outputWidth + x) * 4;
        result.setRange(destination, destination + 4, bytes, source);
      }
    }
    return RgbaFrame(outputWidth, outputHeight, result);
  }

  RgbaFrame crop(int left, int top, int cropWidth, int cropHeight) => transformPixels(
        (x, _) => left + x,
        (_, y) => top + y,
        cropWidth,
        cropHeight,
      );

  RgbaFrame flipHorizontally() => transformPixels((x, _) => width - 1 - x, (_, y) => y, width, height);

  RgbaFrame flipVertically() => transformPixels((x, _) => x, (_, y) => height - 1 - y, width, height);

  RgbaFrame rotate90() => transformPixels((_, y) => y, (x, _) => height - 1 - x, height, width);

  RgbaFrame rotate180() => transformPixels((x, _) => width - 1 - x, (_, y) => height - 1 - y, width, height);

  RgbaFrame rotate270() => transformPixels((_, y) => width - 1 - y, (x, _) => x, height, width);

  RgbaFrame grayscale() => _mapRgb((red, green, blue) {
        final gray = ((299 * red + 587 * green + 114 * blue + 500) ~/ 1000).clamp(0, 255);
        return (gray, gray, gray);
      });

  RgbaFrame blackwhite() => _mapRgb((red, green, blue) {
        final gray = ((299 * red + 587 * green + 114 * blue + 500) ~/ 1000).clamp(0, 255);
        final value = gray >= 128 ? 255 : 0;
        return (value, value, value);
      });

  RgbaFrame negate() => _mapRgb((red, green, blue) => (255 - red, 255 - green, 255 - blue));

  RgbaFrame gaussianBlur({required int radius, required int sigma}) {
    final kernel = _gaussianKernel(radius, sigma);
    return _convolve(kernel, radius);
  }

  RgbaFrame boxBlur({required int radius, int? left, int? top, int? rectWidth, int? rectHeight}) {
    final size = radius * 2 + 1;
    final weight = 1 / (size * size);
    return _convolve(
      List<double>.filled(size * size, weight),
      radius,
      left: left,
      top: top,
      rectWidth: rectWidth,
      rectHeight: rectHeight,
    );
  }

  RgbaFrame meanBlur({required int radius, int? left, int? top, int? rectWidth, int? rectHeight}) => boxBlur(
        radius: radius,
        left: left,
        top: top,
        rectWidth: rectWidth,
        rectHeight: rectHeight,
      );

  RgbaFrame _mapRgb((int, int, int) Function(int red, int green, int blue) map) {
    final result = Uint8List.fromList(bytes);
    for (var index = 0; index < result.length; index += 4) {
      final (red, green, blue) = map(result[index], result[index + 1], result[index + 2]);
      result[index] = red;
      result[index + 1] = green;
      result[index + 2] = blue;
    }
    return RgbaFrame(width, height, result);
  }

  RgbaFrame _convolve(List<double> kernel, int radius, {int? left, int? top, int? rectWidth, int? rectHeight}) {
    final result = Uint8List.fromList(bytes);
    final startX = left ?? 0;
    final startY = top ?? 0;
    final endX = startX + (rectWidth ?? width);
    final endY = startY + (rectHeight ?? height);
    final boundedStartX = startX.clamp(0, width).toInt();
    final boundedStartY = startY.clamp(0, height).toInt();
    final boundedEndX = endX.clamp(0, width).toInt();
    final boundedEndY = endY.clamp(0, height).toInt();
    final kernelSize = radius * 2 + 1;

    for (var y = boundedStartY; y < boundedEndY; y++) {
      for (var x = boundedStartX; x < boundedEndX; x++) {
        final destination = (y * width + x) * 4;
        for (var channel = 0; channel < 3; channel++) {
          var value = 0.0;
          for (var kernelY = -radius; kernelY <= radius; kernelY++) {
            final sourceY = (y + kernelY).clamp(0, height - 1).toInt();
            for (var kernelX = -radius; kernelX <= radius; kernelX++) {
              final sourceX = (x + kernelX).clamp(0, width - 1).toInt();
              final weight = kernel[(kernelY + radius) * kernelSize + kernelX + radius];
              value += bytes[(sourceY * width + sourceX) * 4 + channel] * weight;
            }
          }
          result[destination + channel] = value.round().clamp(0, 255);
        }
      }
    }
    return RgbaFrame(width, height, result);
  }
}

class Yuv420Frame {
  Yuv420Frame.i420(this.width, this.height, this.y, this.u, this.v) : uv = null;

  Yuv420Frame.nv21Uv(this.width, this.height, this.y, Uint8List interleavedUv)
      : u = null,
        v = null,
        uv = interleavedUv;

  final int width;
  final int height;
  final Uint8List y;
  final Uint8List? u;
  final Uint8List? v;

  /// The public `nv21` label uses the established legacy UV/NV12-like order:
  /// U then V in every interleaved chroma pair.
  final Uint8List? uv;

  bool get isI420 => uv == null;

  List<Uint8List> get planes => isI420 ? <Uint8List>[y, u!, v!] : <Uint8List>[y, uv!];

  RgbaFrame decode() {
    final output = Uint8List(width * height * 4);
    for (var row = 0; row < height; row++) {
      for (var column = 0; column < width; column++) {
        final chromaIndex = (row ~/ 2) * chromaWidth + column ~/ 2;
        final chromaU = isI420 ? u![chromaIndex] : uv![chromaIndex * 2];
        final chromaV = isI420 ? v![chromaIndex] : uv![chromaIndex * 2 + 1];
        final c = y[row * width + column] - 16;
        final d = chromaU - 128;
        final e = chromaV - 128;
        final destination = (row * width + column) * 4;
        output[destination] = _clip((298 * c + 409 * e + 128) >> 8);
        output[destination + 1] = _clip((298 * c - 100 * d - 208 * e + 128) >> 8);
        output[destination + 2] = _clip((298 * c + 516 * d + 128) >> 8);
        output[destination + 3] = 255;
      }
    }
    return RgbaFrame(width, height, output);
  }

  int get chromaWidth => (width + 1) ~/ 2;

  int get chromaHeight => (height + 1) ~/ 2;
}

Yuv420Frame rgbaToI420(RgbaFrame source) {
  final y = Uint8List(source.width * source.height);
  final chromaWidth = (source.width + 1) ~/ 2;
  final chromaHeight = (source.height + 1) ~/ 2;
  final u = Uint8List(chromaWidth * chromaHeight);
  final v = Uint8List(chromaWidth * chromaHeight);
  for (var row = 0; row < source.height; row++) {
    for (var column = 0; column < source.width; column++) {
      final index = (row * source.width + column) * 4;
      y[row * source.width + column] = _luma(source.bytes[index], source.bytes[index + 1], source.bytes[index + 2]);
    }
  }
  for (var row = 0; row < source.height; row += 2) {
    for (var column = 0; column < source.width; column += 2) {
      var red = 0;
      var green = 0;
      var blue = 0;
      var samples = 0;
      for (var yOffset = 0; yOffset < 2; yOffset++) {
        for (var xOffset = 0; xOffset < 2; xOffset++) {
          if (row + yOffset >= source.height || column + xOffset >= source.width) {
            continue;
          }
          final index = ((row + yOffset) * source.width + column + xOffset) * 4;
          red += source.bytes[index];
          green += source.bytes[index + 1];
          blue += source.bytes[index + 2];
          samples++;
        }
      }
      final chromaIndex = (row ~/ 2) * chromaWidth + column ~/ 2;
      u[chromaIndex] = _chromaU(red ~/ samples, green ~/ samples, blue ~/ samples);
      v[chromaIndex] = _chromaV(red ~/ samples, green ~/ samples, blue ~/ samples);
    }
  }
  return Yuv420Frame.i420(source.width, source.height, y, u, v);
}

Yuv420Frame i420ToNv21Uv(Yuv420Frame source) {
  if (!source.isI420) {
    throw ArgumentError.value(source, 'source', 'must be I420');
  }
  final uv = Uint8List(source.chromaWidth * source.chromaHeight * 2);
  for (var index = 0; index < source.u!.length; index++) {
    uv[index * 2] = source.u![index];
    uv[index * 2 + 1] = source.v![index];
  }
  return Yuv420Frame.nv21Uv(source.width, source.height, Uint8List.fromList(source.y), uv);
}

Map<String, Object> planeMetadata(Yuv420Frame frame, {required String layout}) {
  final yStride = switch (layout) {
    'padded' => frame.width + 8,
    'customStride' => frame.width + 3,
    _ => frame.width,
  };
  final chromaStride = switch (layout) {
    'padded' => frame.chromaWidth + 4,
    'customStride' => frame.chromaWidth + 2,
    _ => frame.chromaWidth,
  };
  final result = <String, Object>{
    'layout': layout,
    'planes': <Map<String, Object>>[
      _planeMap(frame.y, frame.height, yStride, 1, frame.width),
    ],
  };
  final planes = result['planes']! as List<Map<String, Object>>;
  if (frame.isI420) {
    planes.add(_planeMap(frame.u!, frame.chromaHeight, chromaStride, 1, frame.chromaWidth));
    planes.add(_planeMap(frame.v!, frame.chromaHeight, chromaStride, 1, frame.chromaWidth));
  } else {
    final uvRowBytes = frame.chromaWidth * 2;
    final uvStride = switch (layout) {
      'padded' => uvRowBytes + 8,
      'customStride' => uvRowBytes + 3,
      _ => uvRowBytes,
    };
    planes.add(_planeMap(frame.uv!, frame.chromaHeight, uvStride, 2, uvRowBytes));
  }
  return result;
}

Map<String, Object> bgraPlaneMetadata(Uint8List tightBgra, int width, int height, {required String layout}) => <String, Object>{
      'layout': layout,
      'planes': <Map<String, Object>>[
        _planeMap(
          tightBgra,
          height,
          switch (layout) {
            'padded' => width * 4 + 16,
            'customStride' => width * 4 + 7,
            _ => width * 4,
          },
          4,
          width * 4,
        ),
      ],
    };

Map<String, Object> _planeMap(Uint8List tight, int height, int rowStride, int pixelStride, int usefulRowBytes) {
  final bytes = Uint8List(height * rowStride);
  for (var row = 0; row < height; row++) {
    final destination = row * rowStride;
    final source = row * usefulRowBytes;
    bytes.setRange(destination, destination + usefulRowBytes, tight, source);
    bytes.fillRange(destination + usefulRowBytes, destination + rowStride, 0xa5);
  }
  return <String, Object>{
    'height': height,
    'rowStride': rowStride,
    'pixelStride': pixelStride,
    'byteLength': bytes.length,
    'sha256': sha256Hex(bytes),
  };
}

Uint8List encodePng(RgbaFrame frame) {
  final output = image.Image(width: frame.width, height: frame.height, numChannels: 4);
  for (var y = 0; y < frame.height; y++) {
    for (var x = 0; x < frame.width; x++) {
      final index = (y * frame.width + x) * 4;
      output.setPixelRgba(x, y, frame.bytes[index], frame.bytes[index + 1], frame.bytes[index + 2], frame.bytes[index + 3]);
    }
  }
  return Uint8List.fromList(image.encodePng(output, level: 6));
}

RgbaFrame decodePng(Uint8List png) {
  final decoded = image.decodePng(png);
  if (decoded == null) {
    throw ArgumentError.value(png, 'png', 'cannot decode PNG');
  }
  final rgba = Uint8List(decoded.width * decoded.height * 4);
  for (var y = 0; y < decoded.height; y++) {
    for (var x = 0; x < decoded.width; x++) {
      final pixel = decoded.getPixel(x, y);
      final index = (y * decoded.width + x) * 4;
      rgba[index] = pixel.r.toInt();
      rgba[index + 1] = pixel.g.toInt();
      rgba[index + 2] = pixel.b.toInt();
      rgba[index + 3] = pixel.a.toInt();
    }
  }
  return RgbaFrame(decoded.width, decoded.height, rgba);
}

List<double> _gaussianKernel(int radius, int sigma) {
  final size = radius * 2 + 1;
  final result = List<double>.filled(size * size, 0);
  var total = 0.0;
  final denominator = 2 * sigma * sigma;
  for (var y = -radius; y <= radius; y++) {
    for (var x = -radius; x <= radius; x++) {
      final value = math.exp(-(x * x + y * y) / denominator);
      result[(y + radius) * size + x + radius] = value;
      total += value;
    }
  }
  return result.map((value) => value / total).toList(growable: false);
}

int _luma(int red, int green, int blue) => _clip(((66 * red + 129 * green + 25 * blue + 128) >> 8) + 16);
int _chromaU(int red, int green, int blue) => _clip(((-38 * red - 74 * green + 112 * blue + 128) >> 8) + 128);
int _chromaV(int red, int green, int blue) => _clip(((112 * red - 94 * green - 18 * blue + 128) >> 8) + 128);
int _clip(int value) => value.clamp(0, 255);
