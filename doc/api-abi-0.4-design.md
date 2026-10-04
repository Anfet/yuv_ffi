# yuv_ffi 0.4.0: public Dart API and native ABI design

Status: implemented 0.4.0 release contract. The native ABI v1 and its IO/Web
transport were developed on the unpublished 0.3.0 Git branch; 0.4.0 is the
next public release after 0.2.4 and includes them alongside the public Dart API
and codec changes below. Owner decisions on live planes, codec v1 removal,
public API and initialization were confirmed on 2026-09-23. The previous
design review was on 2026-09-14.

## 1. Outcome

Version `0.4.0` builds on the unpublished 0.3.0 native ABI work and changes
the public Dart surface with:

- explicit `apply*` in-place operations that return the same object;
- `to*` conversions that always return an independent object;
- live writable planes with explicit `markDirty()` invalidation;
- a truthful `nv12` name while preserving legacy `nv21 == UV` bytes through
  deprecated compatibility entry points;
- explicit backend capabilities and typed failures;
- the format-independent, status-returning native symbols developed for 0.3.0;
- the transactional Dart lifecycle developed for 0.3.0:
  `marshal → invoke → status → commit → dispose`.

Web remains a partial WASM backend. Shared API/state does not imply feature
parity.

## 2. Approved contracts

1. `apply*` mutates in place and returns exactly `this` for chaining.
2. `to*` returns a new independent value and never changes source/revision.
3. Legacy instance methods move to an exported extension and are deprecated.
   Factories/static methods that extensions cannot preserve remain deprecated
   members on their owning declaration.
4. Constructors copy caller buffers. Image getters expose live writable planes;
   callers invoke `markDirty()` after direct writes. `applyPlanes` remains an
   atomic copying replacement path.
5. Canonical semi-planar UV is named NV12. Existing legacy `nv21` entry points
   keep their established UV byte interpretation and are deprecated.
6. Invalid input throws `ArgumentError`; unsupported format/capability throws
   `UnsupportedError`; native overflow/allocation/runtime status becomes
   `YuvNativeException`.
7. Web exposes capabilities and never reports success through a silent no-op.
8. Gaussian, mean, and box blur remain three public operations. Mean and
   normalized box have the same mathematical uniform-average result and may
   share kernels; Gaussian remains weighted. Border handling is
   clamp-to-edge/edge-replicate for all three, approved 2026-09-20: the kernel
   is always the full `(2 * radius + 1)²` samples for every output pixel,
   including at the border. A window cell that falls outside the plane is
   replaced by the nearest in-bounds row/column (the edge sample is
   effectively duplicated) rather than shrinking the averaging window and
   rescaling by the smaller count. The divisor is always the full kernel area.
   Rounding is half up. Alpha is copied, never blurred. This mirrors
   `test/helpers/reference/test_pattern_reference.dart::_convolve`, the
   independent oracle these operations are checked against.
9. Native calls use separate const source and writable destination descriptors,
   versioned options, fixed status values, and format-independent symbols.

## 3. Public library inventory

`lib/yuv_ffi.dart` currently exports the following package declarations. The
table covers declarations owned by this package; inherited Flutter/Object
members are not a package API declaration.

| Current declaration | Current exposure | 0.4.0 decision |
|---|---|---|
| `YuvImage` | Root public interface | Replace its member set using section 4 |
| `YuvImageImpl` | Accidentally exported by conditional export in `yuv.dart` | Hide; implementations remain under `impl/*_io.dart` and `impl/*_web.dart` |
| `YuvPlane` | Root public mutable value | Keep as live image plane or caller-owned plane data; section 5 |
| `YuvFileFormat` | Root public enum | Deprecate in favor of `YuvPixelFormat`; preserve legacy source mapping, without v1 decoding |
| `YuvImageRotation` | Root public enum | Keep, clean up legacy `toZero`; section 6 |
| `YuvImageInvalidation` | Root public extension | Keep `revision` and `markDirty` for direct edits and foreign implementations |
| `YuvImageWidget` | Root public widget | Keep; consume the new `toBgraBytes()` contract |
| `YuvImageProvider` | Root public provider | Keep; revision-based cache contract remains |
| `YuvFfi` | Root public initializer | Add capabilities; section 7 |
| — | `YuvPixelFormat` | New exported storage-format value type with stable IDs; section 6 |
| — | `YuvOperation` | New exported operation enum used by capabilities/errors; section 7 |
| — | `YuvCapabilities` | New exported immutable backend capability value; section 7 |
| — | `YuvNativeException` | New exported catchable native-runtime failure; sections 7 and 11 |

The conditional implementation export must be removed. Factory redirection is
an implementation detail and must not expose `YuvImageImpl` as a constructible
public class.

The leaked `YuvImageImpl` surface consists of unnamed, `i420`, `nv21`, and
`bgra` constructors; every getter/method listed for `YuvImage`; plus
`internalRevision`, `bumpInternalRevision()`, and `toString()`. The first four
become private backend constructors, interface overrides remain reachable only
through `YuvImage`, revision members remain internal, and `toString()` remains
an ordinary implementation override rather than a promised package contract.

`lib/yuv_ffi_web.dart` is a Flutter-generated plugin registrant library rather
than the package's user API. Its public `YuvFfiWebPlugin` declaration and static
`registerWith(Registrar)` entry point remain solely for Flutter Web plugin
registration and are excluded from `lib/yuv_ffi.dart`; application code uses
`YuvFfi.initialize()` instead.

## 4. `YuvImage` member migration

| Published 0.2.4 member | 0.4.0 member | Mutation/allocation | Failure/backend |
|---|---|---|---|
| `format` | `format: YuvPixelFormat` | Read-only | Always available |
| `width` | `width` | Read-only | Always available |
| `height` | `height` | Read-only | Always available |
| `size` | `size` | New `Size` value | Always available |
| `planes` | `planes` | Unmodifiable list of live `YuvPlane` references | Always available |
| `yPlane` | `yPlane` | Live plane | `StateError` only for corrupt internal state |
| `uPlane` | `uPlane` | Live plane | `StateError` when format has no U plane |
| `vPlane` | `vPlane` | Live plane | `StateError` when format has no V plane |
| `y` | deprecated extension `y` | Live plane | Same as `yPlane` |
| `u` | deprecated extension `u` | Live nullable plane | Direct writes require `markDirty()` |
| `v` | deprecated extension `v` | Live nullable plane | Direct writes require `markDirty()` |
| `YuvImage.i420(...)` | same named factory | New owned image; copies provided planes | `ArgumentError` geometry/layout |
| `YuvImage.nv21(...)` | deprecated factory forwarding to canonical NV12 storage | New owned image; legacy UV interpretation unchanged | `ArgumentError` geometry/layout |
| — | `YuvImage.nv12(...)` | New owned image | `ArgumentError` geometry/layout |
| `YuvImage.bgra(...)` | `YuvImage.bgra(...)` | New owned image | `ArgumentError` geometry/layout |
| `YuvImage(format, ...)` | deprecated unnamed factory plus `YuvImage.allocate(format, width, height)` | Legacy factory preserves explicit strides/planes; allocate creates tight zeroed storage | `ArgumentError`/`UnsupportedError` |
| `getBytes()` | `toBytes()` | New concatenated plane copy | Never exposes backing storage |
| `copy(blank: false)` | `copy()` with deprecated `blank` parameter retained | New deep copy | Always available |
| `copy(blank: true)` | `YuvImage.allocate(...)` | Compatibility path returns zeroed same-layout image; parameter use warns | Always available |
| — | `applyPlanes(Iterable<YuvPlane>)` | Validates, copies, atomically replaces, returns `this` | `ArgumentError`; no change on failure |
| `save(sink)` | `encodeTo(sink)` | Does not mutate | Sink errors preserved |
| `load(stream)` | `YuvImage.decode(stream)` | New image; no receiver mutation | `FormatException`/stream error |
| `blackwhite()` | `applyBlackWhite()` | In-place, returns `this` | Capability/status mapping |
| `gaussianBlur(...)` | `applyGaussianBlur(radius:, sigma:)` | In-place, returns `this` | Argument/capability/status mapping |
| `boxBlur(...)` | `applyBoxBlur(radius:, region:)` | In-place, returns `this` | Argument/capability/status mapping |
| `meanBlur(...)` | `applyMeanBlur(radius:, region:)` | In-place, returns `this` | Argument/capability/status mapping |
| `grayscale()` | `applyGrayscale()` | In-place, returns `this` | Capability/status mapping |
| `negate()` | `applyNegate()` | In-place, returns `this` | Capability/status mapping |
| `crop(rect)` | `applyCrop(region)` | In-place geometry/data replacement, returns `this` | Empty effective ROI is no-op |
| — | `cropped(region)` | New image; source unchanged | Same normalized ROI contract |
| `flipHorizontally()` | `applyFlipHorizontal()` | In-place, returns `this` | Capability/status mapping |
| `flipVertically()` | `applyFlipVertical()` | In-place, returns `this` | Capability/status mapping |
| `rotate(rotation)` | `applyRotation(rotation)` | In-place, returns `this` | Rotation 0 is no-op |
| — | `rotated(rotation)` | New image; source unchanged | Same rotation contract |
| `fromRgba8888(bytes)` | `applyRgbaBytes(bytes)` | Replaces pixels in current format, returns `this` | Exact-length `ArgumentError` |
| — | `YuvImage.fromRgbaBytes(bytes, width:, height:, format:)` | New image | Argument/capability/status mapping |
| `toYuvI420()` | `applyFormat(YuvPixelFormat.i420)` | Deprecated old method retains mutation | Status mapping |
| `toYuvBgra8888()` | `applyFormat(YuvPixelFormat.bgra8888)` | Deprecated old method retains mutation | Status mapping |
| `toYuvNv21()` | `applyFormat(YuvPixelFormat.nv12)` | Deprecated old method retains legacy UV bytes | Status mapping |
| — | `toI420()` | New independent image | Status mapping |
| — | `toNv12()` | New independent image | Status mapping |
| — | `toBgra()` | New independent image | Status mapping |
| `toBgra8888()` | `toBgraBytes()` | New tight byte copy | Status mapping |
| `toImage()` | `toImage()` | New Flutter image; source unchanged | Decode/backend error |
| `swapNv()` | deprecated extension → `applyChromaSwap()` | In-place channel-value effect | Keeps canonical NV12 label and historical output bytes |

The following is the exhaustive `0.4.0` `YuvImage` member inventory. Factory
bodies/redirects are omitted from the sketch; implementation classes remain
private to their platform libraries.

```dart
abstract interface class YuvImage {
  YuvPixelFormat get format;
  int get width;
  int get height;
  ui.Size get size;
  List<YuvPlane> get planes;
  YuvPlane get yPlane;
  YuvPlane get uPlane;
  YuvPlane get vPlane;

  factory YuvImage.i420(int width, int height, {
    int yPixelStride = 1,
    int uvPixelStride = 1,
    Iterable<YuvPlane>? planes,
  });
  factory YuvImage.nv12(int width, int height, {
    int yPixelStride = 1,
    int uvPixelStride = 2,
    Iterable<YuvPlane>? planes,
  });
  factory YuvImage.bgra(int width, int height, {
    Iterable<YuvPlane>? planes,
  });
  factory YuvImage.allocate(YuvPixelFormat format, int width, int height);
  factory YuvImage.fromRgbaBytes(
    Uint8List bytes, {
    required int width,
    required int height,
    required YuvPixelFormat format,
  });
  static Future<YuvImage> decode(Stream<List<int>> stream);

  @Deprecated('Legacy nv21 label contains UV bytes; use YuvImage.nv12().')
  factory YuvImage.nv21(int width, int height, {
    int yPixelStride = 1,
    int uvPixelStride = 2,
    Iterable<YuvPlane>? planes,
  });
  @Deprecated('Use a named factory or YuvImage.allocate().')
  factory YuvImage(
    YuvFileFormat format,
    int width,
    int height, {
    int yPixelStride = 1,
    int uvPixelStride = 1,
    Iterable<YuvPlane>? planes,
  });

  YuvImage copy({
    @Deprecated('Use YuvImage.allocate() for a blank image.')
    bool blank = false,
  });
  YuvImage applyPlanes(Iterable<YuvPlane> planes);
  YuvImage applyRgbaBytes(Uint8List bytes);
  YuvImage applyGrayscale();
  YuvImage applyBlackWhite();
  YuvImage applyNegate();
  YuvImage applyGaussianBlur({required int radius, required double sigma});
  YuvImage applyMeanBlur({required int radius, ui.Rect? region});
  YuvImage applyBoxBlur({required int radius, ui.Rect? region});
  YuvImage applyCrop(ui.Rect region);
  YuvImage applyFlipHorizontal();
  YuvImage applyFlipVertical();
  YuvImage applyRotation(YuvImageRotation rotation);
  YuvImage applyFormat(YuvPixelFormat format);
  YuvImage applyChromaSwap();

  YuvImage cropped(ui.Rect region);
  YuvImage rotated(YuvImageRotation rotation);
  YuvImage toI420();
  YuvImage toNv12();
  YuvImage toBgra();
  Uint8List toBytes();
  Uint8List toBgraBytes();
  Future<void> encodeTo(Sink<List<int>> sink);
  Future<ui.Image> toImage();
}
```

Every successful `apply*` that changes state increments revision exactly once.
A no-op and every failure leave bytes, metadata, and revision unchanged.
Defined no-ops are radius `0`, empty normalized ROI/crop, rotation `0`, and
same-format `applyFormat`; they short-circuit before dispatch. Other successful
mutators increment once even when their computed visible bytes happen to equal
the input; implementations do not perform a full-frame equality scan.
New-result counterparts never alias even for a semantic no-op: `cropped()` with
an empty effective region, `rotated(rotation0)`, and same-format `to*` return an
independent deep copy while leaving the source revision unchanged.
`applyPlanes` preserves format/dimensions and atomically replaces only valid
plane data. It copies supplied buffers and invalidates previously obtained
live plane references; callers reacquire planes after a replacement operation.
Direct writes through current live planes require one `markDirty()` after the
write batch so revision-keyed render caches can see the change. `applyRgbaBytes`
requires exactly `width * height * 4` tight
RGBA bytes. `applyChromaSwap` accepts only NV12; I420 and BGRA throw
`UnsupportedError` without conversion or mutation. The deprecated `swapNv()`
retains its separately specified convert-then-swap behavior in section 14.
`toBytes()` concatenates each plane's full `height * rowStride` storage in
format order, including declared row/pixel padding but adding no alignment gaps
or trailing bytes. `toBgraBytes()` instead returns exactly
`width * height * 4` tightly packed visible BGRA pixels.

The canonical I420 allocation default changes from the historical
`uvPixelStride = 2` to planar `uvPixelStride = 1`; callers that explicitly need
gapped planar samples may still pass a larger positive stride. NV12 keeps
`uvPixelStride = 2`. This is an intentional `0.4.0` breaking default correction,
not a reinterpretation of supplied plane bytes.

## 5. `YuvPlane` migration

| Current member | 0.4.0 contract |
|---|---|
| constructor | Keep; requires non-negative height/rowStride, positive pixelStride, checked `height * rowStride`, exact input length, and copies input; `rowStride == 0` is allowed only when `height == 0` |
| `bytes` | Writable buffer; a plane obtained from an image aliases that image's storage, so direct writes require `image.markDirty()` |
| `height` | Keep |
| `rowStride` | Keep |
| `bytesPerRow` | Keep as alias |
| `pixelStride` | Keep |
| `bytesPerPixel` | Keep as alias |
| `bytesPerPixes` | Deprecated extension alias, then removal after migration window |
| `getPixel(x,y)` | Keep; require `0 <= y < height`, `x >= 0`, and `x * pixelStride < rowStride` with checked index arithmetic |
| `setPixel(x,y,value)` | Same unconditional coordinate/value checks; on a live image plane, the caller invokes `image.markDirty()` after the edit batch |
| `assignFrom(bytes)` | Keep for live/caller-owned plane values with exact length; live edits require `markDirty()` |
| `copy()` | Keep deep copy |
| `toString()` | Keep diagnostic, do not print bytes |

`YuvImage.planes/yPlane/uPlane/vPlane` expose live values. Their buffers are
stable only until an operation replaces the plane set; callers must reacquire
the handles after `applyPlanes`, crop, rotation or format conversion. The
`planes` list cannot be structurally modified. Direct writes never update the
revision automatically; call `markDirty()` once after each batch. `applyPlanes`
provides an atomic copied replacement when that behavior is needed.
`setPixel` accepts only `0..255`. Constructor, coordinate, length, arithmetic,
and value violations throw `ArgumentError` rather than relying on debug asserts
or incidental `RangeError`.

## 6. Enum and serialization migration

Introduce the exported storage enum below. Serialization uses `wireId`, never
the Dart enum index:

```dart
enum YuvPixelFormat {
  i420(1),
  nv12(2),
  bgra8888(3);

  const YuvPixelFormat(this.wireId);
  final int wireId;
}
```

RGBA8888 is native ABI input format ID `4`, not a storable `YuvImage` format and
therefore not a `YuvPixelFormat` value. `YuvFileFormat` remains exported but is
deprecated; its values remain `nv21`, `i420`, and `bgra8888` for source
compatibility only.

### Codec v1 breaking change

The v1 payload body used by 0.2.4 and the unpublished 0.3.0 baseline contains:

1. `uint32 little-endian headerLength`;
2. `headerLength` UTF-8 bytes containing a JSON object with integer `version: 1`,
   string `format`, integer `width`, and integer `height`;
3. `uint8 planeCount`;
4. for each plane in format order: `uint32 LE height`, `uint32 LE rowStride`,
   `uint32 LE pixelStride`, `uint32 LE byteLength`, then exactly `byteLength`
   bytes;
5. the unpublished 0.3.0 reader required immediate EOF; the published 0.2.4
   writer may append zero padding, which its reader ignored.

This layout documents v1 data written by published 0.2.4 and the unpublished
0.3.0 Git baseline. The 0.4.0 decoder rejects `version: 1` with
`FormatException`; there is no v1 writer or automatic migration. Applications
retaining serialized 0.2.4 frames need a two-app-version
transfer: before the upgrade, the 0.2.4 app reads each v1 frame and persists
its format, dimensions, plane row/pixel strides, and bytes in an
application-owned intermediate representation. After the upgrade, the 0.4.0
app recreates the image from that representation and writes v2. Re-saving with
0.2.4 would still produce v1, potentially with trailing zero padding; raw v1
bytes are not the intermediate representation. Legacy `nv21` UV samples remain
unchanged when restored by the application.

### Codec v2 writer and reader

Version `0.4.0` writes only v2 and reads only v2. V2 deliberately keeps
the proven outer framing and plane body; only the header's format identity is
made stable:

1. `uint32 little-endian headerLength`;
2. UTF-8 JSON object with required integer fields `version: 2`, `formatId`,
   `width`, and `height`; `formatId` is exactly `1`, `2`, or `3` from
   `YuvPixelFormat.wireId`;
3. the same `uint8 planeCount` and per-plane body/order as v1;
4. immediate EOF.

Required v2 fields must have the exact JSON scalar types above and positive
dimensions. Unknown header keys are ignored for forward-compatible metadata;
unknown `formatId` and unsupported `version` throw `FormatException`. Existing
header/plane size limits and checked geometry validation apply before buffering
plane data. Adding or reordering Dart enum values cannot change the v2 wire
format.

`YuvImageRotation.rotation0/90/180/270`, `degrees`, `swapSize`, `clockwise`, and
`counterClockwise` remain. The identity-like `toZero()` becomes deprecated and
is removed from the core interface because it adds no normalized value.

## 7. Initialization, capabilities, widgets, and revision

Target initializer:

```dart
final capabilities = await YuvFfi.initialize();
if (capabilities.supports(YuvOperation.gaussianBlur,
    sourceFormat: YuvPixelFormat.nv12)) {
  image.applyGaussianBlur(radius: 2, sigma: 1.0);
}
```

- Add exported immutable `YuvCapabilities` and the exhaustive operation enum:

  ```dart
  enum YuvOperation {
    convert,
    blackWhite,
    grayscale,
    negate,
    gaussianBlur,
    meanBlur,
    boxBlur,
    crop,
    flipHorizontal,
    flipVertical,
    rotate,
    chromaSwap,
  }

  abstract interface class YuvCapabilities {
    bool supports(
      YuvOperation operation, {
      required YuvPixelFormat sourceFormat,
      YuvPixelFormat? destinationFormat,
    });
  }
  ```

  `destinationFormat` is required for `convert` and must be omitted for all
  other operations. Capability objects are immutable snapshots; unsupported or
  malformed capability queries return `false` and do not initialize/execute an
  operation.
- Add exported `YuvNativeException implements Exception` with immutable
  `int statusCode`, `YuvOperation operation`, and `String message`. It is used
  only for overflow, allocation, internal/unknown native failures; it retains
  the numeric status for diagnostics and has a non-empty `toString()`.
- `YuvFfi.initialize()` returns capabilities and shares/retries initialization
  with the existing contract.
- Keep deprecated `YuvFfi.ensureInitialized()` forwarding to `initialize()`.
- A capability says whether dispatch exists, not whether arbitrary input is
  valid. Invalid geometry still throws `ArgumentError`.
- Native IO initialization requires the complete ABI-v1 symbol manifest for the
  operations built into that library; a missing required symbol fails
  initialization. Web remains partial: its immutable capability snapshot marks
  an operation true only when the matching WASM export is present and the
  loader initialized successfully. The mapping is exact:

  | Public operation(s) | Required processing export |
  |---|---|
  | `to*`, `applyFormat`, RGBA import | `yuv_convert_v1` |
  | black-white | `yuv_black_white_v1` |
  | grayscale | `yuv_grayscale_v1` |
  | negate | `yuv_negate_v1` |
  | Gaussian / mean / box | corresponding `yuv_*_blur_v1` export |
  | crop | `yuv_crop_v1` |
  | horizontal / vertical flip | `yuv_flip_v1` |
  | rotate | `yuv_rotate_v1` |
  | chroma swap | `yuv_chroma_swap_v1` |

  No Web operation is promised merely because it exists on IO. Calling one
  whose exact format/pair capability is false throws `UnsupportedError` before
  allocation, native invocation, or revision change.
- `YuvImageInvalidation.revision` remains.
- `markDirty()` remains required after direct edits to live planes of
  package-owned images and remains available for foreign implementations.
- `YuvImageWidget` retains constructor fields `image`, `boxFit`,
  `loadingBuilder`, `errorBuilder`, and `frameBuilder`, plus its public
  `build(BuildContext)` override inherited from `StatelessWidget`.
- `YuvImageProvider` retains `image`, constructor, key equality/hash, and image
  loading overrides: `obtainKey(ImageConfiguration)`, `operator ==`, `hashCode`,
  and `loadImage(YuvImageProvider, ImageDecoderCallback)`; it consumes
  `toBgraBytes()`.
- The exported `YuvImageInvalidation` extension retains exactly `revision` and
  `markDirty()`. Internal `YuvRevisionAware`/`YuvRevision` stay unexported.

## 8. Deprecated compatibility extension

```dart
extension DeprecatedYuvImageApi on YuvImage {
  @Deprecated('Use applyGrayscale().')
  YuvImage grayscale() => applyGrayscale();

  @Deprecated('Use applyGaussianBlur().')
  YuvImage gaussianBlur({int radius = 2, int sigma = 2}) =>
      applyGaussianBlur(radius: radius, sigma: sigma.toDouble());

  @Deprecated('Legacy mutating API; use toNv12() or applyFormat().')
  YuvImage toYuvNv21() => applyFormat(YuvPixelFormat.nv12);
}
```

The final extension contains every renamed legacy getter/instance operation in
section 4 (`getBytes`, `save`, `load`, effects, transforms, conversions,
`fromRgba8888`, and `swapNv`). Unchanged target members such as `toImage` remain
on the interface. Old renamed members must be removed from the concrete
class/interface because an instance member would shadow the extension.

The `copy(blank:)` name collides with target `copy()`, so it remains one core
method with only the `blank` parameter deprecated; `blank: true` preserves the
old same-layout zeroed-copy behavior. Named/unnamed factories and `YuvFfi`
static methods cannot be reproduced as extension calls and therefore remain
deprecated forwarding members on their owning declaration. The mutating legacy
`load()` extension may use a package-private atomic state-replacement adapter;
for a foreign `implements YuvImage` that cannot provide that adapter it throws
`UnsupportedError` without changing the receiver. New code uses
`YuvImage.decode()` and receives a new image.

## 9. Native ABI types

All public integer constants have explicit values. Do not expose a compiler-
sized C enum, `long`, `size_t`, or `bool` as a cross-backend field.

```c
typedef int32_t YuvStatus;

#define YUV_STATUS_OK                 ((YuvStatus)0)
#define YUV_STATUS_INVALID_ARGUMENT   ((YuvStatus)1)
#define YUV_STATUS_UNSUPPORTED_FORMAT ((YuvStatus)2)
#define YUV_STATUS_UNSUPPORTED_LAYOUT ((YuvStatus)3)
#define YUV_STATUS_OVERFLOW           ((YuvStatus)4)
#define YUV_STATUS_ALLOCATION_FAILED  ((YuvStatus)5)
#define YUV_STATUS_INTERNAL_ERROR     ((YuvStatus)6)
#define YUV_STATUS_UNSUPPORTED_COLOR  ((YuvStatus)7)

#define YUV_FORMAT_I420     ((uint32_t)1)
#define YUV_FORMAT_NV12     ((uint32_t)2)
#define YUV_FORMAT_BGRA8888 ((uint32_t)3)
#define YUV_FORMAT_RGBA8888 ((uint32_t)4)

#define YUV_COLOR_MATRIX_NONE  ((uint32_t)0)
#define YUV_COLOR_MATRIX_BT601 ((uint32_t)1)
#define YUV_COLOR_RANGE_NONE   ((uint32_t)0)
#define YUV_COLOR_RANGE_LIMITED ((uint32_t)1)

#define YUV_BORDER_CLAMP ((uint32_t)1)
#define YUV_FLIP_HORIZONTAL ((uint32_t)1)
#define YUV_FLIP_VERTICAL   ((uint32_t)2)

typedef struct {
  uint64_t length;
  uint64_t rowStride;
  uint32_t pixelStride;
  uint32_t sampleBytes;
  const uint8_t *data;
} YuvConstPlaneV1;

typedef struct {
  uint64_t length;
  uint64_t rowStride;
  uint32_t pixelStride;
  uint32_t sampleBytes;
  uint8_t *data;
} YuvMutablePlaneV1;

typedef struct {
  uint32_t structSize;
  uint32_t abiVersion;
  uint32_t format;
  uint32_t planeCount;
  uint32_t width;
  uint32_t height;
  uint32_t colorMatrix;
  uint32_t colorRange;
  YuvConstPlaneV1 planes[3];
  uint64_t reserved[4];
} YuvConstFrameV1;

typedef struct {
  uint32_t structSize;
  uint32_t abiVersion;
  uint32_t format;
  uint32_t planeCount;
  uint32_t width;
  uint32_t height;
  uint32_t colorMatrix;
  uint32_t colorRange;
  YuvMutablePlaneV1 planes[3];
  uint64_t reserved[4];
} YuvMutableFrameV1;
```

Rules:

- ABI version is `1`; every options/frame struct starts with `structSize` and
  `abiVersion`.
- Null descriptor/options pointers, ABI versions other than `1`, `structSize`
  smaller than the full v1 type, non-zero known reserved fields, and unknown
  numeric format/matrix/range values return `YUV_STATUS_INVALID_ARGUMENT`
  before plane access. A larger `structSize` is accepted and its unknown tail is
  ignored; this is the forward-compatible extension rule.
- I420/NV12 frames require matrix `BT601` and range `LIMITED`. BGRA/RGBA frames
  require matrix/range `NONE`. These are the only color-space combinations in
  ABI v1; a known format with another declared color space returns
  `YUV_STATUS_UNSUPPORTED_COLOR`. The `0.4.0` reference oracle is BT.601
  limited-range.
- Width/height are in `1..INT32_MAX`; all derived dimensions, strides, spans,
  allocation sizes, and coordinate arithmetic must additionally fit their
  declared `uint32_t`/`uint64_t` fields and the target address space.
- Plane count, sample bytes, strides, and minimum spans are format-validated
  with checked arithmetic against `length`.
- Unused planes are zero-filled descriptors with null data.
- Source and destination active spans must not overlap in ABI v1.
- Native/WASM builds publish `sizeof`/`offsetof` assertions or generated layout
  tests for their pointer width; Web must not guess native-64 offsets.

The v1 layout is deliberately identical on supported native32, native64, and
wasm32 ABIs that align `uint64_t` to 8 bytes. This is a required build assertion,
not an assumption:

| Type/member | Offset | Size |
|---|---:|---:|
| plane `length` | 0 | 8 |
| plane `rowStride` | 8 | 8 |
| plane `pixelStride` | 16 | 4 |
| plane `sampleBytes` | 20 | 4 |
| `YuvConstPlaneV1.data` / mutable `data` | 24 | pointer width (4 or 8) |
| complete plane descriptor | — | 32 |
| frame scalar prefix (`structSize` through `colorRange`) | 0 | 32 |
| frame `planes[0]` / `[1]` / `[2]` | 32 / 64 / 96 | 32 each |
| frame `reserved` | 128 | 32 |
| complete frame descriptor | — | 160 |

Compilation fails on a target whose `sizeof`/`offsetof` differs. Every pointer
is passed as the target pointer-width value; no pointer is serialized into the
codec or truncated through a Dart/JS `int32` view.

## 10. Options ABI

Each options struct is a distinct fixed-width type. Positional scalar tails are
not permitted.

```c
typedef struct {
  uint32_t structSize;
  uint32_t abiVersion;
  int32_t left;
  int32_t top;
  int32_t right;
  int32_t bottom;
  uint32_t enabled;
  uint32_t reserved0;
} YuvRegionOptionsV1;

typedef struct {
  uint32_t structSize;
  uint32_t abiVersion;
  uint32_t radius;
  uint32_t borderMode;
  double sigma;
  YuvRegionOptionsV1 region;
  uint64_t reserved[2];
} YuvBlurOptionsV1;

typedef struct {
  uint32_t structSize;
  uint32_t abiVersion;
  YuvRegionOptionsV1 region;
  uint64_t reserved[2];
} YuvEffectOptionsV1;

typedef struct {
  uint32_t structSize;
  uint32_t abiVersion;
  uint64_t reserved[3];
} YuvConvertOptionsV1;

typedef struct {
  uint32_t structSize;
  uint32_t abiVersion;
  int32_t left;
  int32_t top;
  uint32_t width;
  uint32_t height;
  uint64_t reserved[1];
} YuvCropOptionsV1;

typedef struct {
  uint32_t structSize;
  uint32_t abiVersion;
  uint32_t direction;
  uint32_t reserved0;
  uint64_t reserved[2];
} YuvFlipOptionsV1;

typedef struct {
  uint32_t structSize;
  uint32_t abiVersion;
  uint32_t rotationDegrees;
  uint32_t reserved0;
  uint64_t reserved[2];
} YuvRotateOptionsV1;
```

`YuvRegionOptionsV1` has 4-byte alignment; the option structs containing
`double`/`uint64_t` have 8-byte alignment. Their exact layout is below.
`sizeof`, alignment, and `offsetof` compile assertions are required beside the
frame assertions.

| Type | Exact member offsets | Size |
|---|---|---:|
| region | `structSize 0`, `abiVersion 4`, `left 8`, `top 12`, `right 16`, `bottom 20`, `enabled 24`, `reserved0 28` | 32 |
| blur | `structSize 0`, `abiVersion 4`, `radius 8`, `borderMode 12`, `sigma 16`, `region 24`, `reserved 56` | 72 |
| effect | `structSize 0`, `abiVersion 4`, `region 8`, `reserved 40` | 56 |
| convert | `structSize 0`, `abiVersion 4`, `reserved 8` | 32 |
| crop | `structSize 0`, `abiVersion 4`, `left 8`, `top 12`, `width 16`, `height 20`, `reserved 24` | 32 |
| flip | `structSize 0`, `abiVersion 4`, `direction 8`, `reserved0 12`, `reserved 16` | 32 |
| rotate | `structSize 0`, `abiVersion 4`, `rotationDegrees 8`, `reserved0 12`, `reserved 16` | 32 |

`YuvRegionOptionsV1` uses right/bottom-exclusive coordinates. `enabled` is only
`0` or `1`; when `0`, all four coordinates and `reserved0` must be zero. Dart
normalizes a public `Rect` as `floor(left/top)`, `ceil(right/bottom)`, clamps it
to the visible frame, and uses `enabled = 1`. Empty normalized effect regions
and empty crops are handled as Dart no-ops before native dispatch. C validates
the normalized signed rectangle defensively.

`radius == 0` is a no-op; valid non-zero radius is `1..256`. Gaussian `sigma`
must be finite and positive. Mean/box require `sigma == 0.0`. Border mode is
exactly `YUV_BORDER_CLAMP`; unknown values return invalid argument. Crop options
contain the already normalized visible rectangle. Flip direction is exactly
horizontal or vertical. Rotation is exactly `0`, `90`, `180`, or `270` degrees
clockwise. Convert options carry no duplicated format/color fields: source and
destination descriptors are authoritative, avoiding mismatch states.
`yuv_chroma_swap_v1` requires its effect region to be disabled; regional chroma
swap is not a public `0.4.0` operation.

## 11. Target exported native/WASM symbols

All operations use the order `(source, destination, options)` and return
`YuvStatus`:

| Target symbol | Options | Purpose |
|---|---|---|
| `yuv_convert_v1` | `YuvConvertOptionsV1` | RGBA/BGRA/I420/NV12 conversion matrix |
| `yuv_black_white_v1` | `YuvEffectOptionsV1` | Threshold effect |
| `yuv_grayscale_v1` | `YuvEffectOptionsV1` | Grayscale effect |
| `yuv_negate_v1` | `YuvEffectOptionsV1` | Visible RGB negate |
| `yuv_gaussian_blur_v1` | `YuvBlurOptionsV1` | Weighted Gaussian blur |
| `yuv_mean_blur_v1` | `YuvBlurOptionsV1` | Uniform mean blur |
| `yuv_box_blur_v1` | `YuvBlurOptionsV1` | Normalized box blur |
| `yuv_crop_v1` | `YuvCropOptionsV1` | Crop to destination geometry |
| `yuv_flip_v1` | `YuvFlipOptionsV1` | Horizontal/vertical flip |
| `yuv_rotate_v1` | `YuvRotateOptionsV1` | 0/90/180/270 rotation |
| `yuv_chroma_swap_v1` | `YuvEffectOptionsV1` | Swap U/V sample values without changing NV12 format |

The table expands to these exact declarations; no variadic, nullable-options,
or format-specific processing overloads are part of ABI v1:

```c
FFI_PLUGIN_EXPORT YuvStatus yuv_convert_v1(const YuvConstFrameV1 *, YuvMutableFrameV1 *, const YuvConvertOptionsV1 *);
FFI_PLUGIN_EXPORT YuvStatus yuv_black_white_v1(const YuvConstFrameV1 *, YuvMutableFrameV1 *, const YuvEffectOptionsV1 *);
FFI_PLUGIN_EXPORT YuvStatus yuv_grayscale_v1(const YuvConstFrameV1 *, YuvMutableFrameV1 *, const YuvEffectOptionsV1 *);
FFI_PLUGIN_EXPORT YuvStatus yuv_negate_v1(const YuvConstFrameV1 *, YuvMutableFrameV1 *, const YuvEffectOptionsV1 *);
FFI_PLUGIN_EXPORT YuvStatus yuv_gaussian_blur_v1(const YuvConstFrameV1 *, YuvMutableFrameV1 *, const YuvBlurOptionsV1 *);
FFI_PLUGIN_EXPORT YuvStatus yuv_mean_blur_v1(const YuvConstFrameV1 *, YuvMutableFrameV1 *, const YuvBlurOptionsV1 *);
FFI_PLUGIN_EXPORT YuvStatus yuv_box_blur_v1(const YuvConstFrameV1 *, YuvMutableFrameV1 *, const YuvBlurOptionsV1 *);
FFI_PLUGIN_EXPORT YuvStatus yuv_crop_v1(const YuvConstFrameV1 *, YuvMutableFrameV1 *, const YuvCropOptionsV1 *);
FFI_PLUGIN_EXPORT YuvStatus yuv_flip_v1(const YuvConstFrameV1 *, YuvMutableFrameV1 *, const YuvFlipOptionsV1 *);
FFI_PLUGIN_EXPORT YuvStatus yuv_rotate_v1(const YuvConstFrameV1 *, YuvMutableFrameV1 *, const YuvRotateOptionsV1 *);
FFI_PLUGIN_EXPORT YuvStatus yuv_chroma_swap_v1(const YuvConstFrameV1 *, YuvMutableFrameV1 *, const YuvEffectOptionsV1 *);
```

WASM exports exactly the same processing names plus allocator/runtime exports
required by its loader. The Dart Web backend calls them with return type
`number`, checks status, and never copies back on failure.

### Format, layout, and geometry matrix

Every function requires non-null source, destination, and options pointers.
Format/color metadata comes from the frame descriptors; options never override
it.

Effects and blur have one storage-independent visible-pixel oracle. Decode the
source logical samples as BT.601 limited-range RGB, transform RGB, preserve
alpha, then encode the complete result once into the original storage format:

- grayscale uses
  `gray = floor((299*R + 587*G + 114*B + 500) / 1000)` and writes
  `(gray, gray, gray)`;
- black-white uses that same rounded `gray`, selects white when `gray >= 128`
  and black otherwise;
- negate writes `(255-R, 255-G, 255-B)`;
- Gaussian uses the normalized two-dimensional kernel
  `exp(-(dx²+dy²)/(2*sigma²))` over `[-radius,+radius]`;
- mean and box both use uniform weight `1/(2*radius+1)²` and therefore must
  produce the same logical result for the same radius/ROI.

All three blurs clamp sample coordinates to the nearest visible edge, accumulate
from an immutable source snapshot, and round each positive RGB channel sum with
`floor(value + 0.5)` before clamping to `0..255`. ROI controls destination pixels
that are replaced; samples outside ROI remain exact source values, while kernel
reads may cross the ROI boundary. For YUV output, chroma is re-encoded by the
same clipped 2×2 averaging rule as conversion. These rules are the oracle even
if a storage-specific optimized kernel is used.

| Operation | Accepted source → destination | Destination geometry |
|---|---|---|
| convert | each of I420, NV12, BGRA8888, RGBA8888 → each of I420, NV12, BGRA8888 | exactly source width × height |
| black-white, grayscale, negate | I420→I420, NV12→NV12, BGRA→BGRA | exactly source width × height |
| Gaussian, mean, box | I420→I420, NV12→NV12, BGRA→BGRA | exactly source width × height |
| crop | I420→I420, NV12→NV12, BGRA→BGRA | exactly options width × height |
| flip | I420→I420, NV12→NV12, BGRA→BGRA | exactly source width × height |
| rotate 0/180 | I420→I420, NV12→NV12, BGRA→BGRA | exactly source width × height |
| rotate 90/270 | I420→I420, NV12→NV12, BGRA→BGRA | source height × width |
| chroma swap | NV12→NV12 only | exactly source width × height |

RGBA8888 is valid only as a one-plane source to `yuv_convert_v1`. A same-format
conversion is a stride-aware deep copy, not aliasing. Unsupported pairs return
`YUV_STATUS_UNSUPPORTED_FORMAT` before destination writes.

Transforms use visible-pixel coordinates. Horizontal maps destination `(x,y)`
from source `(width-1-x,y)`; vertical from `(x,height-1-y)`. Clockwise rotations
map 90° destination `(x,y)` from source `(y,height-1-x)`, 180° from
`(width-1-x,height-1-y)`, and 270° from `(width-1-y,x)`. Crop destination `(x,y)`
comes from visible source `(left+x,top+y)`, with the odd-origin chroma rule in
section 14. Implementations may use direct plane paths only when they are
equivalent to these visible-pixel mappings.

Plane layouts are validated per descriptor, so source and destination may use
different padding/strides:

| Format | Planes and logical geometry | `sampleBytes` / minimum `pixelStride` |
|---|---|---|
| I420 | Y: `w×h`; U,V: `ceil(w/2)×ceil(h/2)` | `1 / 1` for every plane |
| NV12 | Y: `w×h`; UV: `ceil(w/2)×ceil(h/2)` | Y `1 / 1`; UV `2 / 2` |
| BGRA8888 or RGBA8888 | packed: `w×h` | `4 / 4` |

For a plane of logical `planeWidth × planeHeight`, checked validation requires
`rowStride >= (planeWidth - 1) * pixelStride + sampleBytes` and
`length >= (planeHeight - 1) * rowStride +
(planeWidth - 1) * pixelStride + sampleBytes`. Positive larger pixel/row strides
are supported. Active samples are read/written through both strides; row gaps,
pixel gaps, and bytes beyond the minimum span are padding and must remain
unchanged. Insufficient or arithmetically overflowing spans are invalid/overflow
statuses respectively.

All YUV↔RGB conversions use the existing BT.601 limited-range integer oracle.
RGBA/BGRA→YUV averages U and V over the clipped visible pixels in each 2×2
chroma footprint, including odd right/bottom edges. YUV→BGRA writes alpha 255.
BGRA→BGRA/RGBA-source→BGRA preserves input alpha. Effects and blur preserve the
BGRA alpha byte; geometric transforms move it with its pixel. ROI effects seed
the destination from source and modify only samples selected by the normalized
ROI/approved chroma-footprint rule.

### Status-to-Dart exception mapping

Public Dart validation runs before allocation/dispatch, but native validation is
still authoritative for hostile or mismatched descriptors:

| Native status | Dart result |
|---:|---|
| `0 OK` | Commit destination; no exception |
| `1 INVALID_ARGUMENT` | `ArgumentError` naming the operation and invalid descriptor/options contract |
| `2 UNSUPPORTED_FORMAT` | `UnsupportedError` with source/destination formats |
| `3 UNSUPPORTED_LAYOUT` | `UnsupportedError` with the unsupported but structurally valid layout |
| `4 OVERFLOW` | `YuvNativeException(statusCode: 4, operation: ...)` |
| `5 ALLOCATION_FAILED` | `YuvNativeException(statusCode: 5, operation: ...)` |
| `6 INTERNAL_ERROR` | `YuvNativeException(statusCode: 6, operation: ...)` |
| `7 UNSUPPORTED_COLOR` | `UnsupportedError` with matrix/range |
| any unknown non-zero value | `YuvNativeException` retaining the unknown code |

Every non-zero status skips commit/copy-back and leaves source, destination Dart
state, metadata, and revision unchanged. Backend unavailability/capability
rejection occurs before invocation and throws `UnsupportedError`, not a native
status exception.

## 12. Complete legacy native symbol migration

Current HEAD declares 40 processing symbols. Every one is mapped below.

| Legacy symbol | Target symbol |
|---|---|
| `bgra8888_blackwhite` | `yuv_black_white_v1` |
| `bgra8888_box_blur` | `yuv_box_blur_v1` |
| `bgra8888_crop_rect` | `yuv_crop_v1` |
| `bgra8888_flip_horizontally` | `yuv_flip_v1` with horizontal option |
| `bgra8888_flip_vertically` | `yuv_flip_v1` with vertical option |
| `bgra8888_from_rgba8888` | `yuv_convert_v1` |
| `bgra8888_gaussian_blur` | `yuv_gaussian_blur_v1` |
| `bgra8888_grayscale` | `yuv_grayscale_v1` |
| `bgra8888_mean_blur` | `yuv_mean_blur_v1` |
| `bgra8888_negate` | `yuv_negate_v1` |
| `bgra8888_rotate` | `yuv_rotate_v1` |
| `bgra8888_to_i420` | `yuv_convert_v1` |
| `bgra8888_to_nv21` | `yuv_convert_v1` to canonical NV12 |
| `yuv420_blackwhite` | `yuv_black_white_v1` |
| `yuv420_box_blur` | `yuv_box_blur_v1` |
| `yuv420_crop_rect` | `yuv_crop_v1` |
| `yuv420_flip_horizontally` | `yuv_flip_v1` with horizontal option |
| `yuv420_flip_vertically` | `yuv_flip_v1` with vertical option |
| `yuv420_from_rgba8888` | `yuv_convert_v1` |
| `yuv420_gaussblur` | `yuv_gaussian_blur_v1` |
| `yuv420_grayscale` | `yuv_grayscale_v1` |
| `yuv420_mean_blur` | `yuv_mean_blur_v1` |
| `yuv420_negate` | `yuv_negate_v1` |
| `yuv420_rotate` | `yuv_rotate_v1` |
| `yuv420_to_bgra8888` | `yuv_convert_v1` |
| `yuv420_i420_to_nv21` | `yuv_convert_v1` to canonical NV12 |
| `nv21_blackwhite` | `yuv_black_white_v1` on canonical NV12 |
| `nv21_box_blur` | `yuv_box_blur_v1` on canonical NV12 |
| `nv21_crop_rect` | `yuv_crop_v1` on canonical NV12 |
| `nv21_flip_horizontally` | `yuv_flip_v1` with horizontal option |
| `nv21_flip_vertically` | `yuv_flip_v1` with vertical option |
| `nv21_from_rgba8888` | `yuv_convert_v1` to canonical NV12 |
| `nv21_gaussian_blur` | `yuv_gaussian_blur_v1` on canonical NV12 |
| `nv21_grayscale` | `yuv_grayscale_v1` on canonical NV12 |
| `nv21_mean_blur` | `yuv_mean_blur_v1` on canonical NV12 |
| `nv21_negate` | `yuv_negate_v1` on canonical NV12 |
| `nv21_rotate` | `yuv_rotate_v1` on canonical NV12 |
| `nv21_to_i420` | `yuv_convert_v1` |
| `nv21_to_bgra8888` | `yuv_convert_v1` |
| `nvXX_to_nvYY` | `yuv_chroma_swap_v1`, with section 14 semantics |

`generate_gaussian_kernel`, `apply_1d_gaussian`,
`gaussian_blur_plane_strided`, and `swap_bytes` are internal helpers, not ABI.
Allocator exports used only by WASM remain loader infrastructure, not processing
API. Removed/undefined historical declarations must not be reintroduced.

## 13. Transactional Dart/backend design

Shared Dart layer owns public semantics and state. IO and Web implement only
transport/memory/dispatch:

```dart
abstract interface class YuvBackend {
  YuvCapabilities get capabilities;

  YuvNativeStatus execute(
    YuvOperation operation,
    YuvFrameData source,
    YuvFrameData destination,
    YuvOperationOptions options,
  );
}
```

IO uses `NativeYuvFrame` to own the descriptor and all allocations. Web uses an
equivalent WASM-linear-memory lease. Both runners follow:

1. validate public arguments and capability;
2. allocate/copy read-only source staging;
3. allocate and seed destination staging where preservation is required;
4. allocate versioned options;
5. invoke exactly one format-independent symbol;
6. map non-zero status to Dart exception without publishing destination;
7. copy destination into a Dart draft;
8. atomically replace receiver for `apply*`, bumping revision once, or return a
   new object for `to*`;
9. dispose options, destination, and source in `finally`.

C validates all descriptors and allocates all scratch before its first write.
After writing starts, no fallible operation is permitted. Consequently a
non-success status leaves destination unchanged. Source is always immutable and
active source/destination spans cannot alias.

The staging-copy design is intentional for `0.4.0`: current planes live on the
Dart heap and Web has a separate linear memory. A native-backed zero-copy image
is a future optional API requiring benchmark and lifecycle design.

## 14. Final Engineer decisions

### Q1 — legacy `swapNv()` meaning

The old method swaps every interleaved U/V byte but keeps the same legacy
`nv21` label. Once canonical storage is truthfully named NV12, interpreting this
as an NV12↔NV21 format conversion would require a real NV21 format value and
would conflict with the approved rule that existing `nv21` entry points retain
their UV interpretation.

Approved 2026-09-14: define new `applyChromaSwap()` as a visible channel-value
effect, not a format conversion. It swaps U and V sample values while the frame
remains labeled NV12. Deprecated `swapNv()` converts non-NV input to NV12 and
then calls `applyChromaSwap()`, preserving historical output bytes without
claiming that the result is truthful NV21 storage.

The native effect reads each logical NV12 UV pair through its row/pixel strides,
writes `(V,U)` to the corresponding destination sample, copies Y unchanged, and
does not touch padding. It rejects I420/BGRA/RGBA and enabled regional options
before writing.

A true VU NV21 format is not added in this refactor. It would be a separate
format/codec/reference expansion and must not be inferred from the legacy name.

### Q2 — odd-origin 4:2:0 crop/ROI chroma phase

For a crop starting at odd x/y, output luma origin does not align with source
2×2 chroma blocks. Directly copying chroma samples creates a phase shift.

Approved 2026-09-14: public crop has visible-pixel semantics. For an odd
origin, recompute destination chroma from the source visible RGB footprint (or
an exactly equivalent phase-aware implementation) and verify it against the
reference oracle. Even-origin crop may use the direct fast path. For blur/effect
ROI, process each chroma sample whose 2×2 luma footprint intersects the
normalized ROI; document possible shared-chroma influence at the boundary.

Rejecting valid odd crop origins is not part of the target API.

## 15. Implementation sequence

Native ABI tasks YUV-33/36/26/31/32/22/23/34 formed the unpublished 0.3.0
development baseline. The 0.4.0 implementation sequence covered format
identity and codec; public factories and plane ownership; mutation and pure
operations; deprecated compatibility; initialization, capabilities and
errors; documentation; then platform verification. The historical task list
is no longer maintained in the active tracker. No new native symbol or C
change is implied by this design revision. Any needed native C change requires
its own plan and approval.

## 16. Breaking changes in 0.4.0

- The public storage format becomes `YuvPixelFormat` with explicit `nv12` and
  stable wire IDs. Legacy `nv21` keeps its historical UV bytes and is deprecated.
- New `apply*` methods mutate and return the same image; new `to*` methods return
  an independent image. Old mutating methods remain as deprecated extensions.
  Adding members to `YuvImage` also breaks foreign `implements YuvImage` classes.
- The default I420 chroma pixel stride becomes 1. Code depending on the old
  gapped default must specify its stride explicitly.
- Codec output changes from v1 to v2 and the decoder accepts v2 only. Existing
  serialized v1 frames require a two-app-version migration: extract format,
  dimensions, plane strides, and bytes while running published 0.2.4; reconstruct and
  encode v2 only after upgrading.
- Image plane getters remain live and mutable. Clients that edit those buffers
  must call `markDirty()` so revision-keyed caches refresh; replacement
  operations invalidate earlier plane handles.
- `YuvFfi.initialize()` returns capabilities, and unsupported operations report
  typed failures according to sections 2 and 7. Web remains a partial backend.

These are the implemented release contracts; the release CHANGELOG documents
their user-facing impact.

## 17. Required design verification

- Public API compile tests for `apply* == identical(this)`, independent `to*`,
  live plane getters, `markDirty()` invalidation, deprecated forwarding, and
  foreign implementation.
- ABI layout tests for native-32, native-64, and wasm32 sizes/offsets.
- One symbol-manifest test shared by headers, ffigen allowlist, Web dispatch,
  and WASM exported functions.
- Status tests for every numeric value and Dart exception mapping.
- Atomic failure tests for invalid descriptor, overflow, unsupported layout,
  injected allocation failure, and Web unavailable capability.
- Reference tests for every operation/format, padded strides, odd sizes, alpha,
  padding canaries, and the two decisions in section 14.

## 18. Current CI verification

The workflow is maintained in [`.github/workflows/ci.yml`](../.github/workflows/ci.yml).
Its current platform evidence is narrower than the complete design verification
list above and must not be read as full backend parity:

- `analyze-and-test-vm` runs analyzer and package tests on Flutter 3.38.10 and
  3.44.9; the Linux native library is built and loaded for those tests.
- `native-sanitizer-gate` runs the C ABI sanitizer suite in Debug and Release.
- `bindings-regeneration` regenerates and audits ffigen output on Flutter 3.44.9.
- `linux-native-smoke` and `macos-native-smoke` build the example and run
  app-runtime conversion/effect smoke checks.
- `android-native-build` is configured to build the Android example APK and run
  the app-runtime conversion/effect smoke on an API 35 x86_64 emulator. The job
  prints the emulator ABI before driving the test.
- `ios-native-build` builds simulator and device examples and runs the app-runtime
  smoke on an iPhone simulator. Physical-device camera validation is separate
  from CI.
- `wasm-web-integration` runs browser integration contracts and the 119-case
  Web reference matrix using the actual WASM asset bundle. The reference cases
  cover constructors, conversions, transforms, effects, blur, copying, and
  serialization; this does not establish complete Web feature parity with
  native backends. Asset-dependent browser tests live under
  `example/integration_test/`; tests under `test/web/` either use VM
  placeholders or exercise browser-only code with a fake module, so they are
  not evidence for the asset-backed runtime path.

This matrix describes the workflow at the time of the 0.4.1 maintenance pass;
check the workflow itself for changes to targets or commands.
