#include <libyuv.h>

#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace {

constexpr int kSourceWidth = 512;
constexpr int kSourceHeight = 512;

struct Image {
  int width;
  int height;
  std::vector<uint8_t> bgra;
};

struct ChannelDiff {
  uint8_t maximum = 0;
  size_t different = 0;
  std::optional<size_t> first;
  uint8_t expected = 0;
  uint8_t actual = 0;
};

struct Result {
  bool passed = true;

  void Add(std::string_view pair, std::string_view channel, const ChannelDiff& diff, int width, size_t total,
           int tolerance) {
    std::cout << std::left << std::setw(24) << pair << " " << std::setw(4) << channel << " max=" << std::setw(3)
              << static_cast<int>(diff.maximum) << " different=" << std::fixed << std::setprecision(4)
              << (100.0 * diff.different / static_cast<double>(total == 0 ? 1 : total)) << "%\n";
    if (diff.maximum <= tolerance) {
      return;
    }
    passed = false;
    const size_t index = *diff.first;
    std::cerr << "FAILED\nCase: " << pair << "\nChannel: " << channel << "\nCoordinate: (" << (index % width)
              << ", " << (index / width) << ")\nExpected: " << static_cast<int>(diff.expected)
              << "\nActual:   " << static_cast<int>(diff.actual) << "\n";
  }
};

[[noreturn]] void Fail(const std::string& message) {
  std::cerr << "FAILED\n" << message << "\n";
  std::exit(2);
}

std::vector<uint8_t> Read(const std::filesystem::path& path) {
  std::ifstream input(path, std::ios::binary);
  if (!input) {
    Fail("Cannot read " + path.string());
  }
  input.seekg(0, std::ios::end);
  const auto length = input.tellg();
  input.seekg(0, std::ios::beg);
  std::vector<uint8_t> bytes(static_cast<size_t>(length));
  input.read(reinterpret_cast<char*>(bytes.data()), length);
  if (!input) {
    Fail("Cannot read complete file " + path.string());
  }
  return bytes;
}

uint16_t U16(const std::vector<uint8_t>& bytes, size_t offset) {
  return static_cast<uint16_t>(bytes[offset]) | (static_cast<uint16_t>(bytes[offset + 1]) << 8);
}

uint32_t U32(const std::vector<uint8_t>& bytes, size_t offset) {
  return static_cast<uint32_t>(bytes[offset]) | (static_cast<uint32_t>(bytes[offset + 1]) << 8) |
         (static_cast<uint32_t>(bytes[offset + 2]) << 16) | (static_cast<uint32_t>(bytes[offset + 3]) << 24);
}

int32_t I32(const std::vector<uint8_t>& bytes, size_t offset) {
  return static_cast<int32_t>(U32(bytes, offset));
}

Image ReadBmp(const std::filesystem::path& path) {
  const auto bytes = Read(path);
  if (bytes.size() < 54 || bytes[0] != 'B' || bytes[1] != 'M') {
    Fail("Expected BMP from sips: " + path.string());
  }
  const uint32_t offset = U32(bytes, 10);
  const uint32_t header_size = U32(bytes, 14);
  const int32_t width = I32(bytes, 18);
  const int32_t signed_height = I32(bytes, 22);
  const uint16_t planes = U16(bytes, 26);
  const uint16_t bits_per_pixel = U16(bytes, 28);
  const uint32_t compression = U32(bytes, 30);
  if (header_size < 40 || width <= 0 || signed_height == 0 || planes != 1 ||
      (bits_per_pixel != 24 && bits_per_pixel != 32) || (compression != 0 && compression != 3)) {
    Fail("Unsupported BMP from sips: " + path.string());
  }
  const int height = std::abs(signed_height);
  const size_t stride = ((static_cast<size_t>(width) * bits_per_pixel + 31) / 32) * 4;
  if (offset + stride * height > bytes.size()) {
    Fail("Truncated BMP from sips: " + path.string());
  }
  Image image{width, height, std::vector<uint8_t>(static_cast<size_t>(width) * height * 4)};
  for (int y = 0; y < height; ++y) {
    const int source_y = signed_height > 0 ? height - 1 - y : y;
    const auto* source = bytes.data() + offset + stride * source_y;
    auto* destination = image.bgra.data() + static_cast<size_t>(y) * width * 4;
    for (int x = 0; x < width; ++x) {
      const int source_offset = x * (bits_per_pixel / 8);
      destination[x * 4] = source[source_offset];
      destination[x * 4 + 1] = source[source_offset + 1];
      destination[x * 4 + 2] = source[source_offset + 2];
      destination[x * 4 + 3] = bits_per_pixel == 32 ? source[source_offset + 3] : 255;
    }
  }
  return image;
}

ChannelDiff Compare(const uint8_t* expected, const uint8_t* actual, size_t count) {
  ChannelDiff result;
  for (size_t index = 0; index < count; ++index) {
    const int difference = std::abs(static_cast<int>(expected[index]) - static_cast<int>(actual[index]));
    result.maximum = std::max(result.maximum, static_cast<uint8_t>(difference));
    if (difference != 0) {
      ++result.different;
      if (!result.first) {
        result.first = index;
        result.expected = expected[index];
        result.actual = actual[index];
      }
    }
  }
  return result;
}

void ComparePlane(Result& result, std::string_view pair, std::string_view channel, const uint8_t* expected,
                  const uint8_t* actual, int width, int height, int tolerance) {
  result.Add(pair, channel, Compare(expected, actual, static_cast<size_t>(width) * height), width,
             static_cast<size_t>(width) * height, tolerance);
}

void CompareImage(Result& result, std::string_view pair, const Image& expected, const std::vector<uint8_t>& actual,
                  int tolerance) {
  if (actual.size() != expected.bgra.size()) {
    Fail(std::string(pair) + " produced an unexpected BGRA byte length");
  }
  constexpr std::string_view channels[] = {"B", "G", "R", "A"};
  for (size_t channel = 0; channel < 4; ++channel) {
    std::vector<uint8_t> expected_channel(static_cast<size_t>(expected.width) * expected.height);
    std::vector<uint8_t> actual_channel(expected_channel.size());
    for (size_t pixel = 0; pixel < expected_channel.size(); ++pixel) {
      expected_channel[pixel] = expected.bgra[pixel * 4 + channel];
      actual_channel[pixel] = actual[pixel * 4 + channel];
    }
    ComparePlane(result, pair, channels[channel], expected_channel.data(), actual_channel.data(), expected.width,
                 expected.height, tolerance);
  }
}

Image Expected(const std::filesystem::path& decoded_root, const std::string& name) {
  return ReadBmp(decoded_root / (name + ".bmp"));
}

std::vector<uint8_t> ToBgra(const uint8_t* y, int y_stride, const uint8_t* u, int u_stride, const uint8_t* v,
                            int v_stride, int width, int height) {
  std::vector<uint8_t> output(static_cast<size_t>(width) * height * 4);
  if (libyuv::I420ToARGBMatrix(y, y_stride, u, u_stride, v, v_stride, output.data(), width * 4,
                                &libyuv::kYuvI601Constants, width, height) != 0) {
    Fail("I420ToARGBMatrix failed");
  }
  return output;
}

std::vector<uint8_t> ToBgraNv21(const uint8_t* y, int y_stride, const uint8_t* vu, int vu_stride, int width,
                                int height) {
  std::vector<uint8_t> output(static_cast<size_t>(width) * height * 4);
  if (libyuv::NV21ToARGBMatrix(y, y_stride, vu, vu_stride, output.data(), width * 4, &libyuv::kYuvI601Constants,
                                width, height) != 0) {
    Fail("NV21ToARGBMatrix failed");
  }
  return output;
}

void CheckGeometry(Result& result, std::string_view pair, const std::vector<uint8_t>& expected,
                   const std::vector<uint8_t>& actual, int width, int height) {
  ComparePlane(result, pair, "Y", expected.data(), actual.data(), width, height, 0);
}

std::vector<uint8_t> RotatePlane(const uint8_t* source, int width, int height, libyuv::RotationMode mode) {
  const int output_width = mode == libyuv::kRotate90 || mode == libyuv::kRotate270 ? height : width;
  const int output_height = mode == libyuv::kRotate90 || mode == libyuv::kRotate270 ? width : height;
  std::vector<uint8_t> output(static_cast<size_t>(output_width) * output_height);
  for (int y = 0; y < output_height; ++y) {
    for (int x = 0; x < output_width; ++x) {
      int source_x = x;
      int source_y = y;
      switch (mode) {
        case libyuv::kRotate90:
          source_x = y;
          source_y = height - 1 - x;
          break;
        case libyuv::kRotate180:
          source_x = width - 1 - x;
          source_y = height - 1 - y;
          break;
        case libyuv::kRotate270:
          source_x = width - 1 - y;
          source_y = x;
          break;
        default:
          break;
      }
      output[static_cast<size_t>(y) * output_width + x] = source[static_cast<size_t>(source_y) * width + source_x];
    }
  }
  return output;
}

void CheckRotatedGeometry(Result& result, std::string_view pair, const uint8_t* source, const std::vector<uint8_t>& actual,
                          int width, int height, libyuv::RotationMode mode) {
  const auto expected = RotatePlane(source, width, height, mode);
  const int output_width = mode == libyuv::kRotate90 || mode == libyuv::kRotate270 ? height : width;
  const int output_height = mode == libyuv::kRotate90 || mode == libyuv::kRotate270 ? width : height;
  ComparePlane(result, pair, "raw", expected.data(), actual.data(), output_width, output_height, 0);
}

void CheckMirroredGeometry(Result& result, std::string_view pair, const uint8_t* source, const std::vector<uint8_t>& actual,
                           int width, int height, bool vertical) {
  std::vector<uint8_t> expected(actual.size());
  for (int y = 0; y < height; ++y) {
    for (int x = 0; x < width; ++x) {
      const int source_x = vertical ? x : width - 1 - x;
      const int source_y = vertical ? height - 1 - y : y;
      expected[static_cast<size_t>(y) * width + x] = source[static_cast<size_t>(source_y) * width + source_x];
    }
  }
  ComparePlane(result, pair, "raw", expected.data(), actual.data(), width, height, 0);
}

void RequireStatus(int status, std::string_view operation) {
  if (status != 0) {
    Fail(std::string(operation) + " failed with status " + std::to_string(status));
  }
}

void CheckRotation(Result& result, const uint8_t* source_y, const uint8_t* source_u, const uint8_t* source_v,
                   const std::filesystem::path& decoded_root, int degrees, libyuv::RotationMode mode) {
  const int width = kSourceWidth;
  const int height = kSourceHeight;
  const int chroma_width = width / 2;
  const int chroma_height = height / 2;
  const int output_width = mode == libyuv::kRotate90 || mode == libyuv::kRotate270 ? height : width;
  const int output_height = mode == libyuv::kRotate90 || mode == libyuv::kRotate270 ? width : height;
  const int output_chroma_width = output_width / 2;
  const int output_chroma_height = output_height / 2;
  std::vector<uint8_t> y(static_cast<size_t>(output_width) * output_height);
  std::vector<uint8_t> u(static_cast<size_t>(output_chroma_width) * output_chroma_height);
  std::vector<uint8_t> v(u.size());
  RequireStatus(libyuv::I420Rotate(source_y, width, source_u, chroma_width, source_v, chroma_width, y.data(), output_width,
                                    u.data(), output_chroma_width, v.data(), output_chroma_width, width, height, mode),
                "I420Rotate");
  const std::string pair = "rotate_" + std::to_string(degrees);
  CheckRotatedGeometry(result, pair + "_Y", source_y, y, width, height, mode);
  CheckRotatedGeometry(result, pair + "_U", source_u, u, chroma_width, chroma_height, mode);
  CheckRotatedGeometry(result, pair + "_V", source_v, v, chroma_width, chroma_height, mode);
  CompareImage(result, pair, Expected(decoded_root, pair + ".png"),
               ToBgra(y.data(), output_width, u.data(), output_chroma_width, v.data(), output_chroma_width, output_width,
                      output_height),
               2);
}

void CheckCrop(Result& result, const uint8_t* source_y, const uint8_t* source_u, const uint8_t* source_v,
               const std::filesystem::path& decoded_root, const std::string& name, int left, int top, int width,
               int height) {
  const int source_chroma_width = kSourceWidth / 2;
  const int crop_chroma_width = (width + 1) / 2;
  const int crop_chroma_height = (height + 1) / 2;
  std::vector<uint8_t> y(static_cast<size_t>(width) * height);
  std::vector<uint8_t> u(static_cast<size_t>(crop_chroma_width) * crop_chroma_height);
  std::vector<uint8_t> v(u.size());
  libyuv::CopyPlane(source_y + top * kSourceWidth + left, kSourceWidth, y.data(), width, width, height);
  libyuv::CopyPlane(source_u + (top / 2) * source_chroma_width + left / 2, source_chroma_width, u.data(),
                    crop_chroma_width, crop_chroma_width, crop_chroma_height);
  libyuv::CopyPlane(source_v + (top / 2) * source_chroma_width + left / 2, source_chroma_width, v.data(),
                    crop_chroma_width, crop_chroma_width, crop_chroma_height);
  std::vector<uint8_t> expected_y(y.size());
  std::vector<uint8_t> expected_u(u.size());
  std::vector<uint8_t> expected_v(v.size());
  for (int row = 0; row < height; ++row) {
    std::copy_n(source_y + (top + row) * kSourceWidth + left, width, expected_y.data() + row * width);
  }
  for (int row = 0; row < crop_chroma_height; ++row) {
    std::copy_n(source_u + (top / 2 + row) * source_chroma_width + left / 2, crop_chroma_width,
                expected_u.data() + row * crop_chroma_width);
    std::copy_n(source_v + (top / 2 + row) * source_chroma_width + left / 2, crop_chroma_width,
                expected_v.data() + row * crop_chroma_width);
  }
  ComparePlane(result, "crop_" + name + "_Y", "raw", expected_y.data(), y.data(), width, height, 0);
  ComparePlane(result, "crop_" + name + "_U", "raw", expected_u.data(), u.data(), crop_chroma_width,
               crop_chroma_height, 0);
  ComparePlane(result, "crop_" + name + "_V", "raw", expected_v.data(), v.data(), crop_chroma_width,
               crop_chroma_height, 0);
  CompareImage(result, "crop_" + name, Expected(decoded_root, "crop_" + name + ".png"),
               ToBgra(y.data(), width, u.data(), crop_chroma_width, v.data(), crop_chroma_width, width, height), 2);
}

}  // namespace

int main(int argc, char** argv) {
  if (argc != 3) {
    std::cerr << "Usage: libyuv_harness <artifact-directory> <decoded-bmp-directory>\n";
    return 64;
  }
  const std::filesystem::path artifacts = argv[1];
  const std::filesystem::path decoded = argv[2];
  const auto bgra = Read(artifacts / "source_bgra8888.bin");
  const auto i420 = Read(artifacts / "source_i420.yuv");
  const auto expected_nv21_uv = Read(artifacts / "source_nv21_uv.yuv");
  const size_t y_size = kSourceWidth * kSourceHeight;
  const size_t chroma_size = y_size / 4;
  if (bgra.size() != y_size * 4 || i420.size() != y_size + 2 * chroma_size || expected_nv21_uv.size() != y_size + 2 * chroma_size) {
    Fail("Fixture dimensions do not match test_pattern_512");
  }
  const auto* source_y = i420.data();
  const auto* source_u = source_y + y_size;
  const auto* source_v = source_u + chroma_size;
  const auto* expected_nv21_y = expected_nv21_uv.data();
  const auto* expected_nv21_chroma = expected_nv21_y + y_size;

  Result result;
  std::cout << "libyuv reference comparison\n";
  std::cout << "Pair                     Chan max different\n";

  std::vector<uint8_t> encoded_y(y_size);
  std::vector<uint8_t> encoded_u(chroma_size);
  std::vector<uint8_t> encoded_v(chroma_size);
  RequireStatus(libyuv::ARGBToI420(bgra.data(), kSourceWidth * 4, encoded_y.data(), kSourceWidth, encoded_u.data(),
                                   kSourceWidth / 2, encoded_v.data(), kSourceWidth / 2, kSourceWidth, kSourceHeight),
                "ARGBToI420");
  ComparePlane(result, "bgra_to_i420", "Y", source_y, encoded_y.data(), kSourceWidth, kSourceHeight, 1);
  ComparePlane(result, "bgra_to_i420", "U", source_u, encoded_u.data(), kSourceWidth / 2, kSourceHeight / 2, 2);
  ComparePlane(result, "bgra_to_i420", "V", source_v, encoded_v.data(), kSourceWidth / 2, kSourceHeight / 2, 2);

  CompareImage(result, "i420_decode", Expected(decoded, "i420_decoded.png"),
               ToBgra(source_y, kSourceWidth, source_u, kSourceWidth / 2, source_v, kSourceWidth / 2, kSourceWidth,
                      kSourceHeight),
               2);

  std::vector<uint8_t> nv21_y(y_size);
  std::vector<uint8_t> nv21_vu(2 * chroma_size);
  RequireStatus(libyuv::I420ToNV21(source_y, kSourceWidth, source_u, kSourceWidth / 2, source_v, kSourceWidth / 2,
                                    nv21_y.data(), kSourceWidth, nv21_vu.data(), kSourceWidth, kSourceWidth,
                                    kSourceHeight),
                "I420ToNV21");
  ComparePlane(result, "i420_to_nv21", "Y", expected_nv21_y, nv21_y.data(), kSourceWidth, kSourceHeight, 0);
  std::vector<uint8_t> expected_u(chroma_size);
  std::vector<uint8_t> expected_v(chroma_size);
  std::vector<uint8_t> actual_u(chroma_size);
  std::vector<uint8_t> actual_v(chroma_size);
  for (size_t index = 0; index < chroma_size; ++index) {
    expected_u[index] = expected_nv21_chroma[index * 2];
    expected_v[index] = expected_nv21_chroma[index * 2 + 1];
    actual_u[index] = nv21_vu[index * 2 + 1];
    actual_v[index] = nv21_vu[index * 2];
  }
  ComparePlane(result, "i420_to_nv21", "U", expected_u.data(), actual_u.data(), kSourceWidth / 2, kSourceHeight / 2, 0);
  ComparePlane(result, "i420_to_nv21", "V", expected_v.data(), actual_v.data(), kSourceWidth / 2, kSourceHeight / 2, 0);
  CompareImage(result, "nv21_decode", Expected(decoded, "nv21_uv_decoded.png"),
               ToBgraNv21(nv21_y.data(), kSourceWidth, nv21_vu.data(), kSourceWidth, kSourceWidth, kSourceHeight), 2);

  CheckRotation(result, source_y, source_u, source_v, decoded, 90, libyuv::kRotate90);
  CheckRotation(result, source_y, source_u, source_v, decoded, 180, libyuv::kRotate180);
  CheckRotation(result, source_y, source_u, source_v, decoded, 270, libyuv::kRotate270);

  std::vector<uint8_t> mirror_y(y_size);
  std::vector<uint8_t> mirror_u(chroma_size);
  std::vector<uint8_t> mirror_v(chroma_size);
  RequireStatus(libyuv::I420Mirror(source_y, kSourceWidth, source_u, kSourceWidth / 2, source_v, kSourceWidth / 2,
                                    mirror_y.data(), kSourceWidth, mirror_u.data(), kSourceWidth / 2, mirror_v.data(),
                                    kSourceWidth / 2, kSourceWidth, kSourceHeight),
                "I420Mirror");
  CheckMirroredGeometry(result, "flip_horizontal_Y", source_y, mirror_y, kSourceWidth, kSourceHeight, false);
  CheckMirroredGeometry(result, "flip_horizontal_U", source_u, mirror_u, kSourceWidth / 2, kSourceHeight / 2, false);
  CheckMirroredGeometry(result, "flip_horizontal_V", source_v, mirror_v, kSourceWidth / 2, kSourceHeight / 2, false);
  CompareImage(result, "flip_horizontal", Expected(decoded, "flip_horizontal.png"),
               ToBgra(mirror_y.data(), kSourceWidth, mirror_u.data(), kSourceWidth / 2, mirror_v.data(), kSourceWidth / 2,
                      kSourceWidth, kSourceHeight),
               2);

  std::vector<uint8_t> vertical_y(y_size);
  std::vector<uint8_t> vertical_u(chroma_size);
  std::vector<uint8_t> vertical_v(chroma_size);
  RequireStatus(libyuv::I420Copy(source_y, kSourceWidth, source_u, kSourceWidth / 2, source_v, kSourceWidth / 2,
                                  vertical_y.data(), kSourceWidth, vertical_u.data(), kSourceWidth / 2, vertical_v.data(),
                                  kSourceWidth / 2, kSourceWidth, -kSourceHeight),
                "I420Copy");
  CheckMirroredGeometry(result, "flip_vertical_Y", source_y, vertical_y, kSourceWidth, kSourceHeight, true);
  CheckMirroredGeometry(result, "flip_vertical_U", source_u, vertical_u, kSourceWidth / 2, kSourceHeight / 2, true);
  CheckMirroredGeometry(result, "flip_vertical_V", source_v, vertical_v, kSourceWidth / 2, kSourceHeight / 2, true);
  CompareImage(result, "flip_vertical", Expected(decoded, "flip_vertical.png"),
               ToBgra(vertical_y.data(), kSourceWidth, vertical_u.data(), kSourceWidth / 2, vertical_v.data(),
                      kSourceWidth / 2, kSourceWidth, kSourceHeight),
               2);

  CheckCrop(result, source_y, source_u, source_v, decoded, "inner", 64, 96, 256, 320);
  CheckCrop(result, source_y, source_u, source_v, decoded, "1x1", 0, 0, 1, 1);
  CheckCrop(result, source_y, source_u, source_v, decoded, "3x5", 0, 0, 3, 5);
  CheckCrop(result, source_y, source_u, source_v, decoded, "127x255", 0, 0, 127, 255);

  if (!result.passed) {
    return 1;
  }
  std::cout << "libyuv reference comparison passed\n";
  return 0;
}
