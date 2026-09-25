# PERF-01: Benchmark Setup

Status: stand definition for the 0.4.2 performance series (tracker: `todo.md`, section
"0.4.2 — производительность ABI v1"). This document fixes *what* is measured, *on which bytes*, *with which
build*, and *how* the numbers are reduced. It does not contain measurements: MEAS-01/02/03 produce the
baseline matrices, PERF-02…31 the per-function `before → after → 0.2.4` tables, PERF-34/35/36 the repeats.

Everything marked **verified** below was executed on the reference machine on 2026-09-25 while writing this
document. Everything marked **to be created** is a specification for the MEAS-01 executor; PERF-01 changed no
code.

## Toolchain

Reference Windows machine (MEAS-01, PERF-02…31, PERF-34):

| Item | Value |
|---|---|
| OS | Windows 10 Home 10.0.19045 (build 19045), x64 |
| CPU | 13th Gen Intel Core i9-13980HX, 24 cores / 32 logical processors (8 P-cores with HT + 16 E-cores), base clock 2.2 GHz |
| RAM | 64 GB |
| IDE / toolset | Visual Studio 2022 Community 17.14.13 (August 2025), MSVC toolset 14.44.35207 |
| C compiler | `cl.exe` 14.44.35215.0, `Hostx64\x64` |
| Windows SDK | 10.0.22621.0 and 10.0.26100.0 installed (CMake picks the default) |
| CMake | 3.31.6-msvc6, bundled with VS2022; not on `PATH` (see below) |
| CMake generator | `Visual Studio 17 2022`, platform `x64` (multi-config) |
| Flutter | 3.44.9, channel stable, framework `6b182d2c75`, engine `b9499e4c25` |
| Dart | 3.12.2 (stable), `windows_x64` |
| Git | 2.45.1.windows.1 |

CMake and CTest are not installed on their own. Call them by full path:

```powershell
$CMakeBin = 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin'
& "$CMakeBin\cmake.exe" --version
```

`dumpbin.exe` (export checks) is `C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\dumpbin.exe`.
To use `cl.exe` from a plain shell, open a VS developer environment. `vcvars64.bat` needs `vswhere.exe` on
`PATH`, and the non-interactive shell does not have it:

```cmd
set "PATH=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer;%PATH%"
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
```

### Effective release flags (verified)

Both versions compile with **identical** flags in CMake `Release`. This is the parity condition for every
comparison in the series:

| Version | Flags from `CMakeCache.txt` / `yuv_ffi.vcxproj` (Release x64) |
|---|---|
| 0.2.4 | `/DWIN32 /D_WINDOWS /W3` + `/MD /O2 /Ob2 /DNDEBUG`; `Optimization=MaxSpeed`, `InlineFunctionExpansion=AnySuitable`, no `/GL` |
| ABI v1 `35c516e` | the same; its explicit `$<$<NOT:$<CONFIG:Debug>>:/O2>` from `src/CMakeLists.txt` duplicates the CMake Release default |

Neither version enables LTO (`/GL`, `/LTCG`) or `/arch:AVX*`. The x64 baseline is SSE2. Do not add flags on
one side only. If a PERF card changes flags, that is a build change and gets its own card and measurement.

Other platforms (reference only; recorded again at their stages):

- Android / Pixel 3 (MEAS-02, PERF-32/33/35): Android SDK `D:\.important\android-sdk`, NDK 21…28, JDK 17. The
  plugin builds through `android/` → `src/CMakeLists.txt` (`-O3` for non-Debug). Build the release APK
  locally, not in CI.
- Web (MEAS-03, PERF-36): `bash ./tool/wasm/build_wasm.sh` with emsdk on `PATH` (it must run under `bash`;
  under `sh`/dash the `emcc.bat` fallback silently fails). The release profile uses `-O3`. Browser runs happen
  on the Mac runner, because local Chrome hangs on `loading`.

## Repository tags and SHAs

| Role | Ref | Commit | `src/` tree id |
|---|---|---|---|
| Published baseline | tag `0.2.4` (annotated) | `5f52fd14540a283da91a6d80e1fc7128bba1c796` (2026-03-06) | `eba076b4cc9a0d7a686b61edbbb8101da9270356` |
| ABI v1 baseline | `35c516e` on `release/0.4.2` | `35c516e216fef8d5ed4ef379d38655fc643f738d` (2026-09-25) | `9029ff28d9834c069f41159d122b36ed6d9d4968` |

- Whole-tree ids: `0.2.4^{tree}` = `dad02af70d6640e70f1e016d19c9bd113f482e16`, `35c516e^{tree}` =
  `0233f81b6a14c73d00acc5cc9d0fe5ba9010076a`.
- Identity check before any run: `git -C <repo> rev-parse 0.2.4:src 35c516e:src` must print the two tree ids
  above.
- Informational: with git 2.45.1, `git archive --format=tar` produced SHA-256
  `70d4e6498eb5f12b94c32343162319acc2fd36a18078041ffa40c33cdec6ec2a` for `0.2.4 src` and
  `44c771316191784232dbfb9665763540228f41f325d32f8adca94e478032cff8` for `35c516e src CMakeLists.txt test_native`.
  The tree ids are the authoritative identity. Archive bytes may differ across git versions.
- **Never benchmark the working tree.** On 2026-09-25 the working tree of `release/0.4.2` has uncommitted
  changes, including `src/CMakeLists.txt` (a version bump only). Each measured version is extracted from its
  commit, as shown below.
- For PERF-02…31, "before" means the card's immediate parent SHA and "after" is the card's own commit. Both
  are extracted the same way, with the SHA substituted.

## How to build (Release)

All commands are PowerShell, run on the reference machine. The bench root lives **outside** the repository, so
nothing lands in the repo's working tree. Any path works; `$B` below is the suggested default.

```powershell
$Repo     = 'D:\.projects\yuv_ffi'
$B        = "$env:TEMP\yuv_ffi_bench"
$CMakeBin = 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin'
$AbiSha   = '35c516e216fef8d5ed4ef379d38655fc643f738d'

New-Item -ItemType Directory -Force "$B\v024", "$B\abi_v1" | Out-Null

# 1. Extract exact sources (0.2.4 has no root CMakeLists.txt and no test_native/).
git -C $Repo archive --format=tar -o "$B\v024.tar"   0.2.4   src
git -C $Repo archive --format=tar -o "$B\abi_v1.tar" $AbiSha src CMakeLists.txt test_native
tar -xf "$B\v024.tar"   -C "$B\v024"
tar -xf "$B\abi_v1.tar" -C "$B\abi_v1"

# 2. Configure + build the shared library in Release (multi-config: the type is chosen at build time).
& "$CMakeBin\cmake.exe" -S "$B\v024\src"   -B "$B\v024\build"   -G "Visual Studio 17 2022" -A x64
& "$CMakeBin\cmake.exe" --build "$B\v024\build"   --config Release
& "$CMakeBin\cmake.exe" -S "$B\abi_v1\src" -B "$B\abi_v1\build" -G "Visual Studio 17 2022" -A x64
& "$CMakeBin\cmake.exe" --build "$B\abi_v1\build" --config Release
# Outputs: $B\v024\build\Release\yuv_ffi.{dll,lib}   and   $B\abi_v1\build\Release\yuv_ffi.{dll,lib}
```

Post-build checks (verified 2026-09-25):

```powershell
$Dumpbin = 'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\dumpbin.exe'
& $Dumpbin /exports "$B\abi_v1\build\Release\yuv_ffi.dll"   # exactly the 11 yuv_*_v1 symbols
& $Dumpbin /exports "$B\v024\build\Release\yuv_ffi.dll"     # 40 legacy symbols (bgra8888_*, nv21_*, yuv420_*, nvXX_to_nvYY)
Select-String -Path "$B\abi_v1\build\CMakeCache.txt" -Pattern '^CMAKE_C_FLAGS_RELEASE'   # /MD /O2 /Ob2 /DNDEBUG
```

- 0.2.4 builds with warnings C4244/C4018 in its legacy kernels. They are expected and are not errors.
- The DLL files are not bit-reproducible, because they embed a link timestamp. Identify a build by source tree
  id + toolchain + flags, not by DLL hash.
- A Flutter build (`flutter build windows --release`) compiles the same `src/` through the plugin's
  `windows/CMakeLists.txt` with the Flutter Release configuration. That is the library the Dart-level bench
  loads.

## Test inputs

### Image sizes

| Name | Size | Luma samples | Role |
|---|---|---:|---|
| 1080p | 1920×1080 | 2 073 600 | primary timing size, both versions |
| 12MP | 4000×3000 | 12 000 000 | primary timing size, both versions |
| odd | 1921×1081 | 2 076 601 | **ABI v1 checksum sanity only**: odd-edge chroma footprint. Not timed against 0.2.4, whose kernels assume even geometry (e.g. `width / 2` loops) and are not safe to run on it. |

### Formats and layout

All timing inputs use the **tight canonical layout** of ABI v1 for both versions. The 0.2.4 descriptors point
at the same bytes (see [Legacy 0.2.4 descriptor mapping](#legacy-024-descriptor-mapping)). Here `cw = ceil(w/2)`
and `ch = ceil(h/2)`. Destination buffers use the same tight layout for the destination geometry: the crop
size, or `h × w` for 90°/270° rotations.

| Format | Planes (ABI v1 descriptor) | colorMatrix / colorRange |
|---|---|---|
| I420 (`1`) | 3 planes: Y `{length w·h, rowStride w, pixelStride 1, sampleBytes 1}`; U, V `{cw·ch, cw, 1, 1}` | BT601 / LIMITED |
| NV12 (`2`) | 2 planes: Y as above; UV `{2·cw·ch, 2·cw, 2, 2}` (byte order U,V) | BT601 / LIMITED |
| BGRA8888 (`3`) | 1 plane: `{4·w·h, 4·w, 4, 4}` | NONE / NONE |
| RGBA8888 (`4`) | 1 plane, as BGRA; **convert source only** | NONE / NONE |

Unused plane descriptors are zero-filled with `data = NULL`. Padded and pixel-gap layouts are correctness
fixtures that belong to the per-card tests (`todo.md` "Атомарная матрица задач"). They are not timing inputs
unless a card adds one explicitly.

### Generation (deterministic seed)

Content is uniform pseudo-random bytes. This is the worst case for branchy kernels such as threshold and
clamp, and it defeats any content-dependent shortcut. Both versions see the same bytes. The generator is
xorshift32. Each output byte is the top byte of the state after one step:

```c
static uint32_t xs;                       /* state; seeded per stream, never 0 */
static uint8_t next_byte(void) {
    xs ^= xs << 13;
    xs ^= xs >> 17;                       /* logical shift on uint32_t */
    xs ^= xs << 5;
    return (uint8_t)(xs >> 24);
}
```

| Stream | Seed | Fills |
|---|---|---|
| Y | `0x2026A001` | I420 Y and NV12 Y (identical bytes): `w·h` bytes, row-major |
| U | `0x2026A002` | I420 U: `cw·ch` bytes, row-major |
| V | `0x2026A003` | I420 V: `cw·ch` bytes, row-major |
| BGRA | `0x2026A004` | per pixel, row-major: `B = next, G = next, R = next, A = 255` |

Derived buffers:

- NV12 UV: `UV[2i] = U[i]`, `UV[2i+1] = V[i]`, so NV12 and I420 describe the same image.
- RGBA: the same pixels as BGRA, stored `R, G, B, 255`.
- `A = 255` matches camera frames and makes the effect/blur alpha-preservation paths deterministic.

Each stream restarts from its own seed for every image size. In Dart (VM or Web), mask the left shifts with
`& 0xFFFFFFFF`.

### Input checksums (verified)

SHA-256 of the tight concatenation `Y‖U‖V` (I420), `Y‖UV` (NV12) and of the single packed plane (BGRA, RGBA).
Two independent implementations produced byte-identical files: Dart VM and MSVC C, `/O2`.

| Buffer | Bytes | SHA-256 |
|---|---:|---|
| `i420_1920x1080` | 3 110 400 | `71c06f9341e998b2308625dedffb1555a57cacdb4b1479630039dab4febfc0b4` |
| `nv12_1920x1080` | 3 110 400 | `c08dec9993df462f7d96eb3e765ab97b2ac69d86f7bf13e60740ce5c3d4ee652` |
| `bgra_1920x1080` | 8 294 400 | `4a107f2e1d3895761980b2c7e5eecc1a587bffc27626b96868c9c94306dc22a9` |
| `rgba_1920x1080` | 8 294 400 | `1484337a8687599525ff9941412f83613e25e64b32cb9906f2cdf34f0d4238d7` |
| `i420_4000x3000` | 18 000 000 | `282dc210cc232feb071c75483df66bc14373c7c90d1842a8c9136a3778ceb287` |
| `nv12_4000x3000` | 18 000 000 | `cf70f5e6e0ccee46a5615ba49318d698600ec6a569280d4cc881f38be966d0aa` |
| `bgra_4000x3000` | 48 000 000 | `46cc62c75007006f05e66a39eaf8257a90091f9a97617ca16676a043a5d75146` |
| `rgba_4000x3000` | 48 000 000 | `7775779ef9d1ad4c02c11b50d26cec342666863bdb4a1019b6317bb802ad0328` |
| `i420_1921x1081` | 3 116 403 | `0f27396ee703e7e50717df8f2c06323af932efd8c11b4dbbc30a32269a518254` |
| `nv12_1921x1081` | 3 116 403 | `78668007539aabdcfae1266889fa4541d17e1e3d84355c85ef597167960b87f9` |
| `bgra_1921x1081` | 8 306 404 | `f1ef8370d694287d1a0de38ae192ab9cf663fa9d51969d20268dc7c546349023` |
| `rgba_1921x1081` | 8 306 404 | `6a17bfd1b048f1235a0bb023ba5f0c4ae7f3a29c2fb4846b203eef971623f4a9` |

Spot check: the first 8 Y bytes are `70 b9 26 a8 1b c2 ec 40`. Every harness (C, Dart IO, Dart Web, Android)
must hash its generated inputs at start-up and refuse to run on a mismatch. This is the "совпадение входных
байтов" condition of PERF-01.

### Shared geometry parameters

| Parameter | 1080p | 12MP | Used by |
|---|---|---|---|
| Centered ROI `[left, top, right, bottom)` = `[w/4, h/4, 3w/4, 3h/4)` | `[480, 270, 1440, 810)` | `[1000, 750, 3000, 2250)` | effect ROI, box/mean ROI |
| Even crop `(left, top, width, height)` = `(w/4, h/4, w/2, h/2)` | `(480, 270, 960, 540)` | `(1000, 750, 2000, 1500)` | `CROP.*.EVEN` |
| Odd crop `(w/4+1, h/4+1, w/2−1, h/2−1)` | `(481, 271, 959, 539)` | `(1001, 751, 1999, 1499)` | `CROP.*.ODD` |

The ROI is right/bottom-exclusive in both ABI v1 (`YuvRegionOptionsV1`, `enabled = 1`) and 0.2.4 (`uint32_t
rect[4] = {left, top, right, bottom}`, as written by the 0.2.4 Dart `boxBlur`/`meanBlur`).

## ABI v1 Function Registry

### Entry points

Header: `src/yuv/abi/h/yuv_ops_v1.h`, via `src/yuv_ffi.h`. Contract: `doc/api-abi-0.4-design.md` sections 9–11.
Every symbol has the form `YuvStatus f(const YuvConstFrameV1 *src, YuvMutableFrameV1 *dst, const <Options> *opt)`.
All pointers are non-null, every options struct starts with `structSize = sizeof(...)` and `abiVersion = 1`,
and all `reserved*` fields are zero. Verified: the Release DLL at `35c516e` exports exactly these 11 symbols.

| # | Function | Options struct: fields set by the bench | Formats (src → dst) | Dst geometry | Parameters measured | 0.2.4 native counterpart |
|---|---|---|---|---|---|---|
| 1 | `yuv_convert_v1` | `YuvConvertOptionsV1`: none | {I420, NV12, BGRA8888, RGBA8888} → {I420, NV12, BGRA8888}: 12 directions | = src | direction | `yuv420_to_bgra8888`, `yuv420_i420_to_nv21`, `nv21_to_i420`, `nv21_to_bgra8888`, `bgra8888_to_i420`, `bgra8888_to_nv21`, `yuv420_from_rgba8888`, `nv21_from_rgba8888`, `bgra8888_from_rgba8888`; none for same-format |
| 2 | `yuv_black_white_v1` | `YuvEffectOptionsV1`: `region` | I420→I420, NV12→NV12, BGRA→BGRA | = src | full frame; centered ROI | `yuv420_/nv21_/bgra8888_blackwhite` (in-place, full frame only) |
| 3 | `yuv_grayscale_v1` | `YuvEffectOptionsV1`: `region` | same 3 | = src | full; ROI | `*_grayscale` (in-place, full only) |
| 4 | `yuv_negate_v1` | `YuvEffectOptionsV1`: `region` | same 3 | = src | full; ROI | `*_negate` (in-place, full only) |
| 5 | `yuv_gaussian_blur_v1` | `YuvBlurOptionsV1`: `radius`, `sigma` (> 0), `borderMode = YUV_BORDER_CLAMP (1)`, `region` disabled | same 3 | = src | (r, σ) ∈ {(2, 2), (10, 10)} | `yuv420_gaussblur` (int σ), `nv21_gaussian_blur`, `bgra8888_gaussian_blur` (float σ); in-place |
| 6 | `yuv_mean_blur_v1` | `YuvBlurOptionsV1`: `radius`, `sigma = 0.0`, `borderMode = 1`, `region` | same 3 | = src | r ∈ {1, 10} full; r = 10 ROI; r = 256 full (1080p only) | `*_mean_blur(src, r, rect)`, in-place |
| 7 | `yuv_box_blur_v1` | as mean | same 3 | = src | as mean | `*_box_blur(src, r, rect)`, in-place |
| 8 | `yuv_crop_v1` | `YuvCropOptionsV1`: `left, top, width, height` | same 3 | `width × height` | even crop; odd crop | `*_crop_rect(src, dst, left, top, w, h)` |
| 9 | `yuv_flip_v1` | `YuvFlipOptionsV1`: `direction` = `YUV_FLIP_HORIZONTAL (1)` / `YUV_FLIP_VERTICAL (2)` | same 3 | = src | H; V | `*_flip_horizontally` / `*_flip_vertically`, in-place |
| 10 | `yuv_rotate_v1` | `YuvRotateOptionsV1`: `rotationDegrees` ∈ {0, 90, 180, 270}, clockwise | same 3 | 0/180: w×h; 90/270: h×w | 0; 90; 180; 270 | `*_rotate(src, dst, deg)` for 90/180/270. For 0, the 0.2.4 Dart `rotate()` returns `this` without a native call. |
| 11 | `yuv_chroma_swap_v1` | `YuvEffectOptionsV1`: `region` **must be disabled** | NV12→NV12 only | = src | full | `nvXX_to_nvYY(srcVU, dstUV, w, h, stride)`: UV plane only, Y untouched |

A disabled region is `{structSize = sizeof(YuvRegionOptionsV1), abiVersion = 1, left = top = right = bottom = 0,
enabled = 0, reserved0 = 0}`. An enabled region carries the centered ROI with `enabled = 1`. Radius 0 is a
defined no-op that the Dart layer short-circuits, so it is not timed. The valid native radius range is 1…256.

### Scenario matrix

Scenario ID: `<OP>.<SRC>[.<DST>][.<VARIANT>]`. Each row runs on 1080p and 12MP, except that `*.R256` rows run on
1080p only. Result: **85 scenarios at 1080p + 79 at 12MP = 164 ABI v1 rows per full matrix**. Each row is also
measured on 0.2.4 where a counterpart exists; otherwise the 0.2.4 cell is `N/A` with the stated reason.

**Convert: 12 directions (`yuv_convert_v1`)**

| ID | 0.2.4 native | 0.2.4 Dart | 0.4 Dart |
|---|---|---|---|
| `CVT.I420.I420` | none (same-format copy did not exist natively) | `copy()` | `toI420()` |
| `CVT.I420.NV12` | `yuv420_i420_to_nv21(src, dst)` | `toYuvNv21()` on a fresh copy | `toNv12()` |
| `CVT.I420.BGRA` | `yuv420_to_bgra8888(src, out)` | `toBgra8888()` (bytes) | `toBgraBytes()`; also `toBgra()` |
| `CVT.NV12.I420` | `nv21_to_i420(src, dst)` | `toYuvI420()` on a fresh copy | `toI420()` |
| `CVT.NV12.NV12` | none | `copy()` | `toNv12()` |
| `CVT.NV12.BGRA` | `nv21_to_bgra8888(src, out)` | `toBgra8888()` | `toBgraBytes()`; also `toBgra()` |
| `CVT.BGRA.I420` | `bgra8888_to_i420(src, dst)` | `toYuvI420()` on a fresh copy | `toI420()` |
| `CVT.BGRA.NV12` | `bgra8888_to_nv21(src, dst)` | `toYuvNv21()` on a fresh copy | `toNv12()` |
| `CVT.BGRA.BGRA` | none | `copy()` | `toBgra()` |
| `CVT.RGBA.I420` | `yuv420_from_rgba8888(rgba, dst)` | `fromRgba8888(bytes)` on a pre-allocated I420 image | `YuvImage.fromRgbaBytes(…, format: i420)` |
| `CVT.RGBA.NV12` | `nv21_from_rgba8888(rgba, dst)` | `fromRgba8888(bytes)` on a pre-allocated nv21 image | `YuvImage.fromRgbaBytes(…, format: nv12)` |
| `CVT.RGBA.BGRA` | `bgra8888_from_rgba8888(rgba, dst)` | `fromRgba8888(bytes)` on a pre-allocated BGRA image | `YuvImage.fromRgbaBytes(…, format: bgra8888)` |

For same-format rows the 0.2.4 native column is `N/A`. The harness also records a `memcpy` of the active planes
as a floor reference, labelled `ref.memcpy`, never as 0.2.4.

**Geometry**: `<FMT>` ∈ {`I420`, `NV12`, `BGRA`}

| IDs | Count | ABI v1 | 0.2.4 native | 0.2.4 Dart → 0.4 Dart |
|---|---:|---|---|---|
| `FLIP.<FMT>.H`, `FLIP.<FMT>.V` | 6 | `yuv_flip_v1` | `*_flip_horizontally/vertically` (in-place) | `flipHorizontally()`/`flipVertically()` → `applyFlipHorizontal()`/`applyFlipVertical()` |
| `ROT.<FMT>.0/90/180/270` | 12 | `yuv_rotate_v1` | `*_rotate(src, dst, deg)`; `ROT.*.0` = `N/A` (no native path) | `rotate(r)` → `rotated(r)` (new image; for 0 compare with 0.2.4 `copy()`) and `applyRotation(r)` |
| `CROP.<FMT>.EVEN`, `CROP.<FMT>.ODD` | 6 | `yuv_crop_v1` | `*_crop_rect` | `crop(rect)` → `cropped(rect)` / `applyCrop(rect)` |

**Effects**

| IDs | Count | ABI v1 | 0.2.4 native | 0.2.4 Dart → 0.4 Dart |
|---|---:|---|---|---|
| `GRAY.<FMT>.FULL`, `BW.<FMT>.FULL`, `NEG.<FMT>.FULL` | 9 | `yuv_grayscale_v1` / `yuv_black_white_v1` / `yuv_negate_v1`, region disabled | `*_grayscale` / `*_blackwhite` / `*_negate` (in-place) | `grayscale()`/`blackwhite()`/`negate()` → `applyGrayscale()`/`applyBlackWhite()`/`applyNegate()` |
| `GRAY.<FMT>.ROI`, `BW.<FMT>.ROI`, `NEG.<FMT>.ROI` | 9 | same, centered ROI | `N/A`: 0.2.4 effects had no ROI | native only; the public 0.4 effects take no region |
| `SWAP.NV12` | 1 | `yuv_chroma_swap_v1` | `nvXX_to_nvYY` (UV plane only) | `swapNv()` → `applyChromaSwap()` |

**Blur**

| IDs | Count | ABI v1 | 0.2.4 native | 0.2.4 Dart → 0.4 Dart |
|---|---:|---|---|---|
| `BOX.<FMT>.R1`, `BOX.<FMT>.R10` | 6 | `yuv_box_blur_v1`, region disabled | `*_box_blur(src, r, NULL)` | `boxBlur(radius: r)` → `applyBoxBlur(radius: r)` |
| `BOX.<FMT>.R10.ROI` | 3 | centered ROI | `*_box_blur(src, 10, rect)` | `boxBlur(radius: 10, rect: roi)` → `applyBoxBlur(radius: 10, region: roi)` |
| `BOX.<FMT>.R256` (1080p only) | 3 | r = 256 | `*_box_blur(src, 256, NULL)` | as above |
| `MEAN.<FMT>.R1/R10/R10.ROI/R256` | 12 | `yuv_mean_blur_v1`, same variants | `*_mean_blur` | `meanBlur` → `applyMeanBlur` |
| `GAUSS.<FMT>.R2S2`, `GAUSS.<FMT>.R10S10` | 6 | `yuv_gaussian_blur_v1` | `yuv420_gaussblur` (int σ) / `nv21_gaussian_blur` / `bgra8888_gaussian_blur` | `gaussianBlur(radius, sigma)` → `applyGaussianBlur(radius:, sigma:)` |

Parameter rationale: r = 10 and (10, 10) reproduce the regression evidence in `todo.md`. (2, 2) is the
public Gaussian default. r = 1 is the smallest kernel. r = 256 is the ABI v1 maximum and exercises the
radius-independence claim of PERF-25/26. Gaussian has no ROI row, because neither the public 0.4 API nor 0.2.4
offers a Gaussian region.

Row count per size: convert 12 + flip 6 + rotate 12 + crop 6 + effects 18 + chroma swap 1 + blur 30 = **85**.

### Legacy 0.2.4 descriptor mapping

0.2.4 takes `YUVDef {y, u, v, width, height, yRowStride, yPixelStride, uvRowStride, uvPixelStride}` (all `int`).
The bench fills it exactly as the 0.2.4 Dart `YUVDefClass` did, pointing at copies of the same input bytes:

| Format | `y` | `u` | `v` | `yRowStride / yPixelStride` | `uvRowStride / uvPixelStride` |
|---|---|---|---|---|---|
| I420 | Y | U | V | `w / 1` | `cw / 1`. The 0.2.4 Dart default was a gapped `uvPixelStride = 2`; the tight value is used here so the bytes match ABI v1. The legacy kernels index through `yuv_index(x, y, rowStride, pixelStride)`. |
| nv21 (= NV12 bytes, UV order) | Y | UV plane | `NULL` (checked: the 0.2.4 `nv21_*` kernels read the interleaved plane through `src->u` only) | `w / 1` | `2·cw / 2` |
| BGRA | pixels | `NULL` | `NULL` | `4w / 4` | `1 / 1` (unused) |

Conversions that write packed BGRA (`yuv420_to_bgra8888`, `nv21_to_bgra8888`) write a tight `w·h·4` buffer.
`from_rgba8888` reads a tight RGBA buffer. The legacy name `nv21` holds UV-ordered bytes, so the NV12 input
buffer feeds it unchanged.

### Semantics that differ from 0.2.4

These are flagged, **not excluded**, per the tracker rule. Correctness is always judged against the ABI v1
reference, never against 0.2.4 bytes.

- 0.2.4 effects, flips and blurs mutate `src` in place. ABI v1 is out-of-place with a const source.
- ABI v1 effects and blurs work in BT.601 RGB space (decode → op → re-encode, clipped 2×2 chroma averaging).
  0.2.4 worked per stored plane. Output checksums therefore differ by design.
- Blur borders: ABI v1 uses edge-replicate with a full `(2r+1)²` divisor, and mean ≡ box. In 0.2.4 box used a
  sliding-window sum while mean and Gaussian had their own paths.
- `ROT.*.0` and same-format convert copy in ABI v1. In 0.2.4 they were a Dart no-op or `copy()`.
- `SWAP.NV12`: ABI v1 also copies Y into the destination. 0.2.4 rewrote only the UV plane.
- Odd geometry: 0.2.4 is not defined on it, so odd-size inputs are ABI v1 only.

## Measurement methodology

### What is timed

- **C-kernel level (primary, all rows):** one call of the entry point. The clock is `QueryPerformanceCounter`.
  The timed region covers the call only.
- **Public Dart level (every row with a Dart column):** one public call in an AOT release build
  (`Stopwatch`, which is backed by QPC on Windows). This includes marshalling, staging, native call and
  copy-back. It covers PERF-28…31, which change only the Dart/FFI path.
- The following are **not** timed: input generation, the restore step, destination pre-fill, and checksumming.

### Per-iteration protocol (identical for both versions)

1. **Restore:** `memcpy` the pristine input into the working source buffers. 0.2.4 mutates in place, and ABI v1
   gets the same copy so that cache state is equal.
2. **Pre-fill** every destination byte, including any padding, with `0xCD`. For 0.2.4 in-place rows the
   destination is the source.
3. Timed call.
4. Check the status: ABI v1 must return `YUV_STATUS_OK`, and any other status fails the row as
   `ERROR:<code>`. 0.2.4 returns `void`.
5. Checksum on the first measured iteration and the last one. The two must be identical, or the row is
   `ERROR:nondeterministic`.

For Dart rows, each iteration gets a fresh image built from the pristine bytes outside the timer: `apply*`
and the 0.2.4 in-place methods mutate their receiver. Nothing is allocated inside the timed region beyond what
the call itself allocates. As with C, each Dart scenario runs in its own process.

### Warm-up and repetitions (adaptive, fixed rule)

Iteration 1 is a calibration run with time `t1`. It always counts as warm-up.

| `t1` | Extra warm-up runs | Measured runs N | Upper statistic |
|---|---:|---:|---|
| < 5 ms | 10 | 50 | p95 |
| 5 – 100 ms | 5 | 30 | p95 |
| 100 ms – 2 s | 2 | 15 | max |
| 2 – 30 s | 1 | 5 | max |
| 30 – 120 s | 0 | 3 | max |
| > 120 s | — | 0 | row = `TIMEOUT(>120 s)`, `t1` recorded as a lower bound |

The rule is applied per version and per row. The 120 s watchdog runs in the driver: each scenario is one child
process, killed on timeout. Some current ABI v1 rows (e.g. `BOX/MEAN/GAUSS` at 12MP, and `*.R256` in general)
are expected to be very slow or to time out. A `TIMEOUT` is an honest "before" value. **Never extrapolate a
time.**

### Metrics per row

- Report `min`, **median** (primary), `p95` (nearest rank: the `ceil(0.95·N)`-th sorted sample) for N ≥ 20, or
  `max` for N < 20 (labelled as such), `mean`, `stdev`, and the relative spread
  `(p95|max − median) / median`.
- **Raw samples** of every measured iteration, in ms with 4 decimals, are stored with the row. The tracker
  requires raw timings.
- Ratio `= median(ABI v1) / median(0.2.4)`. For PERF cards also `median(after) / median(before)`.
- Proposed decision rule, subject to T1 acceptance: a row is **comparable** when the per-round ratio ≤ 1.10
  in at least 2 of 3 interleaved rounds, and **behind** when the ratio > 1.10 in all 3 rounds. Anything else
  is re-measured with another 3 rounds before a verdict.

### Checksum

- SHA-256 over the destination **active samples**, packed tight in plane order (Y‖U‖V, Y‖UV, BGRA),
  excluding row/pixel padding. With the tight layout this equals the full destination buffers. In C use
  Windows CNG (`BCryptHash`, `bcrypt.lib`); in Dart use `package:crypto`, which is already a dev dependency.
- ABI v1 checksums must be **identical across all measurements of the same row**: MEAS-01, before/after of
  every PERF card, PERF-34. Any change breaks byte-exactness and blocks acceptance.
- 0.2.4 checksums are recorded for reproducibility only. They are expected to differ from ABI v1.
- A padding canary check (all `0xCD` outside active samples) is part of the correctness tests, not of the
  timed matrix.

### Run environment controls

- AC power. Record the power plan with `powercfg /getactivescheme`, and use "High performance" or better.
- Close other heavy applications. Do not run builds, indexing or Flutter tooling in parallel.
- Run each child process at high priority, pinned to a single **P-core** logical CPU:
  `cmd /c start "" /wait /high /affinity 4 <exe> <args>`. Mask `0x4` is logical CPU 2. On Raptor Lake the
  P-cores enumerate first; confirm with Sysinternals Coreinfo and record the mask used. Both versions are
  single-threaded, so one core is representative and avoids P/E-core migration noise.
- **Interleave** the versions: for every row, run `0.2.4` then `ABI v1` (or `before` then `after`), for 3
  rounds over the whole matrix. Report the pooled statistics and the per-round medians, which expose thermal
  drift.
- Record the wall-clock start and end of each round.

### Result record (CSV, one line per version × row × round)

`platform, machine, round, version, sha, src_tree_id, scenario_id, op, src_fmt, dst_fmt, width, height, params,
layout, level(c|dart), status(OK|N/A|UNSUPPORTED|TIMEOUT|ERROR:<x>), reason, warmup, n, min_ms, median_ms,
p95_or_max_ms, upper_kind(p95|max), mean_ms, stdev_ms, spread, checksum_sha256, raw_ms(semicolon-separated),
started_at, finished_at, compiler, flags, power_plan, affinity`

## Commands to run

### Flutter/Dart tests

The native-backed Dart tests load `yuv_ffi.dll` by name (`lib/src/loader/impl/loader_io.dart`). The Windows
search order puts the **current directory before `PATH`**, so a `yuv_ffi.dll` in the repository root wins. On
2026-09-25 the root contains a gitignored `yuv_ffi.dll` (20 480 bytes, 2026-09-24 23:21) whose provenance is
unknown. It exports the 11 symbols but differs from the 35c516e Release build (27 136 bytes). Before any test
or Dart bench, replace it with the build under test and record its SHA-256:

```powershell
Set-Location $Repo
Copy-Item "$B\abi_v1\build\Release\yuv_ffi.dll" "$Repo\yuv_ffi.dll" -Force   # gitignored build output
Get-FileHash "$Repo\yuv_ffi.dll"
flutter test                                                                   # full suite (639 tests at 35c516e)
# Focused suites for PERF cards (reference oracle + ABI contract + safety):
flutter test test/reference_native_conversions_test.dart test/io_abi_v1_public_contract_test.dart `
             test/conversions_test.dart test/nv_chroma_order_test.dart `
             test/planar_box_mean_blur_contract_test.dart test/bgra_mean_blur_contract_test.dart `
             test/native_stride_safety_test.dart test/native_allocation_safety_test.dart
```

`flutter test` runs in the JIT VM. It is a **correctness** gate, never a timing source.

### Native C tests (CTest)

Verified on 2026-09-25: 11/11 passed in Release at `35c516e`. `BUILD_TESTING=ON` goes on the **root**
`CMakeLists.txt`, otherwise CTest reports "No tests were found".

```powershell
& "$CMakeBin\cmake.exe" -S "$B\abi_v1" -B "$B\abi_v1\build_tests" -G "Visual Studio 17 2022" -A x64 -DBUILD_TESTING=ON
& "$CMakeBin\cmake.exe" --build "$B\abi_v1\build_tests" --config Release
& "$CMakeBin\ctest.exe" --test-dir "$B\abi_v1\build_tests" -C Release --output-on-failure
```

On Windows the tests run without sanitizers, because ASan/UBSan/LSan are Linux/macOS only. 0.2.4 has no
native tests.

### Native C benchmarks

**To be created by MEAS-01.** The harness source is not part of PERF-01. Proposed layout:
`tool/bench/native/` in the repo, which needs the usual approval for edits outside `lib/`. The harness is
**not** copied into the extracted 0.2.4 tree.

- `gen_inputs.c`: the generator above, plus hash verification against the checksum table.
- `bench_main.c`: CLI, iteration protocol, QPC timing, statistics, CSV, and SHA-256 via CNG.
- `backend_abi_v1.c` and `backend_v024.c`: one `run(scenario, bufs)` adapter per version. The 0.2.4 adapter
  declares the legacy prototypes itself and fills `YUVDef` as in the mapping table.
- `CMakeLists.txt`: `-DYUV_BENCH_BACKEND=abi_v1|v024 -DYUV_SRC_DIR=<extracted src>`. It builds the library from
  `YUV_SRC_DIR` via `add_subdirectory`, so the library gets exactly the Release flags above, and links the
  harness against it. The harness executable gets the same `/O2 /Ob2 /MD /DNDEBUG`.

Intended usage:

```powershell
foreach ($v in 'v024', 'abi_v1') {
  & "$CMakeBin\cmake.exe" -S "$Repo\tool\bench\native" -B "$B\bench_$v" -G "Visual Studio 17 2022" -A x64 `
      -DYUV_BENCH_BACKEND=$v -DYUV_SRC_DIR="$B\$v\src"
  & "$CMakeBin\cmake.exe" --build "$B\bench_$v" --config Release
}
# one scenario, one process, pinned to a P-core, high priority:
cmd /c start "" /wait /high /affinity 4 "$B\bench_abi_v1\Release\yuv_bench.exe" `
    --scenario CVT.I420.BGRA --size 1920x1080 --level c --round 1 --out "$B\results\meas01_windows.csv"
```

The driver (`tool/bench/native/run_matrix.ps1`, to be created) loops over rounds 1..3 × every scenario ×
{v024, abi_v1}, enforces the 120 s watchdog, and appends to one CSV. The executable and its `yuv_ffi.dll` sit
in the same directory. The application directory comes first in the DLL search order, so each version loads
its own library.

The 2026-09-25 regression evidence came from single-shot, un-warmed runs of an earlier ad-hoc harness (content
`k·31`, not the seeded generator). Those numbers are hypotheses only and are not a baseline.

### Public Dart benchmarks (AOT release)

**To be created by MEAS-01.** Use a throwaway Flutter Windows app **outside the repository**. Two entry files
cover the two APIs. The app depends on each version through a path dependency on a worktree, so no example app
or dependency set of either version is changed:

```powershell
git -C $Repo worktree add --detach "$B\wt-v024"   0.2.4
git -C $Repo worktree add --detach "$B\wt-abi_v1" $AbiSha
flutter create --platforms=windows --project-name yuv_bench "$B\dart_bench"
# pubspec: dependencies: yuv_ffi: { path: <$B\wt-v024 or $B\wt-abi_v1> }, crypto
# lib/bench_v024.dart / lib/bench_abi_v1.dart: same generator, protocol and CSV as the C harness
Set-Location "$B\dart_bench"
flutter build windows --release -t lib/bench_abi_v1.dart
cmd /c start "" /wait /high /affinity 4 "$B\dart_bench\build\windows\x64\runner\Release\yuv_bench.exe" `
    --scenario CVT.I420.BGRA --size 1920x1080 --round 1 --out "$B\results\meas01_windows.csv"
```

The Windows runner passes command-line arguments to `main(List<String> args)`. The bench writes the CSV
itself and ends with `exit(0)`: do not rely on console output or on `flutter run` / `flutter drive` exit
codes. Switching the version means changing the path dependency, running `flutter pub get`, and rebuilding.
Afterwards clean up with `git -C $Repo worktree remove "$B\wt-v024"` (and the same for `wt-abi_v1`).

### How to switch to 0.2.4

Preferred: **do not switch the main working tree.** Use `git archive` (native) or `git worktree` (Dart), as
above. Both leave `release/0.4.2` and its uncommitted changes untouched.

Only with a **clean** working tree (`git status --porcelain` prints nothing), a plain checkout is acceptable:

```powershell
git -C $Repo switch --detach 0.2.4
# ... build/measure ...
git -C $Repo switch release/0.4.2
```

Never stash, reset or discard uncommitted changes you did not make just to switch versions. On 2026-09-25 the
tree is **not** clean, so the checkout route is not available.

### Other platforms (pointers for MEAS-02/03)

- Pixel 3: build the release APK locally and install over the existing app with `adb -s <serial> install -r
  <apk>`. Never uninstall or clear data. Use the same generator, checksums, scenario IDs and CSV. Record the
  device temperature at the start and end of each round.
- Web: build the WASM with `bash ./tool/wasm/build_wasm.sh` at each SHA and record the SHA-256 of
  `assets/wasm/yuv_ffi.{js,wasm}`. Run in the Mac runner's Chrome. For the timer use `performance.now()` through
  `Stopwatch`. A row that is not exported is `UNSUPPORTED` together with the call result, and never gets a
  time. 0.2.4 Web availability is recorded per row.
