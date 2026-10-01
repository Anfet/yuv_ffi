# TEST 1 — Инвентаризация тест-сьюта

- SHA dev: `9fbd1564e70965950b5f552221b85e154fb66ba3`.
- Сохранённый полный VM JSON: 731 passed, 1 skipped, 0 failed, 37.75 s; `exclude_tags: release` перед ним временно снимался и затем был восстановлен.
- Example JSON: `cd example && flutter test --reporter json` — 71 passed, 0 skipped, 0 failed, 19.27 s.
- Повтор 2026-10-01: CMake собрал DLL в `%TEMP%/yuv-ffi-test-1-correction/Release`; `flutter test --reporter compact` с ней не завершился за три минуты и был прерван. `dart_test.yaml` не менялся, поэтому ниже сохранены исходные JSON-числа и времена.
- В полном VM результате 724 проверки слоёв `api`/`ffi`/`reference`/`probe`/`release` и семь passing guard-проверок `test/web/*`. WASM-контракты на Windows не исполнялись. Integration counts получены из зарегистрированных `test(` / `testWidgets(`; `reference_web_conversions` регистрирует один testWidgets, который проходит 119 cases.

| Файл | Слой | Контракт | Тестов | Время, с | Пересечения | Предложение |
| --- | --- | --- | ---: | ---: | --- | --- |
| `example/integration_test/all_web_test.dart` | integration | Точка входа browser-набора не объявляет самостоятельных тестов. | 0 | — | — | оставить |
| `example/integration_test/desktop_camera_preview_smoke_test.dart` | integration | Desktop preview получает и показывает frame реальной CameraPlatform. | 1 | — | `example/test/desktop_camera_preview_test.dart` › `group('desktop preview')` | оставить: integration smoke |
| `example/integration_test/example_camera_flow_test.dart` | integration | Demo захватывает frame, детектирует лицо, crop и effect. | 1 | — | — | оставить |
| `example/integration_test/getbytes_contract_web_test.dart` | integration | WASM `getBytes` возвращает tight concatenation и copy. | 4 | — | `test/web/wasm_parity_edge_cases_test.dart` › `group('getBytes contract')` | оставить: real browser |
| `example/integration_test/helpers/probe/layout_pack_test.dart` | integration | Pack сохраняет visible BGRA для padded/gapped layout. | 1 | — | `test/probe/layout_pack_test.dart` › `test('packing preserves the visible BGRA result across padded and gapped layouts')` | оставить: application helper |
| `example/integration_test/helpers/probe/probe_correctness_test.dart` | integration | Matrix совпадает с golden; запись меняет только явно разрешённые values. | 2 | — | `test/probe/probe_correctness_test.dart` › `test('native operation matrix matches the exact golden')` | оставить: application helper |
| `example/integration_test/image_cache_key_web_test.dart` | integration | Revision invalidates Web image cache лишь после real mutation. | 17 | — | `test/yuv_image_widget_test.dart` › `group('image cache key')` | оставить: real WASM |
| `example/integration_test/ios_bgra_camera_frame_test.dart` | integration | Padded iOS BGRA frame сохраняет каждый visible pixel. | 1 | — | `example/test/camera_image_to_yuv_image_padding_test.dart` › `test('toYuvImage keeps a padded BGRA row stride without shifting pixels')` | оставить: iOS boundary |
| `example/integration_test/native_app_runtime_smoke_test.dart` | integration | App bundle загружает plugin и выполняет native conversion. | 1 | — | `test/native_packaging_smoke_test.dart` › `test('the native library opens by its installed name and performs a real conversion')` | оставить: bundle smoke |
| `example/integration_test/nv_chroma_order_web_test.dart` | integration | WASM сохраняет порядок UV при ручных bytes и round-trip. | 2 | — | `test/nv_chroma_order_test.dart` › `group('NV chroma byte order')` | оставить: real WASM |
| `example/integration_test/padded_bgra_constructor_web_test.dart` | integration | WASM padded-BGRA constructor validates, copies bytes и сохраняет layout. | 7 | — | `test/web/wasm_parity_edge_cases_test.dart` › `group('padded BGRA constructor contract')` | оставить: real browser |
| `example/integration_test/probe_native_test.dart` | integration | Native operation matrix совпадает с exact golden. | 1 | — | `test/probe/probe_correctness_test.dart` › `test('native operation matrix matches the exact golden')` | оставить: device integration |
| `example/integration_test/probe_performance_test.dart` | integration | Benchmark выдаёт один complete structured verdict. | 1 | — | `test/probe/probe_performance_test.dart` › `test('performance scenarios report correctness hashes and timing verdicts')` | оставить: integration harness |
| `example/integration_test/probe_web_test.dart` | integration | Web operation matrix совпадает с exact golden. | 1 | — | `test/probe/probe_correctness_test.dart` › `test('native operation matrix matches the exact golden')` | оставить: Web backend |
| `example/integration_test/reference_web_conversions_test.dart` | integration | Один browser test прогоняет 119-case reference matrix против WASM. | 1 | — | `test/reference_native_conversions_test.dart` › `test('manifest declares the complete native reference matrix')` | оставить: Web oracle |
| `example/integration_test/serialization_contract_web_test.dart` | integration | WASM codec preserves layout/revision; malformed input не меняет image. | 11 | — | `test/yuv_serialization_test.dart` › `group('a failed load leaves the image untouched')` | оставить: real browser |
| `example/integration_test/wasm_abi_v1_descriptor_staging_web_test.dart` | integration | Browser ABI v1 stages descriptors/options, symbols и cleanup correctly. | 29 | — | `test/abi_status_mapping_test.dart` › `group('YuvAbiV1Runner descriptor construction (no yuv_ffi.dll required)')` | оставить: browser staging |
| `example/integration_test/wasm_bootstrap_web_test.dart` | integration | Web WASM runtime initializes and converts a frame. | 1 | — | `test/web/yuv_web_wasm_test.dart` › `test('i420/nv21/bgra pipelines run without throwing')` | оставить: bootstrap |
| `example/integration_test/wasm_loader_lifecycle_web_test.dart` | integration | Loader caches success, shares in-flight attempt и retries error. | 9 | — | `test/web/wasm_loader_initialization_test.dart` › `test('a failed attempt is not cached and the next call retries')` | оставить: asset lifecycle |
| `example/integration_test/wasm_parity_edge_cases_web_test.dart` | integration | WASM packs padded BGRA to tight bytes without changing tight input. | 2 | — | `test/web/wasm_parity_edge_cases_test.dart` › `group('padded BGRA constructor contract')` | оставить: real browser |
| `example/integration_test/wasm_swap_nv_atomicity_web_test.dart` | integration | Failed convert/swap publishes no partial state; success increments revision once. | 5 | — | `test/io_abi_v1_public_contract_test.dart` › `group('swapNv on a non-NV receiver is atomic across both native calls')` | оставить: real WASM |
| `example/integration_test/web_matrix_abort_test.dart` | integration | BGRA→NV21 abort publishes no partial result. | 1 | — | `test/io_abi_v1_public_contract_test.dart` › `group('a non-zero native status leaves the receiver untouched')` | оставить: abort boundary |
| `example/integration_test/web_ownership_regression_web_test.dart` | integration | WASM planes/conversions/no-ops own independent buffers. | 3 | — | `test/web/independent_results_web_test.dart` › `group('aliasing')` | оставить: ownership regression |
| `example/integration_test/yuv_web_capabilities_web_test.dart` | integration | ABI exports determine capabilities before mutation. | 5 | — | `test/yuv_capabilities_test.dart` › `group('yuvRequireCapability')` | оставить: real module |
| `example/test/camera_image_pack_planes_test.dart` | example | Camera I420/NV12/BGRA padded/gapped planes preserve visible samples. | 9 | 8.81 | `test/pack_planes_native_equivalence_test.dart` › `group('padded vs. packed YuvPlane produce identical native output')` | оставить: adapter |
| `example/test/camera_image_to_yuv_image_padding_test.dart` | example | `toYuvImage` keeps padded BGRA row stride without pixel shift. | 1 | 8.89 | `example/integration_test/ios_bgra_camera_frame_test.dart` › `testWidgets('preserves each visible pixel of a padded iOS BGRA camera frame')` | оставить: adapter |
| `example/test/camera_preview_lifecycle_test.dart` | example | Mobile preview serializes streams, drops stale frames/errors and captures shown frame. | 27 | 19.23 | `example/test/desktop_camera_preview_test.dart` › `group('desktop preview')` | оставить: mobile controller |
| `example/test/camera_screen_capture_test.dart` | example | Captured preview frame survives reuse of source image. | 1 | 10.47 | `example/test/desktop_camera_preview_test.dart` › `group('CameraScreen on desktop')` | оставить: capture aliasing |
| `example/test/desktop_camera_preview_test.dart` | example | Desktop preview stops old stream and returns independent capture. | 10 | 12.68 | `example/test/camera_preview_lifecycle_test.dart` › `group('mobile preview')` | оставить: desktop path |
| `example/test/frame_read_loop_test.dart` | example | Read loop ignores stale frames/errors after stop/restart. | 5 | 9.98 | `example/test/camera_preview_lifecycle_test.dart` › `group('mobile preview')` | оставить: loop seam |
| `example/test/pack00_bench_screen_test.dart` | example | Benchmark screen restores flag after finish/dispose without stomping second screen. | 4 | 11.62 | — | оставить |
| `example/test/present_camera_frame_test.dart` | example | Presenter shows transformed/original frame and drops only failed transform. | 3 | 10.33 | `example/test/camera_preview_lifecycle_test.dart` › `group('transform contract')` | оставить: presenter |
| `example/test/stream_start_test.dart` | example | Browser camera start releases stale getUserMedia stream and reports only current error. | 8 | 10.58 | `example/test/camera_preview_lifecycle_test.dart` › `group('mobile preview')` | оставить: browser start |
| `example/test/yuv_image_to_input_image_test.dart` | example | Padded/gapped I420/NV12/BGRA become tight correctly ordered NV21 input. | 3 | 10.72 | `example/test/camera_image_pack_planes_test.dart` › `group('toInputImage() metadata after packing')` | оставить: ML adapter |
| `test/abi_status_mapping_test.dart` | ffi | ABI statuses map to documented exceptions; runner validates descriptors, ROI and cleanup. | 33 | 8.78 | `example/integration_test/wasm_abi_v1_descriptor_staging_web_test.dart` › `group('status mapping and memory')` | оставить: runner seam |
| `test/abi_symbol_manifest_test.dart` | ffi | Header, ffigen, WASM exports and Dart manifest contain same v1 symbols. | 13 | 8.81 | `example/integration_test/yuv_web_capabilities_web_test.dart` › `testWidgets('a module exporting the complete ABI v1 manifest yields capabilities supporting every operation')` | оставить |
| `test/apple_forwarder_sources_test.dart` | api | Apple forwarders include each CMake source exactly once. | 6 | 8.92 | `test/cmake_sources_test.dart` › `group('CMakeLists.txt source list stays in sync with src/**/*.c')` | оставить |
| `test/bgra_mean_blur_contract_test.dart` | api | BGRA mean blur preserves alpha and ROI boundary semantics. | 8 | 18.92 | — | оставить |
| `test/cmake_sources_test.dart` | api | CMake manifest has all required native sources and no stale entry. | 5 | 9.46 | `test/apple_forwarder_sources_test.dart` › `group('Apple forwarders stay in sync with src/CMakeLists.txt')` | оставить |
| `test/conversions_test.dart` | api | Conversions/transforms/padded BGRA/getBytes preserve bytes, geometry and ownership. | 41 | 12.79 | `test/web/wasm_parity_conversions_test.dart` › `test('BGRA -> I420 -> BGRA round-trip keeps acceptable quality')` | оставить: native baseline |
| `test/convert_copy_out_test.dart` | api | Convert result survives source mutation/free and calls never share destination buffer. | 4 | 9.99 | `test/independent_results_test.dart` › `group('aliasing: source and result own independent buffers (requires real native library)')` | оставить |
| `test/convert_destination_allocation_test.dart` | api | Convert zeroes padded/gapped destination and frees every allocation. | 8 | 10.24 | `test/abi_status_mapping_test.dart` › `group('YuvAbiV1Runner releases every allocation on a call (no yuv_ffi.dll required)')` | оставить |
| `test/deprecated_api_test.dart` | api | Deprecated 0.3 API compiles and forwards identically to 0.4 methods. | 19 | 10.56 | `test/public_surface_test.dart` › `test('the full deprecated 0.3.0 instance-method surface compiles and runs through the public library alone')` | оставить |
| `test/encode_decode_test.dart` | api | Legacy encode/decode preserves I420 and rejects invalid data. | 11 | 10.71 | `test/yuv_serialization_test.dart` › `group('round-trip')` | оставить |
| `test/independent_results_test.dart` | api | Copy, conversions, crop/rotate and byte getters never alias, including no-op. | 13 | 11.01 | `test/web/independent_results_web_test.dart` › `group('aliasing')` | оставить: native baseline |
| `test/io_abi_v1_public_contract_test.dart` | ffi | Failed ABI status/swapNv leaves receiver untouched; success publishes once. | 25 | 11.30 | `example/integration_test/wasm_swap_nv_atomicity_web_test.dart` › `testWidgets('both calls succeeding publishes once, as NV21, advancing the revision by one')` | оставить |
| `test/loader_io_test.dart` | ffi | Native loader caches success, shares open, retries errors and checks manifest. | 11 | 11.35 | `test/web/wasm_loader_initialization_test.dart` › `test('a failed attempt is not cached and the next call retries')` | оставить |
| `test/native_allocation_safety_test.dart` | ffi | Native operations free partial allocations without masking original error. | 11 | 11.59 | `test/abi_status_mapping_test.dart` › `group('YuvAbiV1Runner releases every allocation on a call (no yuv_ffi.dll required)')` | оставить |
| `test/native_packaging_smoke_test.dart` | ffi | Installed-name DLL opens and performs real conversion. | 1 | 11.62 | `example/integration_test/native_app_runtime_smoke_test.dart` › `testWidgets('the plugin loads from the application bundle and performs real native work')` | оставить |
| `test/native_stride_safety_test.dart` | ffi | Native conversion preserves gaps, UV order and odd-size chroma. | 10 | 12.06 | `test/web/wasm_parity_edge_cases_test.dart` › `test('I420 custom rowStride/pixelStride produces same BGRA output as baseline')` | оставить |
| `test/nv_chroma_order_test.dart` | api | NV12 stores UV order and preserves planes through round-trip. | 5 | 12.15 | `example/integration_test/nv_chroma_order_web_test.dart` › `testWidgets('nv12 and nv21 store identical hand-written chroma bytes on the real WASM backend')` | оставить |
| `test/pack_planes_native_equivalence_test.dart` | ffi | Packed CameraImage planes equal tight native conversion baseline. | 7 | 12.35 | `example/test/camera_image_pack_planes_test.dart` › `group('I420 with gapped U/V stride')` | оставить |
| `test/planar_box_mean_blur_contract_test.dart` | api | I420/NV21 blur keeps outside-ROI bytes, gaps and no-op semantics. | 13 | 12.59 | — | оставить |
| `test/plane_row_copy_contract_test.dart` | api | applyTo/ROI seed reads active padded/gapped samples and preserves padding. | 3 | 12.68 | `example/integration_test/wasm_abi_v1_descriptor_staging_web_test.dart` › `group('source frame staging')` | оставить |
| `test/probe/layout_pack_test.dart` | probe | Packing preserves visible BGRA over padded/gapped layouts. | 1 | 13.28 | `example/integration_test/helpers/probe/layout_pack_test.dart` › `test('packing preserves the visible BGRA result across padded and gapped layouts')` | оставить |
| `test/probe/operation_coverage_test.dart` | probe | Every public operation has correctness/performance scenario and matching golden key. | 5 | 13.18 | `test/probe/probe_correctness_test.dart` › `test('native operation matrix matches the exact golden')` | оставить |
| `test/probe/probe_copy_sync_test.dart` | probe | Example probe helpers and golden match package sources. | 1 | 13.38 | `example/integration_test/helpers/probe/probe_correctness_test.dart` › `test('native operation matrix matches the exact golden')` | оставить |
| `test/probe/probe_correctness_test.dart` | probe | Native matrix matches golden; recording follows append/overwrite policy. | 2 | 15.46 | `example/integration_test/helpers/probe/probe_correctness_test.dart` › `test('native operation matrix matches the exact golden')` | оставить |
| `test/probe/probe_performance_test.dart` | probe | Profile benchmark reports one complete structured verdict. | 1 | 13.67 | `example/integration_test/probe_performance_test.dart` › `testWidgets('profile benchmark reports a single complete structured verdict')` | оставить |
| `test/probe/probe_runner_test.dart` | probe | Runner reports correctness hash, baseline band and strict slowdown verdict. | 6 | 13.99 | — | оставить |
| `test/probe/release_probe_core_test.dart` | release | Release probe core accepts every exact golden case. | 1 | 15.95 | — | оставить |
| `test/probe/run_release_android_test.dart` | release | Android runner accepts one clean marker and rejects malformed provenance. | 13 | 37.58 | — | оставить |
| `test/probe/windows_release_package_provenance_contract_test.dart` | release | Windows package provenance permits only controlled override. | 3 | 14.48 | — | оставить |
| `test/public_surface_test.dart` | api | Public export exposes all factories, legacy surface and foreign implementation. | 3 | 14.75 | `test/deprecated_api_test.dart` › `group('consumer compile test: every 0.3.0 instance method/factory still compiles')` | оставить |
| `test/reference_manifest_test.dart` | reference | Reference manifest pins hashes, artifacts, tolerances and stable case IDs. | 7 | 16.49 | `test/reference_native_conversions_test.dart` › `test('manifest declares the complete native reference matrix')` | оставить |
| `test/reference_native_conversions_test.dart` | reference | Native backend runs 121 reference cases against expected artifacts. | 121 | 32.01 | `example/integration_test/reference_web_conversions_test.dart` › `testWidgets('the full 119-case reference conversion matrix runs on the real Web/WASM backend')` | оставить |
| `test/reference_oracle_shift_test.dart` | reference | BT.601 reference oracle uses portable signed right shift. | 2 | 16.60 | — | оставить |
| `test/wasm_abi_v1_layout_test.dart` | ffi | Dart descriptors/options offsets and sizes match C ABI header. | 16 | 16.89 | `example/integration_test/wasm_abi_v1_descriptor_staging_web_test.dart` › `group('source frame staging')` | оставить |
| `test/web/independent_results_web_test.dart` | web | VM registers one guard; browser copy/conversions/getters/no-op do not alias. | 1 | — | `test/independent_results_test.dart` › `group('aliasing: source and result own independent buffers (requires real native library)')` | оставить: browser parity |
| `test/web/wasm_loader_initialization_test.dart` | web | VM registers one guard; browser loader caches and retries initialization. | 1 | — | `test/loader_io_test.dart` › `group('initialization contract')` | оставить: browser parity |
| `test/web/wasm_parity_conversions_test.dart` | web | VM registers one guard; browser BGRA/I420/NV21 round-trip keeps quality/geometry. | 1 | — | `test/conversions_test.dart` › `test('I420 round-trip RGBA -> I420 -> BGRA keeps acceptable quality')` | оставить: browser parity |
| `test/web/wasm_parity_edge_cases_test.dart` | web | VM registers one guard; browser odd-size/stride/padded/getBytes contracts hold. | 1 | — | `test/conversions_test.dart` › `group('padded BGRA constructor contract')` | оставить: browser parity |
| `test/web/wasm_parity_transforms_test.dart` | web | VM registers one guard; browser crop/rotate/flip exact and swap reversible. | 1 | — | `test/conversions_test.dart` › `test('applyRotation 90 on BGRA is exact')` | оставить: browser parity |
| `test/web/yuv_nv12_pixel_gap_web_test.dart` | web | VM registers one guard; WASM operation leaves NV12 chroma gap untouched. | 1 | — | `test/yuv_image_factories_test.dart` › `group('YuvImage.nv12')` | оставить: browser parity |
| `test/web/yuv_web_wasm_test.dart` | web | VM registers one guard; browser WASM runs unary and multi-format pipelines. | 1 | — | `example/integration_test/wasm_bootstrap_web_test.dart` › `testWidgets('the Web WASM runtime initializes and converts a frame')` | оставить: browser smoke |
| `test/yuv_apply_planes_test.dart` | api | applyPlanes validates layout, copies caller bytes and preserves rejected state. | 15 | 18.70 | `test/yuv_apply_surface_test.dart` › `group('capability gate runs before any state change')` | оставить |
| `test/yuv_apply_surface_test.dart` | api | apply* honors capability, atomicity, revision, no-op and independent-result contract. | 29 | 19.12 | `test/io_abi_v1_public_contract_test.dart` › `group('a non-zero native status leaves the receiver untouched')` | оставить |
| `test/yuv_bgra_pixel_gap_test.dart` | api | BGRA pixel gaps are neither pixels nor mutation targets. | 4 | 19.09 | `test/native_stride_safety_test.dart` › `group('native stride and odd-size safety')` | оставить |
| `test/yuv_capabilities_test.dart` | api | Capabilities snapshot rejects unsupported operation before state mutation. | 15 | 19.35 | `example/integration_test/yuv_web_capabilities_web_test.dart` › `testWidgets('querying an operation the module does not support throws UnsupportedError before any state exists to mutate')` | оставить |
| `test/yuv_ffi_capabilities_wiring_test.dart` | ffi | IO/Web initializers expose manifest-matching capabilities. | 3 | 19.44 | `test/abi_symbol_manifest_test.dart` › `group('ABI v1 symbol manifest')` | оставить |
| `test/yuv_ffi_initializer_test.dart` | ffi | Facade initializer is idempotent, shares in-flight init and reports loader error. | 6 | 19.65 | `test/loader_io_test.dart` › `group('initialization contract')` | оставить |
| `test/yuv_frame_presenter_test.dart` | api | Presenter drops stale frame and owns result during async transform. | 5 | 21.77 | `example/test/present_camera_frame_test.dart` › `test('a throwing transform drops only its frame and is reported')` | оставить |
| `test/yuv_geometry_rejection_test.dart` | api | Invalid/overflow geometry fails before allocation/native dispatch. | 15 | 20.27 | `test/yuv_plane_validation_test.dart` › `group('image dimensions')` | оставить |
| `test/yuv_image_factories_test.dart` | api | Factories allocate valid tight/padded/gapped I420/NV12/BGRA layouts. | 24 | 20.49 | `test/web/yuv_nv12_pixel_gap_web_test.dart` › `test('a real WASM ABI v1 operation on a gapped NV12 plane leaves the gap byte untouched')` | оставить |
| `test/yuv_image_revision_test.dart` | api | Real mutation advances revision once; defined no-op does not. | 14 | 20.61 | `test/yuv_apply_surface_test.dart` › `group('defined no-ops do not advance the revision')` | оставить |
| `test/yuv_image_rotation_test.dart` | api | Quarter-turn enum has correct swap-size and rotation algebra. | 8 | 20.70 | `test/conversions_test.dart` › `test('applyRotation 90 on BGRA is exact')` | оставить |
| `test/yuv_image_source_compatibility_test.dart` | api | Public source types accept compatible data and reject stale legacy representations. | 6 | 20.84 | `test/public_surface_test.dart` › `test('a foreign implements YuvImage still compiles the complete YuvImage surface through the public library alone')` | оставить |
| `test/yuv_image_state_contract_test.dart` | api | Accessors, geometry, deep copy, byte snapshot and revision form consistent state. | 20 | 21.15 | `test/yuv_plane_validation_test.dart` › `group('plane count')` | оставить |
| `test/yuv_image_widget_test.dart` | api | Widget cache tracks revision, retains queued frame and renders padded BGRA. | 17 | 22.66 | `example/integration_test/image_cache_key_web_test.dart` › `group('the image cache follows the real revision')` | оставить |
| `test/yuv_pack_test.dart` | api | Pack/unpack preserves logical samples over planar/interleaved/padded/odd layouts. | 13 | 21.59 | `example/test/camera_image_pack_planes_test.dart` › `group('I420 with gapped U/V stride')` | оставить |
| `test/yuv_pixel_format_test.dart` | api | Format metadata exposes plane count, sample bytes, chroma geometry and wire IDs. | 8 | 21.73 | `test/yuv_image_state_contract_test.dart` › `group('geometry contract')` | оставить |
| `test/yuv_plane_alias_test.dart` | api | Plane copy/assign never aliases source bytes or metadata. | 4 | 21.83 | `test/yuv_image_state_contract_test.dart` › `group('copy contract')` | оставить |
| `test/yuv_plane_layout_test.dart` | api | Layout computes strides, active spans and odd chroma extents consistently. | 15 | 22.22 | `test/yuv_plane_validation_test.dart` › `group('valid layouts still work')` | оставить |
| `test/yuv_plane_validation_test.dart` | api | Validation rejects malformed buffers/geometry/count/stride and accepts exact layouts. | 30 | 22.54 | `test/yuv_geometry_rejection_test.dart` › `group('default constructors validate what they allocate')` | оставить |
| `test/yuv_serialization_test.dart` | api | v2 codec validates incrementally, preserves layout and leaves state on failure. | 44 | 23.12 | `example/integration_test/serialization_contract_web_test.dart` › `group('a failed load leaves the image untouched')` | оставить |

## Сверка чисел

| Слой | Passed в полном VM JSON |
| --- | ---: |
| api | 425 |
| ffi | 136 |
| reference | 130 |
| probe | 16 |
| release | 17 |
| web VM guards | 7 |
| **Итого package** | **731** |
| integration (source count, не запускался) | 107 |
| example (JSON) | 71 |

`api + ffi + reference + probe + release = 724`; семь web guards делают итог package 731. Это объясняет прежнее расхождение без замены VM-result количеством browser-деклараций.

## Медленные файлы

JSON events interleave, поэтому spans не складываются. Самые долгие: `test/probe/run_release_android_test.dart` (37.58 s; запускает runner processes), `test/reference_native_conversions_test.dart` (32.01 s; 121 cases и 512×512 input), `test/yuv_serialization_test.dart` (23.12 s; payloads и fragmented streams), `test/yuv_image_widget_test.dart` (22.66 s; frame/cache scheduling), `test/yuv_plane_validation_test.dart` (22.54 s; validation matrix). Полный invocation: 37.75 s.

## Контракты без второго покрытия

- `example/integration_test/example_camera_flow_test.dart`: demo захватывает frame, распознаёт лицо, делает crop и применяет effect.
- `test/probe/probe_runner_test.dart`: runner сверяет correctness hash, baseline band и strict slowdown verdict.
- `test/probe/run_release_android_test.dart`: parser принимает ровно один complete `RA25_RESULT` marker от clean checkout.
- `test/probe/windows_release_package_provenance_contract_test.dart`: package path/revision допускает лишь controlled override.
- `test/probe/release_probe_core_test.dart`: release core принимает каждый exact golden case.
- `test/bgra_mean_blur_contract_test.dart`: BGRA mean blur сохраняет alpha на ROI boundary.
- `test/planar_box_mean_blur_contract_test.dart`: planar blur не трогает row/pixel gaps.
- `test/reference_oracle_shift_test.dart`: BT.601 oracle имеет portable signed shift.
- `example/test/pack00_bench_screen_test.dart`: dispose первого screen не затирает flag второго.
- `example/test/stream_start_test.dart`: stale `getUserMedia` stream закрывается, не становясь active preview.
- `test/yuv_image_source_compatibility_test.dart`: stale legacy source representation не проходит public API.

TEST 5 не меняет эти контракты без отдельного replacement test.
