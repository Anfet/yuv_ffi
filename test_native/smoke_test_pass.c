/*
 * Smoke test that verifies the harness can run and pass normal tests.
 *
 * This test contains passing checks and demonstrates that:
 *  1. The test harness correctly identifies passing tests
 *  2. Normal positive checks work as expected
 *  3. The exit code is zero for successful tests
 *  4. Checks work in both Debug and Release builds (independent of -DNDEBUG)
 *
 * Uses explicit abort() on failure, matching checked_arithmetic_test.c and
 * validated_view_test.c, so checks are active in Release builds.
 */

#include <stdlib.h>
#include <stdio.h>

int main(void) {
    /* These checks all pass, demonstrating that the test harness
     * correctly handles successful test cases.
     *
     * Unlike assert(), which is compiled away with -DNDEBUG (Release),
     * these explicit checks work in both Debug and Release builds.
     *
     * Volatile variables ensure the compiler cannot optimize away the conditions
     * at compile time; comparisons must be evaluated at runtime, independent
     * of optimization level.
     */

    {
        volatile int actual = 1;
        volatile int expected = 1;
        if (!(actual == expected)) {
            fprintf(stderr, "FAIL: expected 1 == 1\n");
            abort();
        }
    }

    {
        volatile int a = 2;
        volatile int b = 2;
        volatile int sum = a + b;
        volatile int expected = 4;
        if (!(sum == expected)) {
            fprintf(stderr, "FAIL: expected 2 + 2 == 4\n");
            abort();
        }
    }

    {
        volatile int actual = 0;
        volatile int expected = 0;
        if (!(actual == expected)) {
            fprintf(stderr, "FAIL: expected 0 == 0\n");
            abort();
        }
    }

    {
        volatile int actual = -1;
        volatile int expected = 0;
        if (!(actual < expected)) {
            fprintf(stderr, "FAIL: expected -1 < 0\n");
            abort();
        }
    }

    return EXIT_SUCCESS;
}
