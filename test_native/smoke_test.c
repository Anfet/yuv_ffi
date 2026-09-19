/*
 * Smoke test that demonstrates the harness correctly catches assertion failures.
 *
 * This test intentionally fails to prove that:
 *  1. The test harness is properly configured
 *  2. Failures are detected and reported
 *  3. The exit code reflects the failure, independent of optimization level
 *
 * CMake is configured to mark this test as WILL_FAIL, so the test suite passes
 * when this test fails, which proves the harness is working correctly.
 *
 * Unlike assert(3), which is compiled away with -DNDEBUG (Release builds),
 * this test signals failure unconditionally, in every build type.
 *
 * exit(1), not abort(), is what does that signaling. On this toolchain
 * (clang targeting x86_64-pc-windows-msvc), abort() links against the
 * release CRT (msvcrt, selected by CMAKE_C_FLAGS_RELEASE) and raises a
 * structured exception (observed exit status 0xc0000409, i.e.
 * STATUS_STACK_BUFFER_OVERRUN, the CRT's fail-fast signal) instead of
 * returning a plain nonzero exit code. CTest's WILL_FAIL only recognizes a
 * plain nonzero process exit code as "the command failed"; it reports that
 * same abort() as an "Exception" and fails the WILL_FAIL test in Release,
 * even though nothing regressed -- verified by comparing the debug CRT
 * (msvcrtd, Debug config) against the release CRT (msvcrt, Release config)
 * with everything else held fixed. exit(1) leaves no such ambiguity: it is
 * always a plain nonzero exit code, in both CRT variants.
 */

#include <stdlib.h>

int main(void) {
    /* This intentionally failing condition demonstrates that the test harness
     * correctly detects and reports failures. The CMake test is configured with
     * WILL_FAIL TRUE, so this failure is the expected and correct behavior.
     *
     * Volatile variables ensure the compiler cannot optimize away the condition
     * at compile time; the comparison must be evaluated at runtime, independent
     * of optimization level.
     */
    volatile int actual = 1;
    volatile int expected = 2;
    if (actual == expected) {
        return EXIT_SUCCESS;
    }
    exit(1);
}
