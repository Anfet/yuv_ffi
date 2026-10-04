# Web/WASM parity assessment

Assessment of the Web backend at `7446a72` (base `8c3d88d`). The Web backend is a partial WASM implementation; results below describe the checked cases and public paths, not all possible inputs.

## Operation and format inventory

The capability surface contains 12 `YuvOperation` values. The table counts meaningful operation/source-format pairs; conversion has an explicit source/destination pair, while other operations preserve their source format.

| Operation | Native | Web/WASM | Meaningful pairs | Probe / focused coverage |
| --- | --- | --- | ---: | --- |
| `convert` | I420, NV12, BGRA8888 to each of the three formats | Same | 9 | 1188-case probe; Web reference conversions (119 cases) |
| `blackWhite`, `grayscale`, `negate` | I420, NV12, BGRA8888 | Same | 9 | 1188-case probe |
| `gaussianBlur`, `meanBlur`, `boxBlur` | I420, NV12, BGRA8888 | Same | 9 | 1188-case probe |
| `crop`, `flipHorizontal`, `flipVertical`, `rotate` | I420, NV12, BGRA8888 | Same | 12 | 1188-case probe; Web odd-size transform coverage |
| `chromaSwap` | NV12 only | NV12 only | 3 source-format checks; 1 supported | Web NV chroma and edge-case tests |
| **Total** |  |  | **42** | **40 supported; 2 unsupported** |

The two unsupported pairs are `chromaSwap` with I420 and BGRA8888. The other 40 meaningful pairs are supported when the loaded WASM module exports the required ABI symbol. The Web initializer derives capabilities from actual module exports; the browser tests exercise a complete export manifest and deliberately incomplete manifests. RGBA8888 is an input to `convert`/`applyRgbaBytes`, not a stored pixel format and therefore is outside the table's stored-format denominator.

The common probe is **22 operation scenarios × 3 stored formats × 6 dimensions × 3 plane layouts = 1,188 cases**. Its full selector scope is `ops=all formats=all`; Chrome and native completed the same golden-backed matrix with zero mismatches. The separate Web reference conversion matrix contains **119** cases and also passed. It is an independent conversion oracle, not an alternative count for the common probe.

## Other public paths

| Public path | Native evidence | Web evidence | Assessment |
| --- | --- | --- | --- |
| Construction, plane metadata, `copy`, `applyPlanes`, packed/padded layouts | Factory, plane-layout, and ownership tests | Padded BGRA, plane-layout, ownership regression, and edge-case integration tests | Checked; layout cases also occur in the 1,188-case matrix where selected |
| `toI420`, `toNv12`, `toBgra`, `toBgraBytes`, `toBytes` | Common probe and conversion tests | Common probe, reference conversions, get-bytes and ownership tests | Checked by their respective cases; no unsupported format pair found |
| `applyPatch` | `test/yuv_image_patch_test.dart`: all three formats, interior and odd right/bottom edge, padding, invalid input with bytes/revision unchanged | Added browser regression at odd lower-right edge for all formats; invalid BGRA insertion leaves bytes and revision unchanged | Matching contract checks pass on Web and native |
| `YuvFrameGeometry.apply` (crop, orientation, mirror) | `test/yuv_frame_geometry_test.dart` and native presenter/camera geometry checks | Added odd 5×3 case with `cover`, crop to the visible area, 90° rotation and mirror; output bytes match the equivalent transforms | Same odd-frame contract checked on Web and native |
| Serialization (`encodeTo`, `decode`) | Serialization and encode/decode tests | Web serialization contract integration test | Checked |
| `toImage` and widget/presenter display | Native image/widget/presenter tests | Flutter UI integration and shader tests | Runtime/display path checked in Chrome; not part of the 1,188 pixel-operation cases |
| Capability initialization and WASM symbol dispatch | ABI manifest and capability wiring tests | Real-browser capability/loader tests plus ABI descriptor staging | Checked; missing symbols are reported as unsupported capabilities |

`YuvCapabilities` covers the 12 ABI operations, not constructors, storage/layout access, serialization, patch insertion, or display geometry. Those paths need their own contract tests; they must not be counted as extra cases in the operation matrix.

## Browser and build smoke results

| Target | Result | Evidence / limit |
| --- | --- | --- |
| Chrome JavaScript build and runtime | **PASS** | `web.ps1`, Chrome 154.0.8037.98; 14 integration sources, 63 registered integration cases, 1,188 common-probe cases, and 119 reference cases passed. |
| Safari | **NOT RUN** | Mac has Safari 18.6 on macOS 15.6.1. `safaridriver` reports that “Allow remote automation” is disabled. Enabling it with `/usr/bin/safaridriver --enable` failed because the non-interactive Mac account could not authenticate its sudo request. This is an access limitation, not a Web failure. |
| Firefox | **NOT AVAILABLE** | Firefox and `geckodriver` are not installed on the available Mac; no Firefox result is inferred from Chrome. |
| `--wasm` | **BUILD PASS; RUNTIME FAIL** | Flutter 3.44.9 built `example/build/web` on macOS 15.6.1. `flutter drive --wasm` on Chrome 154.0.8037.95 loaded the app and backend, then failed on the first RGBA conversion: `yuv_convert_v1 returned JSValue instead of a YuvStatus number`. |

README currently says to use the JavaScript build and describes `--wasm` as unsupported. The runtime failure confirms this limitation, so the README remains unchanged.

## Release recommendations

| Finding | Impact | Recommendation |
| --- | --- | --- |
| No mismatches in the checked 1,188 common-probe cases or 119 reference conversions | No confirmed data discrepancy in the tested operation/format/layout sample | Keep the existing golden; do not generalize the sample result to all image sizes or inputs. |
| Web patch insertion and odd-frame rotation/mirror now have direct browser contract coverage, matching existing native contract checks | Closes a test-coverage gap; no implementation difference observed | Keep these tests in 0.5.0. |
| Safari and Firefox runtime behavior remains unknown; `--wasm` fails at the first ABI conversion call | Browser compatibility beyond tested Chrome is not evidenced; current Flutter-WASM FFI dispatch does not return the expected status value | Keep the README's `--wasm` limitation. Schedule Safari/Firefox smokes when automation/browser access is available; do not claim parity for those targets from Chrome. |

The sampled results do not establish complete native/Web parity. No implementation change is recommended from this assessment alone; any newly reproduced difference should get its own implementation card and golden-backed regression.
