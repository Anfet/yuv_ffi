/* Exercises ABI size gates with readable descriptors that end at a guard page. */

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "yuv/abi/h/yuv_ops_v1.h"
#include "yuv/abi/h/yuv_validate_v1.h"

#ifdef _WIN32
#include <windows.h>
#else
#include <sys/mman.h>
#include <unistd.h>
#endif

typedef struct GuardedRegion {
    void *mapping;
    size_t mappingSize;
    uint8_t *data;
} GuardedRegion;

static int failures = 0;

static GuardedRegion make_guarded_region(uint32_t value, size_t readableBytes) {
    GuardedRegion result = {0};
#ifdef _WIN32
    SYSTEM_INFO info;
    GetSystemInfo(&info);
    const size_t pageSize = info.dwPageSize;
    result.mappingSize = pageSize * 2;
    result.mapping = VirtualAlloc(NULL, result.mappingSize, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
    if (result.mapping == NULL) {
        return result;
    }
    DWORD previousProtection;
    if (!VirtualProtect((uint8_t *)result.mapping + pageSize, pageSize, PAGE_NOACCESS, &previousProtection)) {
        VirtualFree(result.mapping, 0, MEM_RELEASE);
        result.mapping = NULL;
        return result;
    }
#else
    const long pageSizeValue = sysconf(_SC_PAGESIZE);
    if (pageSizeValue <= 0) {
        return result;
    }
    const size_t pageSize = (size_t)pageSizeValue;
    result.mappingSize = pageSize * 2;
    result.mapping = mmap(NULL, result.mappingSize, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (result.mapping == MAP_FAILED) {
        result.mapping = NULL;
        return result;
    }
    if (mprotect((uint8_t *)result.mapping + pageSize, pageSize, PROT_NONE) != 0) {
        munmap(result.mapping, result.mappingSize);
        result.mapping = NULL;
        return result;
    }
#endif
    const size_t readablePageSize = result.mappingSize / 2;
    if (readableBytes > readablePageSize) {
#ifdef _WIN32
        VirtualFree(result.mapping, 0, MEM_RELEASE);
#else
        munmap(result.mapping, result.mappingSize);
#endif
        result.mapping = NULL;
        return result;
    }
    result.data = (uint8_t *)result.mapping + readablePageSize - readableBytes;
    memcpy(result.data, &value, sizeof(value));
    return result;
}

static void release_guarded_region(GuardedRegion guarded) {
    if (guarded.mapping == NULL) {
        return;
    }
#ifdef _WIN32
    VirtualFree(guarded.mapping, 0, MEM_RELEASE);
#else
    munmap(guarded.mapping, guarded.mappingSize);
#endif
}

static void expect_status(const char *name, YuvStatus actual, YuvStatus expected) {
    if (actual != expected) {
        fprintf(stderr, "FAIL %s: got %d, expected %d\n", name, (int)actual, (int)expected);
        failures++;
    }
}

static void expect_true(const char *name, int condition) {
    if (!condition) {
        fprintf(stderr, "FAIL %s\n", name);
        failures++;
    }
}

static YuvConstFrameV1 make_source(uint8_t *pixels) {
    YuvConstFrameV1 frame;
    memset(&frame, 0, sizeof(frame));
    frame.structSize = (uint32_t)sizeof(frame);
    frame.abiVersion = YUV_ABI_VERSION_1;
    frame.format = YUV_FORMAT_BGRA8888;
    frame.planeCount = 1;
    frame.width = 1;
    frame.height = 1;
    frame.colorMatrix = YUV_COLOR_MATRIX_NONE;
    frame.colorRange = YUV_COLOR_RANGE_NONE;
    frame.planes[0].length = 4;
    frame.planes[0].rowStride = 4;
    frame.planes[0].pixelStride = 4;
    frame.planes[0].sampleBytes = 4;
    frame.planes[0].data = pixels;
    return frame;
}

static YuvMutableFrameV1 make_destination(uint8_t *pixels) {
    YuvMutableFrameV1 frame;
    memset(&frame, 0, sizeof(frame));
    frame.structSize = (uint32_t)sizeof(frame);
    frame.abiVersion = YUV_ABI_VERSION_1;
    frame.format = YUV_FORMAT_BGRA8888;
    frame.planeCount = 1;
    frame.width = 1;
    frame.height = 1;
    frame.colorMatrix = YUV_COLOR_MATRIX_NONE;
    frame.colorRange = YUV_COLOR_RANGE_NONE;
    frame.planes[0].length = 4;
    frame.planes[0].rowStride = 4;
    frame.planes[0].pixelStride = 4;
    frame.planes[0].sampleBytes = 4;
    frame.planes[0].data = pixels;
    return frame;
}

int main(void) {
    uint8_t sourcePixels[4] = {1, 2, 3, 255};
    uint8_t destinationPixels[4] = {0xA5, 0xA5, 0xA5, 0xA5};
    YuvConstFrameV1 source = make_source(sourcePixels);
    YuvMutableFrameV1 destination = make_destination(destinationPixels);
    YuvEffectOptionsV1 options;
    memset(&options, 0, sizeof(options));
    options.structSize = (uint32_t)sizeof(options);
    options.abiVersion = YUV_ABI_VERSION_1;

    GuardedRegion shortConst = make_guarded_region((uint32_t)sizeof(uint32_t), 2 * sizeof(uint32_t));
    GuardedRegion shortMutable = make_guarded_region((uint32_t)sizeof(uint32_t), 2 * sizeof(uint32_t));
    GuardedRegion shortOptionsHeader = make_guarded_region((uint32_t)sizeof(uint32_t), sizeof(uint32_t));
    GuardedRegion shortOptionsOperation = make_guarded_region((uint32_t)sizeof(uint32_t), 2 * sizeof(uint32_t));
    expect_true("guard-page allocations succeeded", shortConst.data != NULL && shortMutable.data != NULL &&
        shortOptionsHeader.data != NULL && shortOptionsOperation.data != NULL);
    if (shortConst.data == NULL || shortMutable.data == NULL || shortOptionsHeader.data == NULL ||
        shortOptionsOperation.data == NULL) {
        release_guarded_region(shortConst);
        release_guarded_region(shortMutable);
        release_guarded_region(shortOptionsHeader);
        release_guarded_region(shortOptionsOperation);
        return 1;
    }
    expect_true("typed short descriptors are 8-byte aligned",
        ((uintptr_t)shortConst.data % 8) == 0 && ((uintptr_t)shortMutable.data % 8) == 0 &&
        ((uintptr_t)shortOptionsOperation.data % 8) == 0);

    YuvValidatedConstFrameView constView;
    expect_status("short const frame", yuv_validate_v1_const_frame((const YuvConstFrameV1 *)shortConst.data,
        &constView), YUV_STATUS_INVALID_ARGUMENT);
    YuvValidatedMutableFrameView mutableView;
    expect_status("short mutable frame", yuv_validate_v1_mutable_frame((YuvMutableFrameV1 *)shortMutable.data,
        &mutableView), YUV_STATUS_INVALID_ARGUMENT);
    expect_status("short options header", yuv_validate_v1_options_header(shortOptionsHeader.data,
        (uint32_t)sizeof(YuvEffectOptionsV1)), YUV_STATUS_INVALID_ARGUMENT);

    destination = make_destination(destinationPixels);
    expect_status("operation rejects short source", yuv_grayscale_v1((const YuvConstFrameV1 *)shortConst.data,
        &destination, &options), YUV_STATUS_INVALID_ARGUMENT);
    expect_true("short source leaves destination intact", destinationPixels[0] == 0xA5 && destinationPixels[1] == 0xA5 &&
        destinationPixels[2] == 0xA5 && destinationPixels[3] == 0xA5);

    destination = make_destination(destinationPixels);
    expect_status("operation rejects short destination", yuv_grayscale_v1(&source,
        (YuvMutableFrameV1 *)shortMutable.data, &options), YUV_STATUS_INVALID_ARGUMENT);
    expect_true("short destination leaves destination intact", destinationPixels[0] == 0xA5 &&
        destinationPixels[1] == 0xA5 && destinationPixels[2] == 0xA5 && destinationPixels[3] == 0xA5);

    expect_status("operation rejects short options", yuv_grayscale_v1(&source, &destination,
        (const YuvEffectOptionsV1 *)shortOptionsOperation.data), YUV_STATUS_INVALID_ARGUMENT);
    expect_true("short options leaves destination intact", destinationPixels[0] == 0xA5 && destinationPixels[1] == 0xA5 &&
        destinationPixels[2] == 0xA5 && destinationPixels[3] == 0xA5);

    expect_status("complete const frame", yuv_validate_v1_const_frame(&source, &constView), YUV_STATUS_OK);
    expect_status("complete mutable frame", yuv_validate_v1_mutable_frame(&destination, &mutableView), YUV_STATUS_OK);
    expect_status("complete options header", yuv_validate_v1_options_header(&options,
        (uint32_t)sizeof(options)), YUV_STATUS_OK);
    source.structSize += 32;
    destination.structSize += 32;
    options.structSize += 32;
    expect_status("larger const frame", yuv_validate_v1_const_frame(&source, &constView), YUV_STATUS_OK);
    expect_status("larger mutable frame", yuv_validate_v1_mutable_frame(&destination, &mutableView), YUV_STATUS_OK);
    expect_status("larger options header", yuv_validate_v1_options_header(&options,
        (uint32_t)sizeof(YuvEffectOptionsV1)), YUV_STATUS_OK);
    expect_status("null const frame", yuv_validate_v1_const_frame(NULL, &constView), YUV_STATUS_INVALID_ARGUMENT);
    expect_status("null mutable frame", yuv_validate_v1_mutable_frame(NULL, &mutableView), YUV_STATUS_INVALID_ARGUMENT);
    expect_status("null options header", yuv_validate_v1_options_header(NULL,
        (uint32_t)sizeof(YuvEffectOptionsV1)), YUV_STATUS_INVALID_ARGUMENT);

    release_guarded_region(shortConst);
    release_guarded_region(shortMutable);
    release_guarded_region(shortOptionsHeader);
    release_guarded_region(shortOptionsOperation);
    if (failures != 0) {
        fprintf(stderr, "%d ABI short descriptor checks failed\n", failures);
        return 1;
    }
    puts("abi_short_descriptor_tests passed");
    return 0;
}
