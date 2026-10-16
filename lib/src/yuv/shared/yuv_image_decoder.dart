import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show Uint8List, visibleForTesting;

/// A callback for replacing the engine decoder in tests.
typedef YuvImageDecodeCallback = Future<ui.Image> Function(Uint8List bytes, int width, int height, ui.PixelFormat pixelFormat);

/// The optional test decoder used instead of the Flutter engine decoder.
@visibleForTesting
YuvImageDecodeCallback? debugYuvImageDecodeOverride;

/// Decodes tightly packed pixels into a Flutter image.
Future<ui.Image> decodeYuvFrameImage(Uint8List bytes, int width, int height, ui.PixelFormat pixelFormat) {
  final override = debugYuvImageDecodeOverride;
  if (override != null) {
    return override(bytes, width, height, pixelFormat);
  }
  return _decodeYuvFrameImage(bytes, width, height, pixelFormat);
}

/// Restores engine decoding after a test installs [debugYuvImageDecodeOverride].
@visibleForTesting
void resetYuvImageDecodeOverride() => debugYuvImageDecodeOverride = null;

Future<ui.Image> _decodeYuvFrameImage(Uint8List bytes, int width, int height, ui.PixelFormat pixelFormat) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  try {
    descriptor = ui.ImageDescriptor.raw(buffer, width: width, height: height, pixelFormat: pixelFormat);
    final codec = await descriptor.instantiateCodec();
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  } finally {
    try {
      descriptor?.dispose();
    } finally {
      buffer.dispose();
    }
  }
}
