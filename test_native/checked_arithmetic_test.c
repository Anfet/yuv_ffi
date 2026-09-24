#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <limits.h>
#include <assert.h>

#include "yuv/utils/h/checked_arithmetic.h"

/* Test counter for summary reporting */
static int test_count = 0;
static int test_pass = 0;

#define ASSERT_EQUAL(actual, expected, msg) \
    do { \
        if ((actual) != (expected)) { \
            fprintf(stderr, "FAIL: %s (expected %llu, got %llu)\n", (msg), (unsigned long long)(expected), (unsigned long long)(actual)); \
            abort(); \
        } \
    } while (0)

#define ASSERT_TRUE(condition, msg) \
    do { \
        if (!(condition)) { \
            fprintf(stderr, "FAIL at test #%d: %s\n", test_count, (msg)); \
            abort(); \
        } \
    } while (0)

#define TEST_CASE(name) \
    printf("  %s\n", (name)); \
    test_count++; \
    test_pass++;

/* ============================================================================
 * Tests for yuv_checked_add
 * ============================================================================ */

static void test_checked_add_basic(void) {
    printf("Testing yuv_checked_add...\n");

    /* 0 + 0 = 0 */
    TEST_CASE("0 + 0 = 0");
    YuvSizeResult r = yuv_checked_add(0, 0);
    ASSERT_TRUE(r.success, "0 + 0 should succeed");
    ASSERT_EQUAL(r.value, 0, "0 + 0 should equal 0");

    /* 1 + 1 = 2 */
    TEST_CASE("1 + 1 = 2");
    r = yuv_checked_add(1, 1);
    ASSERT_TRUE(r.success, "1 + 1 should succeed");
    ASSERT_EQUAL(r.value, 2, "1 + 1 should equal 2");

    /* 100 + 200 = 300 */
    TEST_CASE("100 + 200 = 300");
    r = yuv_checked_add(100, 200);
    ASSERT_TRUE(r.success, "100 + 200 should succeed");
    ASSERT_EQUAL(r.value, 300, "100 + 200 should equal 300");

    /* SIZE_MAX - 1 + 0 = SIZE_MAX - 1 */
    TEST_CASE("(SIZE_MAX - 1) + 0 = SIZE_MAX - 1");
    r = yuv_checked_add(SIZE_MAX - 1, 0);
    ASSERT_TRUE(r.success, "(SIZE_MAX - 1) + 0 should succeed");
    ASSERT_EQUAL(r.value, SIZE_MAX - 1, "(SIZE_MAX - 1) + 0 should equal SIZE_MAX - 1");

    /* SIZE_MAX - 1 + 1 = SIZE_MAX */
    TEST_CASE("(SIZE_MAX - 1) + 1 = SIZE_MAX");
    r = yuv_checked_add(SIZE_MAX - 1, 1);
    ASSERT_TRUE(r.success, "(SIZE_MAX - 1) + 1 should succeed");
    ASSERT_EQUAL(r.value, SIZE_MAX, "(SIZE_MAX - 1) + 1 should equal SIZE_MAX");

    /* SIZE_MAX + 1 should overflow */
    TEST_CASE("SIZE_MAX + 1 should overflow");
    r = yuv_checked_add(SIZE_MAX, 1);
    ASSERT_TRUE(!r.success, "SIZE_MAX + 1 should overflow");

    /* SIZE_MAX + SIZE_MAX should overflow */
    TEST_CASE("SIZE_MAX + SIZE_MAX should overflow");
    r = yuv_checked_add(SIZE_MAX, SIZE_MAX);
    ASSERT_TRUE(!r.success, "SIZE_MAX + SIZE_MAX should overflow");

    /* 1 + SIZE_MAX should overflow */
    TEST_CASE("1 + SIZE_MAX should overflow");
    r = yuv_checked_add(1, SIZE_MAX);
    ASSERT_TRUE(!r.success, "1 + SIZE_MAX should overflow");
}

/* ============================================================================
 * Tests for yuv_checked_mul
 * ============================================================================ */

static void test_checked_mul_basic(void) {
    printf("Testing yuv_checked_mul...\n");

    /* 0 * anything = 0 */
    TEST_CASE("0 * 0 = 0");
    YuvSizeResult r = yuv_checked_mul(0, 0);
    ASSERT_TRUE(r.success, "0 * 0 should succeed");
    ASSERT_EQUAL(r.value, 0, "0 * 0 should equal 0");

    TEST_CASE("0 * SIZE_MAX = 0");
    r = yuv_checked_mul(0, SIZE_MAX);
    ASSERT_TRUE(r.success, "0 * SIZE_MAX should succeed");
    ASSERT_EQUAL(r.value, 0, "0 * SIZE_MAX should equal 0");

    TEST_CASE("SIZE_MAX * 0 = 0");
    r = yuv_checked_mul(SIZE_MAX, 0);
    ASSERT_TRUE(r.success, "SIZE_MAX * 0 should succeed");
    ASSERT_EQUAL(r.value, 0, "SIZE_MAX * 0 should equal 0");

    /* 1 * x = x */
    TEST_CASE("1 * 1 = 1");
    r = yuv_checked_mul(1, 1);
    ASSERT_TRUE(r.success, "1 * 1 should succeed");
    ASSERT_EQUAL(r.value, 1, "1 * 1 should equal 1");

    TEST_CASE("1 * SIZE_MAX = SIZE_MAX");
    r = yuv_checked_mul(1, SIZE_MAX);
    ASSERT_TRUE(r.success, "1 * SIZE_MAX should succeed");
    ASSERT_EQUAL(r.value, SIZE_MAX, "1 * SIZE_MAX should equal SIZE_MAX");

    /* 2 * 100 = 200 */
    TEST_CASE("2 * 100 = 200");
    r = yuv_checked_mul(2, 100);
    ASSERT_TRUE(r.success, "2 * 100 should succeed");
    ASSERT_EQUAL(r.value, 200, "2 * 100 should equal 200");

    /* 1920 * 1080 = 2,073,600 (typical 1080p) */
    TEST_CASE("1920 * 1080 = 2,073,600");
    r = yuv_checked_mul(1920, 1080);
    ASSERT_TRUE(r.success, "1920 * 1080 should succeed");
    ASSERT_EQUAL(r.value, 2073600, "1920 * 1080 should equal 2,073,600");

    /* (SIZE_MAX / 2) * 2 = SIZE_MAX - 1 or SIZE_MAX (depends on SIZE_MAX parity) */
    TEST_CASE("(SIZE_MAX / 2) * 2 should succeed");
    r = yuv_checked_mul(SIZE_MAX / 2, 2);
    ASSERT_TRUE(r.success, "(SIZE_MAX / 2) * 2 should succeed");

    /* (SIZE_MAX / 2 + 1) * 2 should overflow (exceeds SIZE_MAX) */
    TEST_CASE("(SIZE_MAX / 2 + 1) * 2 should overflow");
    r = yuv_checked_mul(SIZE_MAX / 2 + 1, 2);
    ASSERT_TRUE(!r.success, "(SIZE_MAX / 2 + 1) * 2 should overflow");

    /* SIZE_MAX * SIZE_MAX should overflow */
    TEST_CASE("SIZE_MAX * SIZE_MAX should overflow");
    r = yuv_checked_mul(SIZE_MAX, SIZE_MAX);
    ASSERT_TRUE(!r.success, "SIZE_MAX * SIZE_MAX should overflow");

    /* 2 * SIZE_MAX should overflow */
    TEST_CASE("2 * SIZE_MAX should overflow");
    r = yuv_checked_mul(2, SIZE_MAX);
    ASSERT_TRUE(!r.success, "2 * SIZE_MAX should overflow");
}

/* ============================================================================
 * Tests for yuv_checked_ceil_half
 * ============================================================================ */

static void test_checked_ceil_half(void) {
    printf("Testing yuv_checked_ceil_half...\n");

    /* ceil(0 / 2) = 0 */
    TEST_CASE("ceil(0 / 2) = 0");
    YuvSizeResult r = yuv_checked_ceil_half(0);
    ASSERT_TRUE(r.success, "ceil(0 / 2) should succeed");
    ASSERT_EQUAL(r.value, 0, "ceil(0 / 2) should equal 0");

    /* ceil(1 / 2) = 1 */
    TEST_CASE("ceil(1 / 2) = 1");
    r = yuv_checked_ceil_half(1);
    ASSERT_TRUE(r.success, "ceil(1 / 2) should succeed");
    ASSERT_EQUAL(r.value, 1, "ceil(1 / 2) should equal 1");

    /* ceil(2 / 2) = 1 */
    TEST_CASE("ceil(2 / 2) = 1");
    r = yuv_checked_ceil_half(2);
    ASSERT_TRUE(r.success, "ceil(2 / 2) should succeed");
    ASSERT_EQUAL(r.value, 1, "ceil(2 / 2) should equal 1");

    /* ceil(3 / 2) = 2 */
    TEST_CASE("ceil(3 / 2) = 2");
    r = yuv_checked_ceil_half(3);
    ASSERT_TRUE(r.success, "ceil(3 / 2) should succeed");
    ASSERT_EQUAL(r.value, 2, "ceil(3 / 2) should equal 2");

    /* ceil(4 / 2) = 2 */
    TEST_CASE("ceil(4 / 2) = 2");
    r = yuv_checked_ceil_half(4);
    ASSERT_TRUE(r.success, "ceil(4 / 2) should succeed");
    ASSERT_EQUAL(r.value, 2, "ceil(4 / 2) should equal 2");

    /* ceil(5 / 2) = 3 */
    TEST_CASE("ceil(5 / 2) = 3");
    r = yuv_checked_ceil_half(5);
    ASSERT_TRUE(r.success, "ceil(5 / 2) should succeed");
    ASSERT_EQUAL(r.value, 3, "ceil(5 / 2) should equal 3");

    /* ceil(1920 / 2) = 960 */
    TEST_CASE("ceil(1920 / 2) = 960");
    r = yuv_checked_ceil_half(1920);
    ASSERT_TRUE(r.success, "ceil(1920 / 2) should succeed");
    ASSERT_EQUAL(r.value, 960, "ceil(1920 / 2) should equal 960");

    /* ceil(1921 / 2) = 961 */
    TEST_CASE("ceil(1921 / 2) = 961");
    r = yuv_checked_ceil_half(1921);
    ASSERT_TRUE(r.success, "ceil(1921 / 2) should succeed");
    ASSERT_EQUAL(r.value, 961, "ceil(1921 / 2) should equal 961");

    /* ceil(SIZE_MAX / 2) should never overflow (division always succeeds) */
    TEST_CASE("ceil(SIZE_MAX / 2) should succeed");
    r = yuv_checked_ceil_half(SIZE_MAX);
    ASSERT_TRUE(r.success, "ceil(SIZE_MAX / 2) should succeed");
}

/* ============================================================================
 * Tests for yuv_checked_plane_span
 * ============================================================================ */

static void test_checked_plane_span(void) {
    printf("Testing yuv_checked_plane_span...\n");

    /* width=0: span = sampleBytes */
    TEST_CASE("width=0, pixelStride=1, sampleBytes=1 -> span=1");
    YuvSizeResult r = yuv_checked_plane_span(0, 1, 1);
    ASSERT_TRUE(r.success, "width=0 should succeed");
    ASSERT_EQUAL(r.value, 1, "span should equal sampleBytes");

    TEST_CASE("width=0, pixelStride=4, sampleBytes=4 -> span=4");
    r = yuv_checked_plane_span(0, 4, 4);
    ASSERT_TRUE(r.success, "width=0 should succeed");
    ASSERT_EQUAL(r.value, 4, "span should equal sampleBytes");

    /* width=1: span = (1-1)*pixelStride + sampleBytes = sampleBytes */
    TEST_CASE("width=1, pixelStride=1, sampleBytes=1 -> span=1");
    r = yuv_checked_plane_span(1, 1, 1);
    ASSERT_TRUE(r.success, "width=1 should succeed");
    ASSERT_EQUAL(r.value, 1, "span should equal sampleBytes");

    TEST_CASE("width=1, pixelStride=4, sampleBytes=4 -> span=4");
    r = yuv_checked_plane_span(1, 4, 4);
    ASSERT_TRUE(r.success, "width=1 should succeed");
    ASSERT_EQUAL(r.value, 4, "span should equal sampleBytes");

    /* width=2: span = (2-1)*pixelStride + sampleBytes = pixelStride + sampleBytes */
    TEST_CASE("width=2, pixelStride=1, sampleBytes=1 -> span=2");
    r = yuv_checked_plane_span(2, 1, 1);
    ASSERT_TRUE(r.success, "width=2 should succeed");
    ASSERT_EQUAL(r.value, 2, "span should equal 2");

    TEST_CASE("width=2, pixelStride=4, sampleBytes=4 -> span=8");
    r = yuv_checked_plane_span(2, 4, 4);
    ASSERT_TRUE(r.success, "width=2 should succeed");
    ASSERT_EQUAL(r.value, 8, "span should equal 8");

    /* width=1920, pixelStride=1, sampleBytes=1: span = 1919 + 1 = 1920 */
    TEST_CASE("width=1920, pixelStride=1, sampleBytes=1 -> span=1920");
    r = yuv_checked_plane_span(1920, 1, 1);
    ASSERT_TRUE(r.success, "width=1920 should succeed");
    ASSERT_EQUAL(r.value, 1920, "span should equal 1920");

    /* width=1920, pixelStride=2, sampleBytes=2: span = (1920-1)*2 + 2 = 1919*2 + 2 = 3840 */
    TEST_CASE("width=1920, pixelStride=2, sampleBytes=2 -> span=3840");
    r = yuv_checked_plane_span(1920, 2, 2);
    ASSERT_TRUE(r.success, "width=1920 should succeed");
    ASSERT_EQUAL(r.value, 3840, "span should equal 3840");

    /* width=1920, pixelStride=4, sampleBytes=4: span = (1920-1)*4 + 4 = 1919*4 + 4 = 7680 */
    TEST_CASE("width=1920, pixelStride=4, sampleBytes=4 -> span=7680");
    r = yuv_checked_plane_span(1920, 4, 4);
    ASSERT_TRUE(r.success, "width=1920 should succeed");
    ASSERT_EQUAL(r.value, 7680, "span should equal 7680");

    /* span = (UINT32_MAX - 1) * UINT32_MAX + 1 = 18446744060824649731, which
       is the actual boundary case for this helper's widest legal inputs.
       Whether that fits depends on size_t's width, so the expectation is
       branched by SIZE_MAX rather than fixed at "always succeeds" (YUV-36g):
       on 64-bit size_t (SIZE_MAX == 2^64-1 == 18446744073709551615) the value
       fits with room to spare, so this must still succeed; on 32-bit size_t
       (SIZE_MAX == 2^32-1) it overflows by many orders of magnitude, and the
       library correctly reports that -- an unconditional "always succeeds"
       previously asserted the 64-bit answer on every platform, which is what
       made this test abort on a 32-bit build. Branching on SIZE_MAX (rather
       than accepting either outcome) keeps this case exercising the actual
       overflow boundary on both widths instead of degrading into a
       tautology. */
    TEST_CASE("width boundary: UINT32_MAX, pixelStride=UINT32_MAX");
    r = yuv_checked_plane_span(UINT32_MAX, UINT32_MAX, 1);
    /* span = (UINT32_MAX - 1) * UINT32_MAX + 1 = 18446744060824649731, which
       is the actual boundary case for this helper's widest legal inputs.
       Whether that fits depends on size_t's width, so the expectation is
       branched by preprocessor condition on SIZE_MAX (matching the
       `#if SIZE_MAX < UINT64_MAX` pattern already used later in this file for
       yuv_checked_sample_offset) rather than fixed at "always succeeds":
       on 64-bit size_t (SIZE_MAX == 2^64-1) the value fits with room to
       spare, so this must succeed; on 32-bit size_t (SIZE_MAX == 2^32-1) it
       overflows by many orders of magnitude, and the library correctly
       reports that -- an unconditional "always succeeds" previously asserted
       the 64-bit answer on every platform, which is what made this test
       abort on a 32-bit build. A runtime `if (SIZE_MAX >= ...)` was
       considered instead, but MSVC reports C4127 ("conditional expression is
       constant") for it under this harness's /W4 /WX, and the preprocessor
       form is already this file's established way of expressing exactly
       this condition. */
#if SIZE_MAX >= 18446744060824649731ULL
    ASSERT_TRUE(r.success, "boundary case must succeed on a size_t wide enough to hold it");
    ASSERT_EQUAL(r.value, 18446744060824649731ULL, "span should equal (UINT32_MAX-1)*UINT32_MAX+1");
#else
    ASSERT_TRUE(!r.success, "boundary case must overflow on a size_t too narrow to hold it");
#endif

    /* edge case: width=UINT32_MAX, pixelStride=1, sampleBytes=1 */
    TEST_CASE("width=UINT32_MAX, pixelStride=1, sampleBytes=1");
    r = yuv_checked_plane_span(UINT32_MAX, 1, 1);
    ASSERT_TRUE(r.success || !r.success, "boundary case handled");
}

/* ============================================================================
 * Tests for yuv_checked_plane_size
 * ============================================================================ */

static void test_checked_plane_size(void) {
    printf("Testing yuv_checked_plane_size...\n");

    /* height=0: size = minSpan */
    TEST_CASE("height=0, rowStride=1920, minSpan=1920 -> size=1920");
    YuvSizeResult r = yuv_checked_plane_size(0, 1920, 1920);
    ASSERT_TRUE(r.success, "height=0 should succeed");
    ASSERT_EQUAL(r.value, 1920, "size should equal minSpan");

    /* height=1: size = (1-1)*rowStride + minSpan = minSpan */
    TEST_CASE("height=1, rowStride=1920, minSpan=1920 -> size=1920");
    r = yuv_checked_plane_size(1, 1920, 1920);
    ASSERT_TRUE(r.success, "height=1 should succeed");
    ASSERT_EQUAL(r.value, 1920, "size should equal minSpan");

    /* height=2: size = (2-1)*rowStride + minSpan = rowStride + minSpan */
    TEST_CASE("height=2, rowStride=1920, minSpan=1920 -> size=3840");
    r = yuv_checked_plane_size(2, 1920, 1920);
    ASSERT_TRUE(r.success, "height=2 should succeed");
    ASSERT_EQUAL(r.value, 3840, "size should equal 3840");

    /* height=1080: size = (1080-1)*1920 + 1920 = 1079*1920 + 1920 = 1920*1080 = 2,073,600 */
    TEST_CASE("height=1080, rowStride=1920, minSpan=1920 -> size=2,073,600");
    r = yuv_checked_plane_size(1080, 1920, 1920);
    ASSERT_TRUE(r.success, "height=1080 should succeed");
    ASSERT_EQUAL(r.value, 2073600, "size should equal 2,073,600");

    /* I420 Y plane: width=1920, height=1080, pixelStride=1
       span = 1920, size = 1079*1920 + 1920 = 1920*1080 */
    TEST_CASE("I420 Y plane: 1920x1080");
    r = yuv_checked_plane_size(1080, 1920, 1920);
    ASSERT_TRUE(r.success, "I420 Y should succeed");
    ASSERT_EQUAL(r.value, 2073600, "I420 Y should equal 2,073,600");

    /* I420 U/V plane: width=960, height=540, pixelStride=1
       span = 960, size = 539*960 + 960 = 960*540 */
    TEST_CASE("I420 U plane: 960x540");
    r = yuv_checked_plane_size(540, 960, 960);
    ASSERT_TRUE(r.success, "I420 U should succeed");
    ASSERT_EQUAL(r.value, 518400, "I420 U should equal 518,400");

    /* overflow: height * rowStride overflows */
    TEST_CASE("height overflow: UINT32_MAX, rowStride=SIZE_MAX/2");
    r = yuv_checked_plane_size(UINT32_MAX, SIZE_MAX / 2, 1);
    ASSERT_TRUE(!r.success, "overflow should be detected");

#if SIZE_MAX < UINT64_MAX
    TEST_CASE("rowStride wider than size_t is rejected without narrowing");
    r = yuv_checked_plane_size(1, (uint64_t)SIZE_MAX + 1u, 1);
    ASSERT_TRUE(!r.success, "rowStride outside size_t must be rejected");

    TEST_CASE("minSpan wider than size_t is rejected without narrowing");
    r = yuv_checked_plane_size(1, 1, (uint64_t)SIZE_MAX + 1u);
    ASSERT_TRUE(!r.success, "minSpan outside size_t must be rejected");
#endif
}

/* ============================================================================
 * Tests for yuv_checked_sample_offset
 * ============================================================================ */

static void test_checked_sample_offset(void) {
    printf("Testing yuv_checked_sample_offset...\n");

    /* (0, 1920, 0, 1) -> 0*1920 + 0*1 = 0 */
    TEST_CASE("(y=0, rowStride=1920, x=0, pixelStride=1) -> offset=0");
    YuvSizeResult r = yuv_checked_sample_offset(0, 1920, 0, 1);
    ASSERT_TRUE(r.success, "should succeed");
    ASSERT_EQUAL(r.value, 0, "offset should equal 0");

    /* (1, 1920, 0, 1) -> 1*1920 + 0*1 = 1920 */
    TEST_CASE("(y=1, rowStride=1920, x=0, pixelStride=1) -> offset=1920");
    r = yuv_checked_sample_offset(1, 1920, 0, 1);
    ASSERT_TRUE(r.success, "should succeed");
    ASSERT_EQUAL(r.value, 1920, "offset should equal 1920");

    /* (0, 1920, 1, 1) -> 0*1920 + 1*1 = 1 */
    TEST_CASE("(y=0, rowStride=1920, x=1, pixelStride=1) -> offset=1");
    r = yuv_checked_sample_offset(0, 1920, 1, 1);
    ASSERT_TRUE(r.success, "should succeed");
    ASSERT_EQUAL(r.value, 1, "offset should equal 1");

    /* (1, 1920, 1, 1) -> 1*1920 + 1*1 = 1921 */
    TEST_CASE("(y=1, rowStride=1920, x=1, pixelStride=1) -> offset=1921");
    r = yuv_checked_sample_offset(1, 1920, 1, 1);
    ASSERT_TRUE(r.success, "should succeed");
    ASSERT_EQUAL(r.value, 1921, "offset should equal 1921");

    /* BGRA pixel (4 bytes): (y=540, rowStride=7680, x=960, pixelStride=4)
       540*7680 + 960*4 = 4,147,200 + 3,840 = 4,151,040 */
    TEST_CASE("BGRA (y=540, rowStride=7680, x=960, pixelStride=4) -> offset=4,151,040");
    r = yuv_checked_sample_offset(540, 7680, 960, 4);
    ASSERT_TRUE(r.success, "should succeed");
    ASSERT_EQUAL(r.value, 4151040, "offset should equal 4,151,040");

    /* offset = y * rowStride = UINT32_MAX * UINT32_MAX = (2^32-1)^2
       = 18446744065119617025. Same boundary-width issue as the plane_span
       case above (YUV-36g): this fits in a 64-bit size_t with room to spare,
       but overflows a 32-bit one by many orders of magnitude, so the
       expectation is branched the same way rather than fixed at "always
       succeeds". */
    TEST_CASE("overflow: y * rowStride with y=UINT32_MAX and rowStride=UINT32_MAX");
    r = yuv_checked_sample_offset(UINT32_MAX, UINT32_MAX, 0, 1);
#if SIZE_MAX >= 18446744065119617025ULL
    ASSERT_TRUE(r.success, "UINT32_MAX * UINT32_MAX must succeed on a size_t wide enough to hold it");
    ASSERT_EQUAL(r.value, (size_t)UINT32_MAX * UINT32_MAX, "value should match");
#else
    ASSERT_TRUE(!r.success, "UINT32_MAX * UINT32_MAX must overflow on a size_t too narrow to hold it");
#endif

#if SIZE_MAX < UINT64_MAX
    TEST_CASE("sample offset rejects rowStride wider than size_t without narrowing");
    r = yuv_checked_sample_offset(1, (uint64_t)SIZE_MAX + 1u, 0, 1);
    ASSERT_TRUE(!r.success, "rowStride outside size_t must be rejected");
#endif
}

/* ============================================================================
 * Main
 * ============================================================================ */

int main(void) {
    printf("Running checked arithmetic tests...\n\n");

    test_checked_add_basic();
    printf("\n");

    test_checked_mul_basic();
    printf("\n");

    test_checked_ceil_half();
    printf("\n");

    test_checked_plane_span();
    printf("\n");

    test_checked_plane_size();
    printf("\n");

    test_checked_sample_offset();
    printf("\n");

    printf("=============================================================\n");
    printf("All %d tests passed!\n", test_pass);
    printf("=============================================================\n");

    return EXIT_SUCCESS;
}
