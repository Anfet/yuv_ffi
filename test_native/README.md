# Native C Unit Tests for yuv_ffi

This directory contains C unit tests for the native yuv_ffi library. The tests are organized separately from the main library sources (`src/`) to avoid conflicts with the CMakeLists.txt source list verification in `test/cmake_sources_test.dart`.

## Building and Running Tests

To build and run the native C tests:

```bash
# Configure CMake with testing enabled
cmake -S . -B <build-dir> -DBUILD_TESTING=ON

# Build the test targets
cmake --build <build-dir> --config Debug

# Run the tests
ctest --test-dir <build-dir> -C Debug --output-on-failure
```

## Test Infrastructure

- **Compiler**: Strict warnings enabled (`-Wall -Wextra -Werror` on GCC/Clang, `/W4 /WX` on MSVC)
- **Sanitizers**: AddressSanitizer and UndefinedBehaviorSanitizer are enabled on Linux and macOS with non-MSVC compilers (GCC/Clang). On Windows, sanitizers are not enabled for any compiler (including clang), because clang on Windows targets MSVC-compatible `lld-link` which lacks an integrated ASan/UBSan runtime. Tests still compile and run on Windows without sanitizers.
- **LeakSanitizer**: bundled into ASan and on by default on Linux; `abi_sanitizer_tests` additionally sets `ASAN_OPTIONS=detect_leaks=1` there. Not enabled on macOS, where ASan does not support leak detection.
- **Allocation-failure injection**: `abi_sanitizer_test.c` wraps `malloc` via the GNU/gold/lld ELF linker's `--wrap=malloc` (`target_link_options(... -Wl,--wrap=malloc)`, guarded by `ENABLE_MALLOC_WRAP`), enabled only on Linux with a non-MSVC compiler -- the same condition already used for the sanitizer flags, since `--wrap` needs the same ELF-targeting linker. On every other toolchain that test group compiles out to a single line reporting it was skipped, rather than silently omitting cases.

## Test Files

- `smoke_test.c`: Demonstrates that the harness correctly catches assertion failures (configured as `WILL_FAIL`)
- `smoke_test_pass.c`: Verifies that the harness correctly runs and passes normal tests
- `abi_sanitizer_test.c`: Native ASan/UBSan/LSan safety gate (YUV-34). Calls all eleven exported ABI v1 entry points against heap frames whose planes are exact-length allocations, so an out-of-bounds kernel access trips ASan's own redzone; padding gaps inside those same allocations are separately canary-checked. Covers canary probes across every operation family, geometric transforms, region of interest, an exact-fit (zero padding) allocation, repeated allocate/free cycles, invalid rect/radius/sigma/geometry, checked-arithmetic overflow, and allocation-failure injection for the blur entry points (the only ones that allocate).

## Organization Notes

Test sources are placed in `test_native/` at the project root (not under `src/`) because:
1. The Dart test `test/cmake_sources_test.dart` validates that `src/CMakeLists.txt` lists all `.c` files found recursively under `src/`
2. By placing test code outside `src/`, test files are not subject to this validation
3. This keeps test infrastructure cleanly separated from the production library sources
