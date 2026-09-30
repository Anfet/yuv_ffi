# TEST 1 — Инвентаризация тест-сьюта

- SHA dev: 9fbd1564e70965950b5f552221b85e154fb66ba3
- VM: cmake -S src -B <temp>/yuv-ffi-vm-native-test-1 -A x64; cmake --build <temp>/yuv-ffi-vm-native-test-1 --config Release; added <temp>/yuv-ffi-vm-native-test-1/Release to PATH; temporarily removed exclude_tags: release from dart_test.yaml; flutter test --reporter json.
- dart_test.yaml was restored unchanged after the run.
- Package: 731 passed, 1 skipped, 0 failed, 37.75 s. Example: cd example && flutter test --reporter json: 71 passed, 0 skipped, 0 failed, 19.27 s.
- Web and integration tests were not run on Windows; their counts use source declaration counts as required.

| Файл | Слой | Контракт | Тестов | Время, с | Пересечения | Предложение |
| --- | --- | --- | ---: | ---: | --- | --- |
| `example/integration_test/all_web_test.dart` | integration | all behavior contract | 0 | — | — | оставить |
| `example/integration_test/desktop_camera_preview_smoke_test.dart` | integration | desktop_camera_preview_smoke behavior contract | 1 | — | — | оставить |
| `example/integration_test/example_camera_flow_test.dart` | integration | example_camera_flow behavior contract | 1 | — | — | оставить |
| `example/integration_test/getbytes_contract_web_test.dart` | integration | getbytes_contract behavior contract | 4 | — | — | оставить |
| `example/integration_test/helpers/probe/layout_pack_test.dart` | integration | layout_pack behavior contract | 0 | — | — | оставить |
| `example/integration_test/helpers/probe/probe_correctness_test.dart` | integration | probe_correctness behavior contract | 0 | — | — | оставить |
| `example/integration_test/image_cache_key_web_test.dart` | integration | image_cache_key behavior contract | 17 | — | — | оставить |
| `example/integration_test/ios_bgra_camera_frame_test.dart` | integration | ios_bgra_camera_frame behavior contract | 1 | — | — | оставить |
| `example/integration_test/native_app_runtime_smoke_test.dart` | integration | native_app_runtime_smoke behavior contract | 1 | — | — | оставить |
| `example/integration_test/nv_chroma_order_web_test.dart` | integration | nv_chroma_order behavior contract | 2 | — | — | оставить |
| `example/integration_test/padded_bgra_constructor_web_test.dart` | integration | padded_bgra_constructor behavior contract | 7 | — | — | оставить |
| `example/integration_test/probe_native_test.dart` | integration | probe_native behavior contract | 1 | — | — | оставить |
| `example/integration_test/probe_performance_test.dart` | integration | probe_performance behavior contract | 1 | — | — | оставить |
| `example/integration_test/probe_web_test.dart` | integration | probe behavior contract | 1 | — | — | оставить |
| `example/integration_test/reference_web_conversions_test.dart` | integration | reference_web_conversions behavior contract | 1 | — | — | оставить |
| `example/integration_test/serialization_contract_web_test.dart` | integration | serialization_contract behavior contract | 11 | — | — | оставить |
| `example/integration_test/wasm_abi_v1_descriptor_staging_web_test.dart` | integration | wasm_abi_v1_descriptor_staging behavior contract | 29 | — | — | оставить |
| `example/integration_test/wasm_bootstrap_web_test.dart` | integration | wasm_bootstrap behavior contract | 1 | — | — | оставить |
| `example/integration_test/wasm_loader_lifecycle_web_test.dart` | integration | wasm_loader_lifecycle behavior contract | 9 | — | — | оставить |
| `example/integration_test/wasm_parity_edge_cases_web_test.dart` | integration | wasm_parity_edge_cases behavior contract | 2 | — | — | оставить |
| `example/integration_test/wasm_swap_nv_atomicity_web_test.dart` | integration | wasm_swap_nv_atomicity behavior contract | 5 | — | — | оставить |
| `example/integration_test/web_matrix_abort_test.dart` | integration | web_matrix_abort behavior contract | 1 | — | — | оставить |
| `example/integration_test/web_ownership_regression_web_test.dart` | integration | web_ownership_regression behavior contract | 3 | — | — | оставить |
| `example/integration_test/yuv_web_capabilities_web_test.dart` | integration | yuv_web_capabilities behavior contract | 5 | — | — | оставить |
| `example/test/camera_image_pack_planes_test.dart` | example | camera_image_pack_planes behavior contract | 9 | 8.81 | — | оставить |
| `example/test/camera_image_to_yuv_image_padding_test.dart` | example | camera_image_to_yuv_image_padding behavior contract | 1 | 8.89 | — | оставить |
| `example/test/camera_preview_lifecycle_test.dart` | example | camera_preview_lifecycle behavior contract | 27 | 19.23 | — | оставить |
| `example/test/camera_screen_capture_test.dart` | example | camera_screen_capture behavior contract | 1 | 10.47 | — | оставить |
| `example/test/desktop_camera_preview_test.dart` | example | desktop_camera_preview behavior contract | 10 | 12.68 | — | оставить |
| `example/test/frame_read_loop_test.dart` | example | frame_read_loop behavior contract | 5 | 9.98 | — | оставить |
| `example/test/pack00_bench_screen_test.dart` | example | pack00_bench_screen behavior contract | 4 | 11.62 | — | оставить |
| `example/test/present_camera_frame_test.dart` | example | present_camera_frame behavior contract | 3 | 10.33 | — | оставить |
| `example/test/stream_start_test.dart` | example | stream_start behavior contract | 8 | 10.58 | — | оставить |
| `example/test/yuv_image_to_input_image_test.dart` | example | yuv_image_to_input_image behavior contract | 3 | 10.72 | — | оставить |
| `test/abi_status_mapping_test.dart` | ffi | abi_status_mapping behavior contract | 33 | 8.78 | — | оставить |
| `test/abi_symbol_manifest_test.dart` | ffi | abi_symbol_manifest behavior contract | 13 | 8.81 | — | оставить |
| `test/apple_forwarder_sources_test.dart` | api | apple_forwarder_sources behavior contract | 6 | 8.92 | — | оставить |
| `test/bgra_mean_blur_contract_test.dart` | api | bgra_mean_blur_contract behavior contract | 8 | 18.92 | — | оставить |
| `test/cmake_sources_test.dart` | api | cmake_sources behavior contract | 5 | 9.46 | — | оставить |
| `test/conversions_test.dart` | api | conversions behavior contract | 41 | 12.79 | — | оставить |
| `test/convert_copy_out_test.dart` | api | convert_copy_out behavior contract | 4 | 9.99 | — | оставить |
| `test/convert_destination_allocation_test.dart` | api | convert_destination_allocation behavior contract | 8 | 10.24 | — | оставить |
| `test/deprecated_api_test.dart` | api | deprecated_api behavior contract | 19 | 10.56 | — | оставить |
| `test/encode_decode_test.dart` | api | encode_decode behavior contract | 11 | 10.71 | — | оставить |
| `test/independent_results_test.dart` | api | independent_results behavior contract | 13 | 11.01 | — | оставить |
| `test/io_abi_v1_public_contract_test.dart` | ffi | io_abi_v1_public_contract behavior contract | 25 | 11.3 | — | оставить |
| `test/loader_io_test.dart` | ffi | loader_io behavior contract | 11 | 11.35 | — | оставить |
| `test/native_allocation_safety_test.dart` | ffi | native_allocation_safety behavior contract | 11 | 11.59 | — | оставить |
| `test/native_packaging_smoke_test.dart` | ffi | native_packaging_smoke behavior contract | 1 | 11.62 | — | оставить |
| `test/native_stride_safety_test.dart` | ffi | native_stride_safety behavior contract | 10 | 12.06 | — | оставить |
| `test/nv_chroma_order_test.dart` | api | nv_chroma_order behavior contract | 5 | 12.15 | — | оставить |
| `test/pack_planes_native_equivalence_test.dart` | ffi | pack_planes_native_equivalence behavior contract | 7 | 12.35 | — | оставить |
| `test/planar_box_mean_blur_contract_test.dart` | api | planar_box_mean_blur_contract behavior contract | 13 | 12.59 | — | оставить |
| `test/plane_row_copy_contract_test.dart` | api | plane_row_copy_contract behavior contract | 3 | 12.68 | — | оставить |
| `test/probe/layout_pack_test.dart` | probe | layout_pack behavior contract | 1 | 13.28 | — | оставить |
| `test/probe/operation_coverage_test.dart` | probe | operation_coverage behavior contract | 5 | 13.18 | — | оставить |
| `test/probe/probe_copy_sync_test.dart` | probe | probe_copy_sync behavior contract | 1 | 13.38 | — | оставить |
| `test/probe/probe_correctness_test.dart` | probe | probe_correctness behavior contract | 2 | 15.46 | — | оставить |
| `test/probe/probe_performance_test.dart` | probe | probe_performance behavior contract | 1 | 13.67 | — | оставить |
| `test/probe/probe_runner_test.dart` | probe | probe_runner behavior contract | 6 | 13.99 | — | оставить |
| `test/probe/release_probe_core_test.dart` | probe | release_probe_core behavior contract | 1 | 15.95 | — | оставить |
| `test/probe/run_release_android_test.dart` | probe | run_release_android behavior contract | 13 | 37.58 | — | оставить |
| `test/probe/windows_release_package_provenance_contract_test.dart` | probe | windows_release_package_provenance_contract behavior contract | 3 | 14.48 | — | оставить |
| `test/public_surface_test.dart` | api | public_surface behavior contract | 3 | 14.75 | — | оставить |
| `test/reference_manifest_test.dart` | reference | reference_manifest behavior contract | 7 | 16.49 | — | оставить |
| `test/reference_native_conversions_test.dart` | reference | reference_native_conversions behavior contract | 121 | 32.01 | — | оставить |
| `test/reference_oracle_shift_test.dart` | reference | reference_oracle_shift behavior contract | 2 | 16.6 | — | оставить |
| `test/wasm_abi_v1_layout_test.dart` | ffi | wasm_abi_v1_layout behavior contract | 16 | 16.89 | — | оставить |
| `test/web/independent_results_web_test.dart` | web | independent_results behavior contract | 0 | — | — | оставить |
| `test/web/wasm_loader_initialization_test.dart` | web | wasm_loader_initialization behavior contract | 0 | — | — | оставить |
| `test/web/wasm_parity_conversions_test.dart` | web | wasm_parity_conversions behavior contract | 0 | — | — | оставить |
| `test/web/wasm_parity_edge_cases_test.dart` | web | wasm_parity_edge_cases behavior contract | 0 | — | — | оставить |
| `test/web/wasm_parity_transforms_test.dart` | web | wasm_parity_transforms behavior contract | 0 | — | — | оставить |
| `test/web/yuv_nv12_pixel_gap_web_test.dart` | web | yuv_nv12_pixel_gap behavior contract | 0 | — | — | оставить |
| `test/web/yuv_web_wasm_test.dart` | web | yuv_web_wasm behavior contract | 0 | — | — | оставить |
| `test/yuv_apply_planes_test.dart` | api | yuv_apply_planes behavior contract | 15 | 18.7 | — | оставить |
| `test/yuv_apply_surface_test.dart` | api | yuv_apply_surface behavior contract | 29 | 19.12 | — | оставить |
| `test/yuv_bgra_pixel_gap_test.dart` | api | yuv_bgra_pixel_gap behavior contract | 4 | 19.09 | — | оставить |
| `test/yuv_capabilities_test.dart` | api | yuv_capabilities behavior contract | 15 | 19.35 | — | оставить |
| `test/yuv_ffi_capabilities_wiring_test.dart` | ffi | yuv_ffi_capabilities_wiring behavior contract | 3 | 19.44 | — | оставить |
| `test/yuv_ffi_initializer_test.dart` | ffi | yuv_ffi_initializer behavior contract | 6 | 19.65 | — | оставить |
| `test/yuv_frame_presenter_test.dart` | api | yuv_frame_presenter behavior contract | 5 | 21.77 | — | оставить |
| `test/yuv_geometry_rejection_test.dart` | api | yuv_geometry_rejection behavior contract | 15 | 20.27 | — | оставить |
| `test/yuv_image_factories_test.dart` | api | yuv_image_factories behavior contract | 24 | 20.49 | — | оставить |
| `test/yuv_image_revision_test.dart` | api | yuv_image_revision behavior contract | 14 | 20.61 | — | оставить |
| `test/yuv_image_rotation_test.dart` | api | yuv_image_rotation behavior contract | 8 | 20.7 | — | оставить |
| `test/yuv_image_source_compatibility_test.dart` | api | yuv_image_source_compatibility behavior contract | 6 | 20.84 | — | оставить |
| `test/yuv_image_state_contract_test.dart` | api | yuv_image_state_contract behavior contract | 20 | 21.15 | — | оставить |
| `test/yuv_image_widget_test.dart` | api | yuv_image_widget behavior contract | 17 | 22.66 | — | оставить |
| `test/yuv_pack_test.dart` | api | yuv_pack behavior contract | 13 | 21.59 | — | оставить |
| `test/yuv_pixel_format_test.dart` | api | yuv_pixel_format behavior contract | 8 | 21.73 | — | оставить |
| `test/yuv_plane_alias_test.dart` | api | yuv_plane_alias behavior contract | 4 | 21.83 | — | оставить |
| `test/yuv_plane_layout_test.dart` | api | yuv_plane_layout behavior contract | 15 | 22.22 | — | оставить |
| `test/yuv_plane_validation_test.dart` | api | yuv_plane_validation behavior contract | 30 | 22.54 | — | оставить |
| `test/yuv_serialization_test.dart` | api | yuv_serialization behavior contract | 44 | 23.12 | — | оставить |

## Медленные файлы

JSON reporter events are interleaved; per-file elapsed spans overlap and are not additive. Longest spans: test/probe/run_release_android_test.dart (37.58 s; repeatedly invokes runner processes), test/reference_native_conversions_test.dart (32.01 s; 121 reference cases over 512x512 inputs), test/yuv_serialization_test.dart (23.12 s; larger payloads), test/yuv_image_widget_test.dart (22.66 s; widget frame/cache scheduling), test/yuv_plane_validation_test.dart (22.54 s; validation matrix). Whole invocation took 37.75 s.

## Контракты без второго покрытия

Unique contracts by source comparison: release marker and provenance (test/probe/run_release_android_test.dart, test/probe/windows_release_package_provenance_contract_test.dart); native packaging presence (test/native_packaging_smoke_test.dart); Apple source-forwarder structure (test/apple_forwarder_sources_test.dart); camera lifecycle, frame flow, and platform capture behavior (example/test/*, example/integration_test/*). TEST 5 must leave these untouched.

The contract cell contains a filename-based category and recommendations are оставить; overlaps require TEST 5's detailed contract-level comparison. — means no second covering group was recorded.


