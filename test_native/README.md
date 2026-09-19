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

## Test Files

- `smoke_test.c`: Demonstrates that the harness correctly catches assertion failures (configured as `WILL_FAIL`)
- `smoke_test_pass.c`: Verifies that the harness correctly runs and passes normal tests

## Organization Notes

Test sources are placed in `test_native/` at the project root (not under `src/`) because:
1. The Dart test `test/cmake_sources_test.dart` validates that `src/CMakeLists.txt` lists all `.c` files found recursively under `src/`
2. By placing test code outside `src/`, test files are not subject to this validation
3. This keeps test infrastructure cleanly separated from the production library sources
