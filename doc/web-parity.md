# Web/WASM parity assessment

Assessment of the Web backend at `7446a72` (base `8c3d88d`), with the review-requested checks rerun after `13419f8`. The Web backend is a partial WASM implementation; results below describe the checked cases and public paths, not all possible inputs.

## Operation and format inventory

The capability surface contains 12 `YuvOperation` values. The table counts meaningful operation/source-format pairs; conversion has an explicit source/destination pair, while other operations preserve their source format.

| Operation | Native | Web/WASM | Meaningful pairs | Status | Probe / focused coverage |
| --- | --- | --- | ---: | --- | --- |
| `convert` | I420, NV12, BGRA8888 to each of the three formats | Same | 9 | Same: 9 | 1188-case probe; Web reference conversions (119 cases) |
| `blackWhite`, `grayscale`, `negate` | I420, NV12, BGRA8888 | Same | 9 | Same: 9 | 1188-case probe |
| `gaussianBlur`, `meanBlur`, `boxBlur` | I420, NV12, BGRA8888 | Same | 9 | Same: 9 | 1188-case probe |
| `crop`, `flipHorizontal`, `flipVertical`, `rotate` | I420, NV12, BGRA8888 | Same | 12 | Same: 12 | 1188-case probe; Web odd-size transform coverage |
| `chromaSwap` | NV12 only | NV12 only | 3 source-format checks; 1 supported | Same: 1; unsupported: 2 | Web NV chroma and edge-case tests |
| **Total** |  |  | **42** | **Same: 40; differs: 0; unsupported: 2; untested: 0** | |

The two unsupported pairs are `chromaSwap` with I420 and BGRA8888. The other 40 meaningful pairs are supported when the loaded WASM module exports the required ABI symbol. The Web initializer derives capabilities from actual module exports; the browser tests exercise a complete export manifest and deliberately incomplete manifests. RGBA8888 is an input to `convert`/`applyRgbaBytes`, not a stored pixel format and therefore is outside the table's stored-format denominator.

The common probe is **22 operation scenarios × 3 stored formats × 6 dimensions × 3 plane layouts = 1,188 cases**. Its full selector scope is `ops=all formats=all`; Chrome and native completed the same golden-backed matrix with zero mismatches. The separate Web reference conversion matrix contains **119** cases and also passed. It is an independent conversion oracle, not an alternative count for the common probe.

## Other public paths

| Public path | Native evidence | Web evidence | Assessment |
| --- | --- | --- | --- |
| Construction, plane metadata, `copy`, `applyPlanes`, packed/padded layouts | Factory, plane-layout, and ownership tests | Padded BGRA, plane-layout, ownership regression, and edge-case integration tests | Checked; layout cases also occur in the 1,188-case matrix where selected |
| `toI420`, `toNv12`, `toBgra`, `toBgraBytes`, `toBytes` | Common probe and conversion tests | Common probe, reference conversions, get-bytes and ownership tests | Checked by their respective cases; no unsupported format pair found |
| `applyPatch` | `test/yuv_image_patch_test.dart`: all three formats, interior and odd right/bottom edge, padding, invalid input with bytes/revision unchanged | Dedicated browser test checks every output byte for BGRA insertion inside and at the lower-right edge, fragment preservation, and atomic I420 rejection at odd x | Matching contract checks pass on Web and native |
| `YuvFrameGeometry.apply` (crop, orientation, mirror) | `test/yuv_frame_geometry_test.dart`: explicit visible rect on 5×3, exact output bytes for I420 and BGRA | Same input, visible rect, orientation and expected bytes in dedicated browser test | Exact output bytes match on Web and native |
| Serialization (`encodeTo`, `decode`) | Serialization and encode/decode tests | Web serialization contract integration test | Checked |
| `toImage` and widget/presenter display | Native image/widget/presenter tests | Flutter UI integration and shader tests | Runtime/display path checked in Chrome; not part of the 1,188 pixel-operation cases |
| Capability initialization and WASM symbol dispatch | ABI manifest and capability wiring tests | Real-browser capability/loader tests plus ABI descriptor staging | Checked; missing symbols are reported as unsupported capabilities |

`YuvCapabilities` covers the 12 ABI operations, not constructors, storage/layout access, serialization, patch insertion, or display geometry. Those paths need their own contract tests; they must not be counted as extra cases in the operation matrix.

`applyPatch` (`lib/src/yuv/shared/yuv_patch.dart`) and `YuvFrameGeometry.apply` (`lib/src/geometry/yuv_frame_geometry.dart`) are shared Dart code on both platforms. Their underlying crop/rotation operations are in the golden-backed probe, including odd sizes 3×5, 33×17, and 127×255 across formats and layouts. This lowers the risk of backend divergence for these high-level paths; it does not replace direct contract checks for their patch placement and visible-rect behavior.

## Consolidated decision counts

Statuses distinguish matching evidence, confirmed differences, unsupported inputs/targets, and cases not run. A match describes the listed test evidence only, not every possible input.

| Inventory / target | Total | Same / PASS | Differs / fails | Unsupported | Untested | Evidence |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Operation/source-format pairs | 42 | 40 | 0 | 2 | 0 | Capability inventory and common probe; 1,188 cases plus 119 separate reference conversions |
| Other public paths listed above | 7 | 7 | 0 | 0 | 0 | Native and Chrome contract tests; geometry byte-for-byte case and patch checks |
| Browser/build targets | 4 | 1 | 0 | 1 | 2 | Chrome JavaScript PASS; `--wasm` unsupported at runtime; Safari and Firefox untested |

## Browser and build smoke results

| Target | Result | Evidence / limit |
| --- | --- | --- |
| Chrome JavaScript build and runtime | **PASS** | Chrome 154.0.8037.98; the aggregated `all_web_test.dart`, 119-case reference target, and camera smoke passed through `tool/ci/drive.ps1`. `web_ownership_regression_web_test.dart` is now 4 cases; total source baseline is 64. |
| Safari | **NOT RUN** | Mac has Safari 18.6 on macOS 15.6.1. `safaridriver` reports that “Allow remote automation” is disabled. Enabling it with `/usr/bin/safaridriver --enable` failed because the non-interactive Mac account could not authenticate its sudo request. This is an access limitation, not a Web failure. |
| Firefox | **NOT AVAILABLE** | Firefox and `geckodriver` are not installed on the available Mac; no Firefox result is inferred from Chrome. |
| `--wasm` | **BUILD PASS; RUNTIME FAIL** | Flutter 3.44.9 built the app on Windows and macOS. Chrome 154.0.8037.98's wrapped probe drive reported `ERR StateError` for WASM operation calls; the earlier Mac run reported `yuv_convert_v1 returned JSValue instead of a YuvStatus number`. Both fail after app/module startup at the operation call. |

The rework Flutter-WASM smoke used these commands from the repository root:

```powershell
Push-Location example
flutter build web --wasm
Pop-Location
pwsh -File tool/ci/drive.ps1 integration_test/probe_web_test.dart web-server --browser-name=chrome --headless --wasm
```

Recorded runtime failure:

```text
got ERR StateError
flutter drive failed for integration_test/probe_web_test.dart on web-server with exit code 1
```

README currently says to use the JavaScript build and describes `--wasm` as unsupported. The runtime failure confirms this limitation, so the README remains unchanged.

## Release recommendations

| Finding | Impact | Recommendation |
| --- | --- | --- |
| No mismatches in the checked 1,188 common-probe cases or 119 reference conversions | No confirmed data discrepancy in the tested operation/format/layout sample | Keep the existing golden; do not generalize the sample result to all image sizes or inputs. |
| Web patch insertion and odd-frame rotation/mirror now have direct browser contract coverage, matching native expected bytes | Closes a test-coverage gap; no implementation difference observed in the checked scenarios | Keep these tests in 0.5.0. |
| Safari and Firefox runtime behavior remains unknown; `--wasm` fails at the first ABI conversion call | Browser compatibility beyond tested Chrome is not evidenced; current Flutter-WASM FFI dispatch does not return the expected status value | Keep the README's `--wasm` limitation. Schedule Safari/Firefox smokes when automation/browser access is available; do not claim parity for those targets from Chrome. |

The sampled results do not establish complete native/Web parity. No implementation change is recommended from this assessment alone; any newly reproduced difference should get its own implementation card and golden-backed regression.

## Rework verification after `13419f8`

- Native: `flutter test test/yuv_frame_geometry_test.dart` passed 14/14; `flutter test test/yuv_image_patch_test.dart` passed 10/10; `pwsh -File tool/ci/windows.ps1` passed, including native probe/reference and Windows integration targets.
- Chrome JavaScript on commit `bc7936026e7a3093dff3092395ac01d7d49deb23`: `pwsh -File tool/ci/web.ps1` passed on Chrome 154.0.8037.98 with 14 sources, 64 integration cases, the 119-case reference matrix, and camera smoke. The dedicated ownership regression and all mapped Web targets passed.
- Flutter-WASM build: from `example/`, `flutter build web --wasm` passed on Flutter 3.44.9.
- Flutter-WASM runtime: `pwsh -File tool/ci/drive.ps1 integration_test/probe_web_test.dart web-server --browser-name=chrome --headless --wasm` failed inside the probe with `got ERR StateError` for the WASM operation calls. The app and WASM module loaded; the operation-call stage failed. This is an unsupported runtime target, not a JavaScript-backend mismatch.
- New geometry contract case uses a 5×3 input, explicitly asserts visible rect `(0,0,5,3)`, then compares fixed output byte arrays for I420 and BGRA against the same case in native and Web tests. Chroma values in this odd-sized I420 rotation are asserted as the ABI-produced bytes, not inferred from source-plane transposition.
