import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/reference/test_pattern_reference.dart';

/// Regression coverage for YUV-48: the oracle's chroma/decode math must give
/// the same numeric result on every platform, not merely "VM equals Web"
/// (that equality cannot be asserted from a VM-only test). Every expected
/// value below is derived from the BT.601 formula directly, using an input
/// chosen so the pre-shift sum is negative -- the exact case where a raw `>>`
/// diverges between the Dart VM (true signed shift) and dart2js/DDC (Web
/// numbers reinterpret negative operands as unsigned 32-bit before shifting).
void main() {
  group('YUV-48 platform-independent >> in the reference oracle', () {
    test('rgbaToI420 chroma U/V match the BT.601 formula for a negative pre-shift sum', () {
      // red=0, green=255, blue=0 drives chromaU's pre-shift sum to
      // -38*0 - 74*255 + 112*0 + 128 = -18742 (negative) and chromaV's to
      // 112*0 - 94*255 - 18*0 + 128 = -23842 (negative).
      final rgba = Uint8List.fromList(
        List<int>.generate(4 * 4, (index) {
          switch (index % 4) {
            case 0:
              return 0; // red
            case 1:
              return 255; // green
            case 2:
              return 0; // blue
            default:
              return 255; // alpha
          }
        }),
      );
      final frame = RgbaFrame(2, 2, rgba);
      final i420 = rgbaToI420(frame);

      // floor(-18742 / 256) = -74 (not the truncating -73.2...); + 128 = 54.
      expect(i420.u!.single, 54);
      // floor(-23842 / 256) = -94; + 128 = 34.
      expect(i420.v!.single, 34);
    });

    test('decode() matches the BT.601 formula for a negative pre-shift sum in every channel', () {
      // y=0 -> c=-16, u=128 -> d=0, v=0 -> e=-128.
      // R sum = 298*(-16) + 409*(-128) + 128 = -56992 -> floor(/256) = -223 -> clip(-223) = 0.
      // G sum = 298*(-16) - 100*0 - 208*(-128) + 128 = 21984 -> floor(/256) = 85 -> clip(85) = 85.
      // B sum = 298*(-16) + 516*0 + 128 = -4640 -> floor(/256) = -19 -> clip(-19) = 0.
      final frame = Yuv420Frame.i420(1, 1, Uint8List.fromList(<int>[0]), Uint8List.fromList(<int>[128]), Uint8List.fromList(<int>[0]));
      final decoded = frame.decode();

      expect(decoded.bytes[0], 0); // red
      expect(decoded.bytes[1], 85); // green
      expect(decoded.bytes[2], 0); // blue
      expect(decoded.bytes[3], 255); // alpha
    });
  });
}
