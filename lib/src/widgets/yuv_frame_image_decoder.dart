import 'dart:typed_data';
import 'dart:ui' as ui;

/// Decodes a tight raw frame for package presentation code.
Future<ui.Image> decodeYuvFrameImage(Uint8List bytes, int width, int height, ui.PixelFormat pixelFormat) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final descriptor = ui.ImageDescriptor.raw(buffer, width: width, height: height, pixelFormat: pixelFormat);
  try {
    final codec = await descriptor.instantiateCodec();
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  } finally {
    descriptor.dispose();
    buffer.dispose();
  }
}
