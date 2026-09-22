/// The wasm32 byte offsets and sizes of every ABI v1 struct
/// (`src/yuv/abi/h/yuv_abi_v1.h`, `doc/api-abi-0.3-design.md` sections 9 and
/// 10), as the Web runner stages them into WASM linear memory (YUV-51).
///
/// The IO side never needs these: `dart:ffi` derives every offset from the
/// `@Packed`-free generated struct definitions. The Web side has no such
/// mechanism -- it writes raw bytes into `HEAPU8` -- so the layout has to be
/// spelled out, and `test/web/wasm_abi_v1_layout_test.dart` asserts each value
/// against the same tables the C header's static assertions encode.
///
/// Every offset here is identical to the native one, with a single exception:
/// a plane descriptor's `data` member is a pointer, which is 4 bytes on wasm32
/// and 8 on native64. That does not move anything, because `data` is the last
/// member and the struct's 8-byte alignment (it carries `uint64_t` members)
/// pads it back out to 32 bytes either way. This is precisely what the
/// header's `sizeof(((YuvConstPlaneV1 *)0)->data) == sizeof(void *)` assertion
/// allows for, and why the frame descriptor is 160 bytes on both targets.
library;

/// `YuvConstPlaneV1` / `YuvMutablePlaneV1` -- identical layout for both.
abstract final class YuvWasmPlaneV1 {
  /// `uint64 length`.
  static const int offsetLength = 0;

  /// `uint64 rowStride`.
  static const int offsetRowStride = 8;

  /// `uint32 pixelStride`.
  static const int offsetPixelStride = 16;

  /// `uint32 sampleBytes`.
  static const int offsetSampleBytes = 20;

  /// `const uint8 *data` / `uint8 *data` -- 4 bytes on wasm32.
  static const int offsetData = 24;

  /// Total size, padded to the struct's 8-byte alignment on both targets.
  static const int sizeBytes = 32;
}

/// `YuvConstFrameV1` / `YuvMutableFrameV1` -- identical layout for both.
abstract final class YuvWasmFrameV1 {
  /// `uint32 structSize`.
  static const int offsetStructSize = 0;

  /// `uint32 abiVersion`.
  static const int offsetAbiVersion = 4;

  /// `uint32 format`.
  static const int offsetFormat = 8;

  /// `uint32 planeCount`.
  static const int offsetPlaneCount = 12;

  /// `uint32 width`.
  static const int offsetWidth = 16;

  /// `uint32 height`.
  static const int offsetHeight = 20;

  /// `uint32 colorMatrix`.
  static const int offsetColorMatrix = 24;

  /// `uint32 colorRange`.
  static const int offsetColorRange = 28;

  /// `planes[0]`; `planes[n]` starts at `offsetPlanes + n * sizeBytes`.
  static const int offsetPlanes = 32;

  /// `uint64 reserved[4]`.
  static const int offsetReserved = 128;

  /// Total size.
  static const int sizeBytes = 160;

  /// The three plane slots ABI v1 declares, whatever the format's plane count.
  ///
  /// Slots past the format's `planeCount` stay zero-filled with a null `data`,
  /// per section 9 ("Unused planes are zero-filled descriptors with null
  /// data").
  static const int planeSlots = 3;

  /// Byte offset of plane [index]'s descriptor within the frame.
  static int offsetOfPlane(int index) => offsetPlanes + index * YuvWasmPlaneV1.sizeBytes;
}

/// `YuvRegionOptionsV1`, standalone and embedded in the blur/effect options.
abstract final class YuvWasmRegionOptionsV1 {
  /// `uint32 structSize`.
  static const int offsetStructSize = 0;

  /// `uint32 abiVersion`.
  static const int offsetAbiVersion = 4;

  /// `int32 left`.
  static const int offsetLeft = 8;

  /// `int32 top`.
  static const int offsetTop = 12;

  /// `int32 right`.
  static const int offsetRight = 16;

  /// `int32 bottom`.
  static const int offsetBottom = 20;

  /// `uint32 enabled`.
  static const int offsetEnabled = 24;

  /// `uint32 reserved0`.
  static const int offsetReserved0 = 28;

  /// Total size. 4-byte aligned -- it is the one all-32-bit options struct.
  static const int sizeBytes = 32;
}

/// `YuvBlurOptionsV1`.
abstract final class YuvWasmBlurOptionsV1 {
  /// `uint32 structSize`.
  static const int offsetStructSize = 0;

  /// `uint32 abiVersion`.
  static const int offsetAbiVersion = 4;

  /// `uint32 radius`.
  static const int offsetRadius = 8;

  /// `uint32 borderMode`.
  static const int offsetBorderMode = 12;

  /// `double sigma`.
  static const int offsetSigma = 16;

  /// Embedded `YuvRegionOptionsV1 region`.
  static const int offsetRegion = 24;

  /// `uint64 reserved[2]`.
  static const int offsetReserved = 56;

  /// Total size.
  static const int sizeBytes = 72;
}

/// `YuvEffectOptionsV1`.
abstract final class YuvWasmEffectOptionsV1 {
  /// `uint32 structSize`.
  static const int offsetStructSize = 0;

  /// `uint32 abiVersion`.
  static const int offsetAbiVersion = 4;

  /// Embedded `YuvRegionOptionsV1 region`.
  static const int offsetRegion = 8;

  /// `uint64 reserved[2]`.
  static const int offsetReserved = 40;

  /// Total size.
  static const int sizeBytes = 56;
}

/// `YuvConvertOptionsV1` -- header and reserved padding only.
abstract final class YuvWasmConvertOptionsV1 {
  /// `uint32 structSize`.
  static const int offsetStructSize = 0;

  /// `uint32 abiVersion`.
  static const int offsetAbiVersion = 4;

  /// `uint64 reserved[3]`.
  static const int offsetReserved = 8;

  /// Total size.
  static const int sizeBytes = 32;
}

/// `YuvCropOptionsV1`.
abstract final class YuvWasmCropOptionsV1 {
  /// `uint32 structSize`.
  static const int offsetStructSize = 0;

  /// `uint32 abiVersion`.
  static const int offsetAbiVersion = 4;

  /// `int32 left`.
  static const int offsetLeft = 8;

  /// `int32 top`.
  static const int offsetTop = 12;

  /// `uint32 width`.
  static const int offsetWidth = 16;

  /// `uint32 height`.
  static const int offsetHeight = 20;

  /// `uint64 reserved[1]`.
  static const int offsetReserved = 24;

  /// Total size.
  static const int sizeBytes = 32;
}

/// `YuvFlipOptionsV1`.
abstract final class YuvWasmFlipOptionsV1 {
  /// `uint32 structSize`.
  static const int offsetStructSize = 0;

  /// `uint32 abiVersion`.
  static const int offsetAbiVersion = 4;

  /// `uint32 direction`.
  static const int offsetDirection = 8;

  /// `uint32 reserved0`.
  static const int offsetReserved0 = 12;

  /// `uint64 reserved[2]`.
  static const int offsetReserved = 16;

  /// Total size.
  static const int sizeBytes = 32;
}

/// `YuvRotateOptionsV1`.
abstract final class YuvWasmRotateOptionsV1 {
  /// `uint32 structSize`.
  static const int offsetStructSize = 0;

  /// `uint32 abiVersion`.
  static const int offsetAbiVersion = 4;

  /// `uint32 rotationDegrees`.
  static const int offsetRotationDegrees = 8;

  /// `uint32 reserved0`.
  static const int offsetReserved0 = 12;

  /// `uint64 reserved[2]`.
  static const int offsetReserved = 16;

  /// Total size.
  static const int sizeBytes = 32;
}
