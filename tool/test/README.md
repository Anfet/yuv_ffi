# Selecting checks

Commands below run from the package root unless stated otherwise. These are local
slices; the complete release checks in `AGENTS.md` remain mandatory.

## VM runner

```powershell
pwsh -File tool/ci/vm.ps1 -Group codec -List
pwsh -File tool/ci/vm.ps1 -Group codec
pwsh -File tool/ci/vm.ps1 -Group state
pwsh -File tool/ci/vm.ps1 -Group pixel-format
pwsh -File tool/ci/vm.ps1 -Group presenter
pwsh -File tool/ci/vm.ps1 -TestPath test/yuv_image_state_contract_test.dart -Name 'toBytes contract'
```

| Group | File | Preparation |
| --- | --- | --- |
| codec | `test/yuv_serialization_test.dart` | pub get; no DLL |
| state | `test/yuv_image_state_contract_test.dart` | pub get; native build and DLL search path |
| pixel-format | `test/yuv_pixel_format_test.dart` | pub get; native build and DLL search path |
| presenter | `test/yuv_frame_presenter_test.dart` | pub get; native build and DLL search path |

`TestPath` accepts an array of existing `*_test.dart` files beneath `test/`.
It rejects parent traversal and reparse points. `Group` and `TestPath` are mutually
exclusive. `Name` is Flutter's regular expression filter, additional to the file
selection (or the default tags). Unknown groups, empty arrays and missing files
fail before setup. No matching name, loading only, or skipped tests only fail.
The JSON reporter requires a completed successful run with at least one executed,
successful test. `List` prints selection/preparation without pub, build or test.

Without selectors the runner still performs pub get, analysis of `lib test`,
one native build and the complete `smoke || contract` selection. Selectors omit
unrelated analysis; multiple selected files share one preparation within the call.
The existing native helper configures/builds Release DLLs; Flutter tests run Debug.
The runner does not infer a reusable build cache from a path name.

## Native, browser and device targets

Native CTest can select an existing C test by its registered name. Configure/build
once with the desired compiler/configuration in a scratch directory, then select:

```powershell
cmake -S . -B Z:/.ai/claude-work/yuv/ctest-debug -DBUILD_TESTING=ON
cmake --build Z:/.ai/claude-work/yuv/ctest-debug --config Debug
ctest --test-dir Z:/.ai/claude-work/yuv/ctest-debug -C Debug -R '^abi_layout_tests$' --output-on-failure
```

Other names include `checked_arithmetic_tests`, `validated_view_tests`,
`abi_status_tests`, `abi_short_descriptor_tests`, `abi_transform_tests`,
`abi_convert_tests`, `abi_effect_tests`, `abi_blur_tests`, `abi_sanitizer_tests`.
Compiler/platform guards still apply; a filtered run does not replace full CTest.

VM probe selection uses the prepared DLL environment (the runner supplies it):

```powershell
$env:PROBE_OPS='gray'
$env:PROBE_FORMATS='i420'
pwsh -File tool/ci/vm.ps1 -TestPath test/probe/probe_correctness_test.dart
Remove-Item Env:PROBE_OPS
Remove-Item Env:PROBE_FORMATS
```

For browser targets, prepare example dependencies and WASM assets as described in
`doc/validation.md`, start a matching ChromeDriver, and use the checked drive
wrapper. It runs from `example/`; target paths are relative to that directory.

```powershell
pwsh -File tool/ci/drive.ps1 integration_test/probe_web_test.dart web-server --browser-name=chrome --headless --dart-define=PROBE_OPS=gray --dart-define=PROBE_FORMATS=i420
pwsh -File tool/ci/drive.ps1 integration_test/probe_web_test.dart web-server --browser-name=chrome --headless --wasm --dart-define=PROBE_OPS=gray --dart-define=PROBE_FORMATS=i420
```

JavaScript and Flutter `--wasm` are separate results. Full `web.ps1`/`web.sh` run
the probe once per mode through `all_web_test.dart`; standalone probe remains a
targeted entry point. There is no separate isolation assertion in the probe.
Loader lifecycle/bootstrap and shader targets retain their separate execution.
The wrapper requires exit 0 and `All tests passed`.

For a device correctness target, use the same wrapper and a connected, unlocked
physical device, with example dependencies/native plugin prepared. For example:

```powershell
pwsh -File tool/ci/drive.ps1 integration_test/probe_native_test.dart 8B1X11QLW --dart-define=PROBE_OPS=gray --dart-define=PROBE_FORMATS=i420
```

Release benchmarks use the existing `tool/probe/run_android.ps1`, a clean committed
candidate, Pixel 3, and its provenance/install guards. Profile measurements are
diagnostic and do not establish Release/AOT performance. No device scripts or
RA26 fields changed.

## Inventory dispositions (SPLIT 1)

| Before | After / retained contract |
| --- | --- |
| Pixel format nv12-vs-nv12 comparison and legacy-labelled format case | Removed identical-entry comparisons. Stable IDs, public format switch and allocate-vs-named-factory remain in `yuv_pixel_format_test.dart`. |
| Web nv12-vs-nv12 comparison | Removed second identical image; hand-written U=37/V=219, UV byte positions and lossy BGRA round-trip remain in `nv_chroma_order_web_test.dart`. |
| VM `toBytes` cases in conversions plus weak length/snapshot cases in state | Consolidated in `yuv_image_state_contract_test.dart`: all formats, 1x1/3x3/127x255/512x512, explicit per-plane patterns, exact concatenation/length and independence in both directions; I420 3x3 remains exactly 17 bytes. Native conversions stay in `conversions_test.dart`. |
| Seven VM placeholder successes in `test/web/` | Explicit skips. Six suites use real `YuvFfi.initialize`; `wasm_loader_initialization_test.dart` uses the counted initializer seam. Browser branches remain intact. |
| Web edge-case padded BGRA expectations | Default packed: stride 8 / 16 bytes; explicit preserve and deep copy: stride 16 / 32 bytes; allocate: tight stride 8 / 16 zero bytes. Product API unchanged. |
| Repeated standalone WASM probe plus aggregate | Removed standalone invocation only from both full WASM script lists; aggregate import/call and standalone target remain. JS source mapping and case baseline remain unchanged. |
| `example/integration_test/probe_performance_test.dart` | Keep diagnostic profile entry point, structured records and workload selection. Current Android runner builds the separate Release benchmark; no main platform script invokes this old profile target. |
| `example/integration_test/web_matrix_abort_test.dart` | Keep diagnostic isolated/predecessor conversion boundary and console markers. No current platform script calls it; conversion matrices cover results, not its boundary diagnostics. |
| `android_release_benchmark_contract_test.dart` source-string assertions | Keep, including syntax assertions: no ready behavioral replacement for host parsing/integrity is established here. Release/provenance/install guards remain. |
| Camera lifecycle/menu/desktop diagnostics candidates | Outside this repository's card: SPLIT 2 / TEST 1 own the decisions. |
| Probe mirrors, ABI/aliasing/cleanup/races/source compatibility | Keep: copies are checked by `probe_copy_sync_test.dart`; distinct contracts are not duplicate executions. |

The seven root Web suites are not imported wholesale by the integration aggregate.
Integration targets independently cover getbytes, padded constructors, chroma,
ownership, loader lifecycle, conversion matrices and parity edges. This mapping
does not claim equivalent coverage of every root browser assertion. Asset-dependent
root suites cannot simply run with `flutter test --platform chrome` (no asset
bundle); their skips are never Web evidence. Changed Web behavior is pending the
CHECK 20 JavaScript/`--wasm` runs, not a VM PASS. Native CTest and device runs retain
their existing separate release responsibilities.
