

#include <stdlib.h>

/* This test intentionally returns a plain failure code; CTest marks it as
 * expected to fail so the harness behavior is checked in every build mode. */
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
