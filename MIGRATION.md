# Migrating to 0.5.x

## Scope

This guide covers applications moving from the last available release, `yuv_ffi: ^0.2.4`, to the 0.5.x line. Version 0.4.0 was published and later retracted. Applications whose lockfile still resolves 0.4.0 follow the same migration. The minimums are Dart 3.12, Flutter 3.44, Android API 26, iOS 13, and macOS 10.15. Android `x86` is no longer supported; supported Android ABIs are `armeabi-v7a`, `arm64-v8a`, and `x86_64`.

## Steps

1. Change the dependency to `yuv_ffi: ^0.5.1` and run `flutter pub upgrade yuv_ffi`.
2. Await `YuvFfi.initialize()` in every isolate: before capability-gated operations on native platforms and before any image operation on Web.
3. Apply only the `rename` rows in the table mechanically. Search with each listed pattern first.
4. Resolve every `review` row using the decision rules below; do not apply a blind replacement.
5. Migrate persisted frames through your application's own representation as described under Stored frames.
6. Run the Verify commands, `flutter analyze`, and your application's tests on its supported targets.

## Updating from 0.5.0 to 0.5.1

This update does not require API replacements or re-migration of serialized frames. Change the dependency to
`yuv_ffi: ^0.5.1`, run `flutter pub upgrade yuv_ffi`, and check the application on its supported targets. The Web
`--wasm` operation-call failure present in 0.5.0 is fixed in 0.5.1; checked cases passed in Chrome on both the
JavaScript and `--wasm` builds. Safari and Firefox have not been verified.

## Mechanical replacements

Each row names one old public symbol or call form. Patterns are intended for `rg` in application Dart sources; adapt file globs to the repository and confirm the receiver is a `YuvImage` where relevant. `rename` preserves the relevant behavior and bytes. `review` requires the decision below.

| 0.2.4 call / symbol | 0.5.x call / symbol | `rg` pattern | Kind |
| --- | --- | --- | --- |
| `YuvFfi.ensureInitialized()` | `YuvFfi.initialize()` | `YuvFfi\.ensureInitialized\s*\(` | review |
| `YuvImage.nv21(...)` | `YuvImage.nv12(...)` | `YuvImage\.nv21\s*\(` | review |
| `YuvImageImpl` | `YuvImage` factories | `\bYuvImageImpl\b` | review |
| `YuvImage(YuvFileFormat.i420, ...)` | `YuvImage.i420(...)` | `YuvImage\s*\(\s*YuvFileFormat\.i420` | review |
| `YuvImage(YuvFileFormat.nv21, ...)` | `YuvImage.nv12(...)` | `YuvImage\s*\(\s*YuvFileFormat\.nv21` | review |
| `YuvImage(YuvFileFormat.bgra8888, ...)` | `YuvImage.bgra(...)` | `YuvImage\s*\(\s*YuvFileFormat\.bgra8888` | review |
| `YuvImage(YuvFileFormat format, ...)` | Named `YuvImage.i420(...)`, `.nv12(...)`, `.bgra(...)`, or `.allocate(...)` factory | `YuvImage\s*\(\s*format\b` | review |
| `YuvFileFormat` | `YuvPixelFormat` | `\bYuvFileFormat\b` | review |
| `YuvImage.copy()` | `copy()` | `\.copy\s*\(\s*\)` | rename |
| `image.copy(blank: false)` | `image.copy()` | `\.copy\s*\([^)]*blank\s*:\s*false` | rename |
| `image.copy(blank: true)` | `YuvImage.allocate(format, width, height)` | `\.copy\s*\([^)]*blank\s*:\s*true` | review |
| `image.getBytes()` | `image.toBytes()` | `\.getBytes\s*\(` | rename |
| `image.save(sink)` | `image.encodeTo(sink)` | `\.save\s*\(` | review |
| `image.load(stream)` | `YuvImage.decode(stream)` | `\.load\s*\(` | review |
| `image.blackwhite()` | `image.applyBlackWhite()` | `\.blackwhite\s*\(` | review |
| `image.grayscale()` | `image.applyGrayscale()` | `\.grayscale\s*\(` | review |
| `image.negate()` | `image.applyNegate()` | `\.negate\s*\(` | review |
| `image.gaussianBlur()` / `image.gaussianBlur(radius:, sigma:)` | `image.applyGaussianBlur(radius:, sigma:)` | `\.gaussianBlur\s*\(` | review |
| `image.boxBlur()` / `image.boxBlur(radius:, rect:)` | `image.applyBoxBlur(radius:, region:)` | `\.boxBlur\s*\(` | review |
| `image.meanBlur()` / `image.meanBlur(radius:, rect:)` | `image.applyMeanBlur(radius:, region:)` | `\.meanBlur\s*\(` | review |
| `image.swapNv()` | `image.applyChromaSwap()` | `\.swapNv\s*\(` | review |
| `image.toYuvNv21()` | `image.applyFormat(YuvPixelFormat.nv12)` or `image.toNv12()` | `\.toYuvNv21\s*\(` | review |
| `image.toYuvI420()` | `image.applyFormat(YuvPixelFormat.i420)` or `image.toI420()` | `\.toYuvI420\s*\(` | review |
| `image.toYuvBgra8888()` | `image.applyFormat(YuvPixelFormat.bgra8888)` or `image.toBgra()` | `\.toYuvBgra8888\s*\(` | review |
| `image.crop(rect)` | `image.applyCrop(rect)` or `image.cropped(rect)` | `\.crop\s*\(` | review |
| `image.flipHorizontally()` | `image.applyFlipHorizontal()` | `\.flipHorizontally\s*\(` | review |
| `image.flipVertically()` | `image.applyFlipVertical()` | `\.flipVertically\s*\(` | review |
| `image.fromRgba8888(bytes)` | `image.applyRgbaBytes(bytes)` | `\.fromRgba8888\s*\(` | review |
| `image.rotate(rotation)` | `image.applyRotation(rotation)` or `image.rotated(rotation)` | `\.rotate\s*\(` | review |
| `image.toBgra8888()` | `image.toBgraBytes()` | `\.toBgra8888\s*\(` | rename |
| `image.y` | `image.yPlane` | `\.y\b` | rename |
| `image.u` | `image.uPlane` | `\.u\b` | review |
| `image.v` | `image.vPlane` | `\.v\b` | review |
| `plane.bytesPerPixes` | `plane.bytesPerPixel` | `\.bytesPerPixes\b` | rename |

`YuvPlane`, `YuvImageRotation`, `YuvImage.toImage()`, and `YuvImageWidget` retain their public names. Check their changed semantics below where applicable. `YuvImageImpl` was exposed through an implementation export in 0.2.4; it is no longer exported, so migrate code to the `YuvImage` factories instead of depending on that implementation class.

## Changes that need a decision

- **Initialization:** replace `ensureInitialized` with awaited `initialize`. It returns `YuvCapabilities`; initialization is per isolate. Call it in each isolate before backend processing. Web requires initialization before any image operation.
- **NV21 naming and UV order:** the 0.2.4 `nv21` factory used interleaved **UV** bytes, not VU. This is confirmed by the 0.2.4 implementation, so map it to `nv12`; do not swap the bytes just because of the legacy name. The legacy `YuvFileFormat.nv21` likewise represented this UV order.
- **Format type:** replace `YuvFileFormat` with `YuvPixelFormat`; values are `i420`, `nv12`, and `bgra8888`. Review switches, serialization, and any persisted enum index rather than mechanically substituting enum values.
- **Constructors:** after choosing a named factory, confirm its defaults. I420 now defaults to `uvPixelStride: 1`, and factories with supplied planes pack them by default; these changes also apply when replacing the former generic constructor.
- **Copy/allocation:** `copy()` always copies the current contents. In 0.2.4, `copy(blank: true)` retained dimensions, format, and pixel strides, but reconstructed planes and recalculated row strides; arbitrary source row padding was not retained. `YuvImage.allocate(format, width, height)` makes a zero-filled tightly packed image and is the choice for a tightly packed blank image. To preserve an explicitly desired padded layout from an I420 `source`, recreate each zeroed plane from its own geometry and pass `layout: YuvPlaneLayout.preserve`:

  ```dart
  final blank = YuvImage.i420(
    source.width,
    source.height,
    planes: source.planes.map((plane) => YuvPlane(plane.height, plane.rowStride, plane.pixelStride)),
    layout: YuvPlaneLayout.preserve,
  );
  ```

  `YuvPlane` creates zeroed bytes when `bytes` is omitted. This explicit layout recipe is not equivalent to old `copy(blank: true)` when its recalculated strides differed from the source.
- **Mutating methods:** `load(stream)` mutated its receiver; `YuvImage.decode(stream)` returns a new image, so assign the returned image. The old `toYuvI420`, `toYuvNv21`, and `toYuvBgra8888` methods mutated the receiver: choose `applyFormat(...)` for that behavior, or `toI420()`, `toNv12()`, and `toBgra()` for an independent result. The new `apply*` transformations mutate; `cropped` and `rotated` return new images.
- **Serialization:** `save(sink)` becomes `encodeTo(sink)`, but the serialized formats are incompatible. Do not treat this call rename as a way to convert saved v1 frames; use the Stored frames procedure.
- **Crop and blur arguments:** rename `rect:` to `region:` for `applyBoxBlur` and `applyMeanBlur`. Coordinates remain image pixels; review nullable regions and call sites that relied on old rounding or clamping behavior.
- **Blur calls:** old `gaussianBlur()` defaulted to `radius: 2, sigma: 2`; use `applyGaussianBlur(radius: 2, sigma: 2.0)`. For `gaussianBlur(radius: r)` use `applyGaussianBlur(radius: r, sigma: 2.0)`; for `gaussianBlur(sigma: s)` use `applyGaussianBlur(radius: 2, sigma: s.toDouble())` when `s` is an integer. Preserve both explicit values, converting integer sigma values to `double` (for numeric literals, write e.g. `2.0`). Old `boxBlur()` defaulted to radius 10 and `meanBlur()` to radius 2: use `applyBoxBlur(radius: 10)` and `applyMeanBlur(radius: 2)`. Preserve explicit Box/Mean radii and change `rect:` to `region:`; for example, `boxBlur(rect: rect)` becomes `applyBoxBlur(radius: 10, region: rect)`, and `meanBlur(rect: rect)` becomes `applyMeanBlur(radius: 2, region: rect)`. These are argument migration rules; do not infer byte-for-byte blur equivalence from them.
- **Chroma swap:** in 0.2.4, `swapNv()` first converted any non-NV21 format to NV21-labeled UV and then swapped chroma. The new `applyChromaSwap()` accepts only NV12, so for an existing NV12 image call it directly. To retain the old route from another format, convert to NV12 and then swap; for example, `image.applyFormat(YuvPixelFormat.nv12).applyChromaSwap()` for I420. The old NV21 label represented UV order as described above.
- **Plane access:** old `u` and `v` getters were nullable; new `uPlane` and `vPlane` accessors are non-null. Review format-specific access and branches that handled a missing plane.
- **Plane layout:** factories receiving `planes:` now default to `YuvPlaneLayout.packed`, copying visible samples into packed storage. Pass `layout: YuvPlaneLayout.preserve` to retain source strides and padding. NV12's interleaved chroma has `pixelStride == 2`; I420's default `uvPixelStride` is now 1.
- **Direct plane writes:** after modifying `YuvPlane.bytes`, `setPixel`, or `assignFrom`, call the exported `YuvImageInvalidation` extension method `image.markDirty()` so cached widget images are invalidated.
- **Errors:** operations now report typed errors such as `ArgumentError`, `FormatException`, `UnsupportedError`, `StateError`, or `YuvNativeException`. Update catches to the documented type instead of relying on a generic native failure.
- **Implementations:** `YuvImage` is an interface for consumers to implement. If your class uses `implements YuvImage`, add every newly required member or migrate to composition; prefer the provided factories when you do not need a custom implementation.

## Behavior changes without compile errors

- I420 `uvPixelStride` defaults to 1.
- Supplied `planes:` are packed by default; use `layout: YuvPlaneLayout.preserve` to retain strides and padding.
- Native capability-gated processing requires `YuvFfi.initialize()` first, once per isolate.
- Direct plane-buffer writes require `markDirty()` for widget cache invalidation.
- Encoded 0.2.4 frames are not readable by the 0.5.x codec; see Stored frames.
- Android `x86` is unsupported. Minimum platform versions are listed in Scope.

## Stored frames

There is no automatic migration for serialized frames from 0.2.4. Decode or otherwise read each old frame with the 0.2.4 application, export an application-owned representation containing format, dimensions, plane row and pixel strides, and plane bytes, then recreate the image with the matching 0.5.x factory and encode it with `encodeTo`. Do not re-save a v1 payload with the 0.5.x codec and expect it to migrate; the formats are incompatible. Frames already encoded by 0.5.0 need no re-migration for 0.5.1.

## Native and Web consumers

Code calling removed native exports such as `yuv420_*`, `nv21_*`, or `bgra8888_*` must move to the ABI v1 interface and its frame/options structures. Do not call those removed symbols directly. Web uses Flutter's JavaScript or `--wasm` build. The interop return-value failure in 0.5.0 is fixed in 0.5.1: checked operation cases passed in Chrome on both builds. This evidence does not cover every input or browser; Safari and Firefox have not been verified. Use `YuvCapabilities` to check the operations exported by the loaded module.

## Verify

Run these searches over application Dart sources; each should return no old call sites that still need migration:

```sh
rg -n 'YuvFfi\.ensureInitialized|YuvImage\.nv21|YuvFileFormat|\.getBytes\s*\(|\.save\s*\(|\.load\s*\(|\.blackwhite\s*\(|\.grayscale\s*\(|\.negate\s*\(|\.gaussianBlur\s*\(|\.boxBlur\s*\(|\.meanBlur\s*\(|\.swapNv\s*\(|\.toYuv(Nv21|I420|Bgra8888)\s*\(|\.crop\s*\(|\.flipHorizontally\s*\(|\.flipVertically\s*\(|\.fromRgba8888\s*\(|\.rotate\s*\(|\.toBgra8888\s*\(' lib
rg -n '\.copy\s*\([^)]*blank\s*:' lib
rg -n '\bYuvImageImpl\b|\.bytesPerPixes\b' lib
```

Then run `flutter analyze` and the application's tests. Also inspect native and Web source for removed symbols if the application calls package internals directly.

## For automated agents

Apply `rename` rows only when the exact call form matches. For `review` rows, use the decision rule above or leave a TODO comment for an engineer. Do not rewrite stored frame data or native code. Finish by running the Verify searches, `flutter analyze`, and application tests.
