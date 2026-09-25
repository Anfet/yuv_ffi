/*
 * yuv_bench: native C benchmark harness for the 0.4.2 performance series (PERF-01).
 *
 * Specification: doc/perf/PERF-01-bench-setup.md. This file implements, in order:
 * the seeded xorshift32 inputs and their SHA-256 gate, the scenario matrix, the
 * per-iteration protocol, the adaptive warm-up/repetition rule, and the CSV record.
 *
 * One process measures one (version, scenario, size, round). The library under test
 * is loaded at run time from --dll, so a single harness build serves both the 0.2.4
 * DLL (legacy void symbols) and the ABI v1 DLL (yuv_*_v1 symbols); the harness is
 * never compiled into, or against, either library's sources.
 *
 * Windows only: QueryPerformanceCounter, CNG (bcrypt) and LoadLibraryExW.
 */

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef _CRT_SECURE_NO_WARNINGS
#define _CRT_SECURE_NO_WARNINGS
#endif

#include <windows.h>
#include <bcrypt.h>
#include <malloc.h>
#include <math.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Types only (descriptors, options, status codes); it declares no symbols. */
#include "yuv_abi_v1.h"

#define BENCH_TIMEOUT_MS 120000.0
#define BENCH_PREFILL 0xCD

enum { FMT_I420 = 1, FMT_NV12 = 2, FMT_BGRA = 3, FMT_RGBA = 4 };

static const char *fmt_name(int f) {
    switch (f) {
        case FMT_I420: return "I420";
        case FMT_NV12: return "NV12";
        case FMT_BGRA: return "BGRA";
        case FMT_RGBA: return "RGBA";
        default: return "?";
    }
}

static const char *fmt_file_name(int f) {
    switch (f) {
        case FMT_I420: return "i420";
        case FMT_NV12: return "nv12";
        case FMT_BGRA: return "bgra";
        case FMT_RGBA: return "rgba";
        default: return "?";
    }
}

/* ===========================================================================
 * Small utilities
 * =========================================================================== */

typedef struct {
    char *s;
    size_t len;
    size_t cap;
    int fields;
} Str;

static void str_reserve(Str *b, size_t extra) {
    if (b->len + extra + 1 <= b->cap) return;
    size_t cap = b->cap ? b->cap : 256;
    while (cap < b->len + extra + 1) cap *= 2;
    char *p = (char *)realloc(b->s, cap);
    if (!p) {
        fprintf(stderr, "yuv_bench: out of memory\n");
        exit(1);
    }
    b->s = p;
    b->cap = cap;
}

static void str_addf(Str *b, const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    int n = _vscprintf(fmt, ap);
    va_end(ap);
    if (n < 0) return;
    str_reserve(b, (size_t)n);
    va_start(ap, fmt);
    vsnprintf(b->s + b->len, (size_t)n + 1, fmt, ap);
    va_end(ap);
    b->len += (size_t)n;
}

/* The record is unquoted CSV, so separators inside a value are neutralised here
 * rather than trusted to every caller. */
static void csv_field(Str *b, const char *v) {
    if (b->fields++ > 0) str_addf(b, ",");
    size_t start = b->len;
    str_addf(b, "%s", v ? v : "");
    for (size_t i = start; i < b->len; ++i) {
        if (b->s[i] == ',' || b->s[i] == '\r' || b->s[i] == '\n') b->s[i] = ';';
    }
}

static void csv_fieldf(Str *b, const char *fmt, ...) {
    char tmp[512];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(tmp, sizeof(tmp), fmt, ap);
    va_end(ap);
    csv_field(b, tmp);
}

static wchar_t *widen(const char *utf8) {
    int n = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, NULL, 0);
    wchar_t *w = (wchar_t *)malloc(sizeof(wchar_t) * (size_t)(n > 0 ? n : 1));
    if (!w) exit(1);
    if (n <= 0 || !MultiByteToWideChar(CP_UTF8, 0, utf8, -1, w, n)) w[0] = 0;
    return w;
}

static char *narrow(const wchar_t *w) {
    int n = WideCharToMultiByte(CP_UTF8, 0, w, -1, NULL, 0, NULL, NULL);
    char *s = (char *)malloc((size_t)(n > 0 ? n : 1));
    if (!s) exit(1);
    if (n <= 0 || !WideCharToMultiByte(CP_UTF8, 0, w, -1, s, n, NULL, NULL)) s[0] = 0;
    return s;
}

static void utc_now(char *buf, size_t n) {
    SYSTEMTIME st;
    GetSystemTime(&st);
    snprintf(buf, n, "%04u-%02u-%02uT%02u:%02u:%02u.%03uZ", st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute,
        st.wSecond, st.wMilliseconds);
}

/* ===========================================================================
 * Scenario matrix (doc: "Scenario matrix")
 * =========================================================================== */

typedef enum { OP_CVT, OP_FLIP, OP_ROT, OP_CROP, OP_GRAY, OP_BW, OP_NEG, OP_SWAP, OP_BOX, OP_MEAN, OP_GAUSS } OpKind;

static const char *const kOpName[] = { "convert", "flip", "rotate", "crop", "grayscale", "black_white", "negate",
    "chroma_swap", "box_blur", "mean_blur", "gaussian_blur" };

static const char *const kAbiSymbol[] = { "yuv_convert_v1", "yuv_flip_v1", "yuv_rotate_v1", "yuv_crop_v1",
    "yuv_grayscale_v1", "yuv_black_white_v1", "yuv_negate_v1", "yuv_chroma_swap_v1", "yuv_box_blur_v1",
    "yuv_mean_blur_v1", "yuv_gaussian_blur_v1" };

typedef struct {
    char id[32];
    OpKind op;
    int src;
    int dst;
    int arg;   /* flip direction | rotation degrees | crop odd flag | blur radius */
    int sigma; /* Gaussian only */
    int roi;
    int only1080;
} Scenario;

static Scenario g_matrix[96];
static int g_matrix_count;

static void add_scenario(const char *id, OpKind op, int src, int dst, int arg, int sigma, int roi, int only1080) {
    Scenario *s = &g_matrix[g_matrix_count++];
    memset(s, 0, sizeof(*s));
    snprintf(s->id, sizeof(s->id), "%s", id);
    s->op = op;
    s->src = src;
    s->dst = dst;
    s->arg = arg;
    s->sigma = sigma;
    s->roi = roi;
    s->only1080 = only1080;
}

static void build_matrix(void) {
    static const int kCvtSrc[] = { FMT_I420, FMT_NV12, FMT_BGRA, FMT_RGBA };
    static const int kPix[] = { FMT_I420, FMT_NV12, FMT_BGRA };
    static const int kRot[] = { 0, 90, 180, 270 };
    static const struct { const char *tag; OpKind op; } kEffects[] = { { "GRAY", OP_GRAY }, { "BW", OP_BW }, { "NEG", OP_NEG } };
    static const struct { const char *tag; OpKind op; } kBlurs[] = { { "BOX", OP_BOX }, { "MEAN", OP_MEAN } };
    char id[32];

    for (int s = 0; s < 4; ++s) {
        for (int d = 0; d < 3; ++d) {
            snprintf(id, sizeof(id), "CVT.%s.%s", fmt_name(kCvtSrc[s]), fmt_name(kPix[d]));
            add_scenario(id, OP_CVT, kCvtSrc[s], kPix[d], 0, 0, 0, 0);
        }
    }
    for (int f = 0; f < 3; ++f) {
        const char *n = fmt_name(kPix[f]);
        snprintf(id, sizeof(id), "FLIP.%s.H", n);
        add_scenario(id, OP_FLIP, kPix[f], kPix[f], (int)YUV_FLIP_HORIZONTAL, 0, 0, 0);
        snprintf(id, sizeof(id), "FLIP.%s.V", n);
        add_scenario(id, OP_FLIP, kPix[f], kPix[f], (int)YUV_FLIP_VERTICAL, 0, 0, 0);
    }
    for (int f = 0; f < 3; ++f) {
        for (int r = 0; r < 4; ++r) {
            snprintf(id, sizeof(id), "ROT.%s.%d", fmt_name(kPix[f]), kRot[r]);
            add_scenario(id, OP_ROT, kPix[f], kPix[f], kRot[r], 0, 0, 0);
        }
    }
    for (int f = 0; f < 3; ++f) {
        snprintf(id, sizeof(id), "CROP.%s.EVEN", fmt_name(kPix[f]));
        add_scenario(id, OP_CROP, kPix[f], kPix[f], 0, 0, 0, 0);
        snprintf(id, sizeof(id), "CROP.%s.ODD", fmt_name(kPix[f]));
        add_scenario(id, OP_CROP, kPix[f], kPix[f], 1, 0, 0, 0);
    }
    for (int e = 0; e < 3; ++e) {
        for (int f = 0; f < 3; ++f) {
            snprintf(id, sizeof(id), "%s.%s.FULL", kEffects[e].tag, fmt_name(kPix[f]));
            add_scenario(id, kEffects[e].op, kPix[f], kPix[f], 0, 0, 0, 0);
            snprintf(id, sizeof(id), "%s.%s.ROI", kEffects[e].tag, fmt_name(kPix[f]));
            add_scenario(id, kEffects[e].op, kPix[f], kPix[f], 0, 0, 1, 0);
        }
    }
    add_scenario("SWAP.NV12", OP_SWAP, FMT_NV12, FMT_NV12, 0, 0, 0, 0);
    for (int b = 0; b < 2; ++b) {
        for (int f = 0; f < 3; ++f) {
            const char *n = fmt_name(kPix[f]);
            snprintf(id, sizeof(id), "%s.%s.R1", kBlurs[b].tag, n);
            add_scenario(id, kBlurs[b].op, kPix[f], kPix[f], 1, 0, 0, 0);
            snprintf(id, sizeof(id), "%s.%s.R10", kBlurs[b].tag, n);
            add_scenario(id, kBlurs[b].op, kPix[f], kPix[f], 10, 0, 0, 0);
            snprintf(id, sizeof(id), "%s.%s.R10.ROI", kBlurs[b].tag, n);
            add_scenario(id, kBlurs[b].op, kPix[f], kPix[f], 10, 0, 1, 0);
            snprintf(id, sizeof(id), "%s.%s.R256", kBlurs[b].tag, n);
            add_scenario(id, kBlurs[b].op, kPix[f], kPix[f], 256, 0, 0, 1);
        }
    }
    for (int f = 0; f < 3; ++f) {
        snprintf(id, sizeof(id), "GAUSS.%s.R2S2", fmt_name(kPix[f]));
        add_scenario(id, OP_GAUSS, kPix[f], kPix[f], 2, 2, 0, 0);
        snprintf(id, sizeof(id), "GAUSS.%s.R10S10", fmt_name(kPix[f]));
        add_scenario(id, OP_GAUSS, kPix[f], kPix[f], 10, 10, 0, 0);
    }
}

static const Scenario *find_scenario(const char *id) {
    for (int i = 0; i < g_matrix_count; ++i) {
        if (strcmp(g_matrix[i].id, id) == 0) return &g_matrix[i];
    }
    return NULL;
}

static int is_effect(OpKind op) { return op == OP_GRAY || op == OP_BW || op == OP_NEG; }
static int is_rect_blur(OpKind op) { return op == OP_BOX || op == OP_MEAN; }

/* Centered ROI [w/4, h/4, 3w/4, 3h/4), right/bottom-exclusive in both versions. */
static void roi_of(uint32_t w, uint32_t h, uint32_t r[4]) {
    r[0] = w / 4;
    r[1] = h / 4;
    r[2] = 3 * w / 4;
    r[3] = 3 * h / 4;
}

/* (left, top, width, height): even = (w/4, h/4, w/2, h/2), odd = each origin +1, each extent -1. */
static void crop_of(const Scenario *s, uint32_t w, uint32_t h, uint32_t c[4]) {
    uint32_t k = s->arg ? 1u : 0u;
    c[0] = w / 4 + k;
    c[1] = h / 4 + k;
    c[2] = w / 2 - k;
    c[3] = h / 2 - k;
}

static void scenario_params(const Scenario *s, uint32_t w, uint32_t h, char *buf, size_t n) {
    uint32_t r[4];
    switch (s->op) {
        case OP_CVT: snprintf(buf, n, "-"); break;
        case OP_FLIP: snprintf(buf, n, "direction=%s", s->arg == (int)YUV_FLIP_HORIZONTAL ? "H" : "V"); break;
        case OP_ROT: snprintf(buf, n, "degrees=%d", s->arg); break;
        case OP_CROP:
            crop_of(s, w, h, r);
            snprintf(buf, n, "left=%u;top=%u;width=%u;height=%u", r[0], r[1], r[2], r[3]);
            break;
        case OP_GAUSS: snprintf(buf, n, "radius=%d;sigma=%d", s->arg, s->sigma); break;
        default: {
            char region[64];
            if (s->roi) {
                roi_of(w, h, r);
                snprintf(region, sizeof(region), "region=%u:%u:%u:%u", r[0], r[1], r[2], r[3]);
            } else {
                snprintf(region, sizeof(region), "region=off");
            }
            if (is_rect_blur(s->op)) {
                snprintf(buf, n, "radius=%d;%s", s->arg, region);
            } else {
                snprintf(buf, n, "%s", region);
            }
        }
    }
}

/* ===========================================================================
 * Images (tight canonical layout, doc: "Formats and layout")
 * =========================================================================== */

typedef struct {
    int fmt;
    uint32_t w;
    uint32_t h;
    int np;
    uint8_t *p[3];
    size_t len[3];
    size_t rs[3];
    uint32_t ps[3];
} Img;

static int img_alloc(Img *im, int fmt, uint32_t w, uint32_t h) {
    memset(im, 0, sizeof(*im));
    const size_t cw = (w + 1) / 2;
    const size_t ch = (h + 1) / 2;
    im->fmt = fmt;
    im->w = w;
    im->h = h;
    switch (fmt) {
        case FMT_I420:
            im->np = 3;
            im->len[0] = (size_t)w * h, im->rs[0] = w, im->ps[0] = 1;
            im->len[1] = cw * ch, im->rs[1] = cw, im->ps[1] = 1;
            im->len[2] = cw * ch, im->rs[2] = cw, im->ps[2] = 1;
            break;
        case FMT_NV12:
            im->np = 2;
            im->len[0] = (size_t)w * h, im->rs[0] = w, im->ps[0] = 1;
            im->len[1] = 2 * cw * ch, im->rs[1] = 2 * cw, im->ps[1] = 2;
            break;
        case FMT_BGRA:
        case FMT_RGBA:
            im->np = 1;
            im->len[0] = (size_t)4 * w * h, im->rs[0] = (size_t)4 * w, im->ps[0] = 4;
            break;
        default: return 0;
    }
    for (int i = 0; i < im->np; ++i) {
        /* 64-byte aligned for both versions alike, so alignment never differs between rows. */
        im->p[i] = (uint8_t *)_aligned_malloc(im->len[i], 64);
        if (!im->p[i]) return 0;
    }
    return 1;
}

static void img_free(Img *im) {
    for (int i = 0; i < 3; ++i) {
        if (im->p[i]) _aligned_free(im->p[i]);
        im->p[i] = NULL;
    }
}

static void img_copy(Img *dst, const Img *src) {
    for (int i = 0; i < src->np; ++i) memcpy(dst->p[i], src->p[i], src->len[i]);
}

static void img_fill(Img *im, uint8_t v) {
    for (int i = 0; i < im->np; ++i) memset(im->p[i], v, im->len[i]);
}

/* ===========================================================================
 * Deterministic inputs (doc: "Generation (deterministic seed)")
 * =========================================================================== */

#define SEED_Y 0x2026A001u
#define SEED_U 0x2026A002u
#define SEED_V 0x2026A003u
#define SEED_BGRA 0x2026A004u

static uint32_t g_xs;

static uint8_t xs_next(void) {
    g_xs ^= g_xs << 13;
    g_xs ^= g_xs >> 17;
    g_xs ^= g_xs << 5;
    return (uint8_t)(g_xs >> 24);
}

static void xs_fill(uint32_t seed, uint8_t *out, size_t n) {
    g_xs = seed;
    for (size_t i = 0; i < n; ++i) out[i] = xs_next();
}

static int generate_input(Img *im) {
    const size_t n = (size_t)im->w * im->h;
    switch (im->fmt) {
        case FMT_I420:
            xs_fill(SEED_Y, im->p[0], im->len[0]);
            xs_fill(SEED_U, im->p[1], im->len[1]);
            xs_fill(SEED_V, im->p[2], im->len[2]);
            return 1;
        case FMT_NV12: {
            const size_t c = im->len[1] / 2;
            uint8_t *u = (uint8_t *)malloc(c);
            uint8_t *v = (uint8_t *)malloc(c);
            if (!u || !v) {
                free(u);
                free(v);
                return 0;
            }
            xs_fill(SEED_Y, im->p[0], im->len[0]);
            xs_fill(SEED_U, u, c);
            xs_fill(SEED_V, v, c);
            for (size_t i = 0; i < c; ++i) {
                im->p[1][2 * i] = u[i];
                im->p[1][2 * i + 1] = v[i];
            }
            free(u);
            free(v);
            return 1;
        }
        case FMT_BGRA:
        case FMT_RGBA: {
            const int rgba = im->fmt == FMT_RGBA;
            uint8_t *p = im->p[0];
            g_xs = SEED_BGRA;
            for (size_t i = 0; i < n; ++i) {
                const uint8_t b = xs_next();
                const uint8_t g = xs_next();
                const uint8_t r = xs_next();
                p[4 * i + 0] = rgba ? r : b;
                p[4 * i + 1] = g;
                p[4 * i + 2] = rgba ? b : r;
                p[4 * i + 3] = 255;
            }
            return 1;
        }
        default: return 0;
    }
}

/* Verified reference checksums of the tight concatenation (doc: "Input checksums"). */
static const struct {
    const char *name;
    const char *sha;
} kInputSha[] = {
    { "i420_1920x1080", "71c06f9341e998b2308625dedffb1555a57cacdb4b1479630039dab4febfc0b4" },
    { "nv12_1920x1080", "c08dec9993df462f7d96eb3e765ab97b2ac69d86f7bf13e60740ce5c3d4ee652" },
    { "bgra_1920x1080", "4a107f2e1d3895761980b2c7e5eecc1a587bffc27626b96868c9c94306dc22a9" },
    { "rgba_1920x1080", "1484337a8687599525ff9941412f83613e25e64b32cb9906f2cdf34f0d4238d7" },
    { "i420_4000x3000", "282dc210cc232feb071c75483df66bc14373c7c90d1842a8c9136a3778ceb287" },
    { "nv12_4000x3000", "cf70f5e6e0ccee46a5615ba49318d698600ec6a569280d4cc881f38be966d0aa" },
    { "bgra_4000x3000", "46cc62c75007006f05e66a39eaf8257a90091f9a97617ca16676a043a5d75146" },
    { "rgba_4000x3000", "7775779ef9d1ad4c02c11b50d26cec342666863bdb4a1019b6317bb802ad0328" },
    { "i420_1921x1081", "0f27396ee703e7e50717df8f2c06323af932efd8c11b4dbbc30a32269a518254" },
    { "nv12_1921x1081", "78668007539aabdcfae1266889fa4541d17e1e3d84355c85ef597167960b87f9" },
    { "bgra_1921x1081", "f1ef8370d694287d1a0de38ae192ab9cf663fa9d51969d20268dc7c546349023" },
    { "rgba_1921x1081", "6a17bfd1b048f1235a0bb023ba5f0c4ae7f3a29c2fb4846b203eef971623f4a9" },
};

static const char *expected_input_sha(const char *name) {
    for (size_t i = 0; i < sizeof(kInputSha) / sizeof(kInputSha[0]); ++i) {
        if (strcmp(kInputSha[i].name, name) == 0) return kInputSha[i].sha;
    }
    return NULL;
}

/* SHA-256 of the planes in plane order. Tight layout, so the active samples are the whole buffers. */
static int sha256_img(const Img *im, char hex[65]) {
    BCRYPT_ALG_HANDLE alg = NULL;
    BCRYPT_HASH_HANDLE h = NULL;
    UCHAR digest[32];
    int ok = 0;
    if (BCryptOpenAlgorithmProvider(&alg, BCRYPT_SHA256_ALGORITHM, NULL, 0) < 0) return 0;
    if (BCryptCreateHash(alg, &h, NULL, 0, NULL, 0, 0) >= 0) {
        ok = 1;
        for (int i = 0; i < im->np && ok; ++i) {
            if (BCryptHashData(h, (PUCHAR)im->p[i], (ULONG)im->len[i], 0) < 0) ok = 0;
        }
        if (ok && BCryptFinishHash(h, digest, sizeof(digest), 0) < 0) ok = 0;
        BCryptDestroyHash(h);
    }
    BCryptCloseAlgorithmProvider(alg, 0);
    if (!ok) return 0;
    for (int i = 0; i < 32; ++i) snprintf(hex + 2 * i, 3, "%02x", digest[i]);
    return 1;
}

static int load_cached(const wchar_t *path, Img *im) {
    FILE *f = _wfopen(path, L"rb");
    if (!f) return 0;
    int ok = 1;
    for (int i = 0; i < im->np && ok; ++i) {
        if (fread(im->p[i], 1, im->len[i], f) != im->len[i]) ok = 0;
    }
    if (ok && fgetc(f) != EOF) ok = 0;
    fclose(f);
    return ok;
}

static void store_cached(const wchar_t *dir, const wchar_t *path, const Img *im) {
    CreateDirectoryW(dir, NULL);
    FILE *f = _wfopen(path, L"wb");
    if (!f) {
        fprintf(stderr, "yuv_bench: warning: cannot write input cache\n");
        return;
    }
    for (int i = 0; i < im->np; ++i) fwrite(im->p[i], 1, im->len[i], f);
    fclose(f);
}

/*
 * Fills `im` with the canonical input and refuses (returns 0 with a reason) unless its
 * SHA-256 equals the reference. A cached file is only a shortcut: one that fails the
 * gate is regenerated and overwritten, and the regenerated bytes must pass it.
 */
static int prepare_input(Img *im, const char *input_dir, char *reason, size_t rn) {
    char name[64];
    snprintf(name, sizeof(name), "%s_%ux%u", fmt_file_name(im->fmt), im->w, im->h);
    const char *expected = expected_input_sha(name);
    if (!expected) {
        snprintf(reason, rn, "no reference input checksum for %s", name);
        return 0;
    }
    char path_utf8[1024];
    snprintf(path_utf8, sizeof(path_utf8), "%s\\%s.bin", input_dir, name);
    wchar_t *wdir = widen(input_dir);
    wchar_t *wpath = widen(path_utf8);
    char hex[65] = { 0 };
    int ok = 0;
    if (load_cached(wpath, im) && sha256_img(im, hex) && strcmp(hex, expected) == 0) {
        ok = 1;
    } else {
        if (hex[0]) fprintf(stderr, "yuv_bench: cached %s failed the checksum gate, regenerating\n", path_utf8);
        if (generate_input(im) && sha256_img(im, hex) && strcmp(hex, expected) == 0) {
            store_cached(wdir, wpath, im);
            ok = 1;
        } else {
            snprintf(reason, rn, "generated %s sha256 %s != reference %s", name, hex, expected);
        }
    }
    free(wdir);
    free(wpath);
    return ok;
}

/* ===========================================================================
 * 0.2.4 legacy surface (doc: "Legacy 0.2.4 descriptor mapping")
 *
 * Mirrors src/yuv/yuv.h of tag 0.2.4 member for member. It is declared here because
 * the 0.2.4 tree is never part of this repository's build.
 * =========================================================================== */

typedef struct {
    uint8_t *y;
    uint8_t *u;
    uint8_t *v;
    int width;
    int height;
    int yRowStride;
    int yPixelStride;
    int uvRowStride;
    int uvPixelStride;
} YUVDef;

typedef void (*LegacyDef1Fn)(const YUVDef *);
typedef void (*LegacyDef2Fn)(const YUVDef *, const YUVDef *);
typedef void (*LegacyDefOutFn)(const YUVDef *, uint8_t *);
typedef void (*LegacyRgbaFn)(const uint8_t *, const YUVDef *);
typedef void (*LegacyRotFn)(const YUVDef *, const YUVDef *, int);
typedef void (*LegacyCropFn)(const YUVDef *, const YUVDef *, int, int, int, int);
typedef void (*LegacyBlurRectFn)(const YUVDef *, int, const uint32_t *);
typedef void (*LegacyGaussIntFn)(const YUVDef *, int, int);
typedef void (*LegacyGaussFloatFn)(const YUVDef *, int, float);
typedef void (*LegacySwapFn)(uint8_t *, uint8_t *, int, int, int);

typedef enum {
    LK_NONE,
    LK_DEF1,
    LK_DEF2,
    LK_DEF_OUT,
    LK_RGBA,
    LK_ROT,
    LK_CROP,
    LK_BLUR_RECT,
    LK_GAUSS_INT,
    LK_GAUSS_FLOAT,
    LK_SWAP
} LegacyKind;

static const char *legacy_prefix(int fmt) {
    switch (fmt) {
        case FMT_I420: return "yuv420";
        case FMT_NV12: return "nv21";
        case FMT_BGRA: return "bgra8888";
        default: return "?";
    }
}

/* Fills YUVDef exactly as the 0.2.4 Dart YUVDefClass did, over the tight buffers.
 * nv21: `u` is the start of the interleaved plane and `v` is NULL; the plane keeps the
 * NV12 byte order U,V (see the per-function UV table in the setup document). */
static void fill_def(YUVDef *d, const Img *im) {
    memset(d, 0, sizeof(*d));
    d->width = (int)im->w;
    d->height = (int)im->h;
    d->y = im->p[0];
    d->yRowStride = (int)im->rs[0];
    d->yPixelStride = (int)im->ps[0];
    switch (im->fmt) {
        case FMT_I420:
            d->u = im->p[1];
            d->v = im->p[2];
            d->uvRowStride = (int)im->rs[1];
            d->uvPixelStride = 1;
            break;
        case FMT_NV12:
            d->u = im->p[1];
            d->uvRowStride = (int)im->rs[1];
            d->uvPixelStride = 2;
            break;
        default:
            d->uvRowStride = 1;
            d->uvPixelStride = 1;
            break;
    }
}

/* Resolves the 0.2.4 symbol and call shape for a scenario. `inplace` is set for the rows
 * whose legacy kernel mutates its source (flip, effects, blurs). */
static int legacy_resolve(const Scenario *s, char *sym, size_t n, LegacyKind *kind, int *inplace) {
    const char *p = legacy_prefix(s->src);
    *inplace = 0;
    switch (s->op) {
        case OP_CVT: {
            static const struct { int src, dst; const char *sym; LegacyKind kind; } kCvt[] = {
                { FMT_I420, FMT_NV12, "yuv420_i420_to_nv21", LK_DEF2 },
                { FMT_I420, FMT_BGRA, "yuv420_to_bgra8888", LK_DEF_OUT },
                { FMT_NV12, FMT_I420, "nv21_to_i420", LK_DEF2 },
                { FMT_NV12, FMT_BGRA, "nv21_to_bgra8888", LK_DEF_OUT },
                { FMT_BGRA, FMT_I420, "bgra8888_to_i420", LK_DEF2 },
                { FMT_BGRA, FMT_NV12, "bgra8888_to_nv21", LK_DEF2 },
                { FMT_RGBA, FMT_I420, "yuv420_from_rgba8888", LK_RGBA },
                { FMT_RGBA, FMT_NV12, "nv21_from_rgba8888", LK_RGBA },
                { FMT_RGBA, FMT_BGRA, "bgra8888_from_rgba8888", LK_RGBA },
            };
            for (size_t i = 0; i < sizeof(kCvt) / sizeof(kCvt[0]); ++i) {
                if (kCvt[i].src == s->src && kCvt[i].dst == s->dst) {
                    snprintf(sym, n, "%s", kCvt[i].sym);
                    *kind = kCvt[i].kind;
                    return 1;
                }
            }
            return 0;
        }
        case OP_FLIP:
            snprintf(sym, n, "%s_flip_%s", p, s->arg == (int)YUV_FLIP_HORIZONTAL ? "horizontally" : "vertically");
            *kind = LK_DEF1;
            *inplace = 1;
            return 1;
        case OP_ROT:
            snprintf(sym, n, "%s_rotate", p);
            *kind = LK_ROT;
            return 1;
        case OP_CROP:
            snprintf(sym, n, "%s_crop_rect", p);
            *kind = LK_CROP;
            return 1;
        case OP_GRAY:
        case OP_BW:
        case OP_NEG:
            snprintf(sym, n, "%s_%s", p, s->op == OP_GRAY ? "grayscale" : s->op == OP_BW ? "blackwhite" : "negate");
            *kind = LK_DEF1;
            *inplace = 1;
            return 1;
        case OP_SWAP:
            snprintf(sym, n, "nvXX_to_nvYY");
            *kind = LK_SWAP;
            return 1;
        case OP_BOX:
        case OP_MEAN:
            snprintf(sym, n, "%s_%s", p, s->op == OP_BOX ? "box_blur" : "mean_blur");
            *kind = LK_BLUR_RECT;
            *inplace = 1;
            return 1;
        case OP_GAUSS:
            if (s->src == FMT_I420) {
                snprintf(sym, n, "yuv420_gaussblur");
                *kind = LK_GAUSS_INT;
            } else {
                snprintf(sym, n, "%s_gaussian_blur", p);
                *kind = LK_GAUSS_FLOAT;
            }
            *inplace = 1;
            return 1;
    }
    return 0;
}

/* ===========================================================================
 * Bench context
 * =========================================================================== */

typedef enum { VER_ABI_V1, VER_V024, VER_MEMCPY } Version;

typedef YuvStatus (*AbiFn)(const YuvConstFrameV1 *, YuvMutableFrameV1 *, const void *);

typedef struct {
    const Scenario *sc;
    Version ver;
    uint32_t w;
    uint32_t h;
    Img pristine;
    Img work;
    Img dst;
    int has_dst;

    AbiFn abi_fn;
    YuvConstFrameV1 src_frame;
    YuvMutableFrameV1 dst_frame;
    union {
        YuvConvertOptionsV1 cvt;
        YuvEffectOptionsV1 effect;
        YuvBlurOptionsV1 blur;
        YuvCropOptionsV1 crop;
        YuvFlipOptionsV1 flip;
        YuvRotateOptionsV1 rot;
    } opt;

    LegacyKind lk;
    FARPROC legacy_fn;
    YUVDef src_def;
    YUVDef dst_def;
    uint32_t rect[4];
    const uint32_t *rect_ptr;
    uint32_t crop[4];
} Bench;

static void color_of(int fmt, uint32_t *matrix, uint32_t *range) {
    if (fmt == FMT_I420 || fmt == FMT_NV12) {
        *matrix = YUV_COLOR_MATRIX_BT601;
        *range = YUV_COLOR_RANGE_LIMITED;
    } else {
        *matrix = YUV_COLOR_MATRIX_NONE;
        *range = YUV_COLOR_RANGE_NONE;
    }
}

static void const_frame(YuvConstFrameV1 *f, const Img *im) {
    memset(f, 0, sizeof(*f));
    f->structSize = sizeof(*f);
    f->abiVersion = YUV_ABI_VERSION_1;
    f->format = (uint32_t)im->fmt;
    f->planeCount = (uint32_t)im->np;
    f->width = im->w;
    f->height = im->h;
    color_of(im->fmt, &f->colorMatrix, &f->colorRange);
    for (int i = 0; i < im->np; ++i) {
        f->planes[i].length = im->len[i];
        f->planes[i].rowStride = im->rs[i];
        f->planes[i].pixelStride = im->ps[i];
        f->planes[i].sampleBytes = im->ps[i];
        f->planes[i].data = im->p[i];
    }
}

static void mutable_frame(YuvMutableFrameV1 *f, const Img *im) {
    memset(f, 0, sizeof(*f));
    f->structSize = sizeof(*f);
    f->abiVersion = YUV_ABI_VERSION_1;
    f->format = (uint32_t)im->fmt;
    f->planeCount = (uint32_t)im->np;
    f->width = im->w;
    f->height = im->h;
    color_of(im->fmt, &f->colorMatrix, &f->colorRange);
    for (int i = 0; i < im->np; ++i) {
        f->planes[i].length = im->len[i];
        f->planes[i].rowStride = im->rs[i];
        f->planes[i].pixelStride = im->ps[i];
        f->planes[i].sampleBytes = im->ps[i];
        f->planes[i].data = im->p[i];
    }
}

static YuvRegionOptionsV1 region_of(const Bench *b) {
    YuvRegionOptionsV1 r;
    memset(&r, 0, sizeof(r));
    r.structSize = sizeof(r);
    r.abiVersion = YUV_ABI_VERSION_1;
    if (b->sc->roi) {
        uint32_t q[4];
        roi_of(b->w, b->h, q);
        r.left = (int32_t)q[0];
        r.top = (int32_t)q[1];
        r.right = (int32_t)q[2];
        r.bottom = (int32_t)q[3];
        r.enabled = 1;
    }
    return r;
}

static void abi_options(Bench *b) {
    const Scenario *s = b->sc;
    memset(&b->opt, 0, sizeof(b->opt));
    switch (s->op) {
        case OP_CVT:
            b->opt.cvt.structSize = sizeof(b->opt.cvt);
            b->opt.cvt.abiVersion = YUV_ABI_VERSION_1;
            break;
        case OP_GRAY:
        case OP_BW:
        case OP_NEG:
        case OP_SWAP:
            b->opt.effect.structSize = sizeof(b->opt.effect);
            b->opt.effect.abiVersion = YUV_ABI_VERSION_1;
            b->opt.effect.region = region_of(b);
            break;
        case OP_BOX:
        case OP_MEAN:
        case OP_GAUSS:
            b->opt.blur.structSize = sizeof(b->opt.blur);
            b->opt.blur.abiVersion = YUV_ABI_VERSION_1;
            b->opt.blur.radius = (uint32_t)s->arg;
            b->opt.blur.borderMode = YUV_BORDER_CLAMP;
            b->opt.blur.sigma = s->op == OP_GAUSS ? (double)s->sigma : 0.0;
            b->opt.blur.region = region_of(b);
            break;
        case OP_CROP:
            b->opt.crop.structSize = sizeof(b->opt.crop);
            b->opt.crop.abiVersion = YUV_ABI_VERSION_1;
            b->opt.crop.left = (int32_t)b->crop[0];
            b->opt.crop.top = (int32_t)b->crop[1];
            b->opt.crop.width = b->crop[2];
            b->opt.crop.height = b->crop[3];
            break;
        case OP_FLIP:
            b->opt.flip.structSize = sizeof(b->opt.flip);
            b->opt.flip.abiVersion = YUV_ABI_VERSION_1;
            b->opt.flip.direction = (uint32_t)s->arg;
            break;
        case OP_ROT:
            b->opt.rot.structSize = sizeof(b->opt.rot);
            b->opt.rot.abiVersion = YUV_ABI_VERSION_1;
            b->opt.rot.rotationDegrees = (uint32_t)s->arg;
            break;
    }
}

static const char *na_reason(const Scenario *s, Version v, uint32_t w, uint32_t h) {
    if (v == VER_MEMCPY) {
        if (s->op != OP_CVT || s->src != s->dst) return "ref.memcpy is defined only for same-format CVT rows";
        return NULL;
    }
    if (v != VER_V024) return NULL;
    if ((w & 1u) || (h & 1u)) return "0.2.4 kernels assume even geometry; odd sizes are ABI v1 only";
    if (s->op == OP_CVT && s->src == s->dst) return "0.2.4 had no native same-format copy";
    if (s->op == OP_ROT && s->arg == 0) return "0.2.4 rotate(0) returned this without a native call";
    if (is_effect(s->op) && s->roi) return "0.2.4 effects had no ROI";
    return NULL;
}

static void dst_geometry(const Bench *b, int *fmt, uint32_t *dw, uint32_t *dh) {
    const Scenario *s = b->sc;
    *fmt = s->op == OP_CVT ? s->dst : s->src;
    *dw = b->w;
    *dh = b->h;
    if (s->op == OP_ROT && (s->arg == 90 || s->arg == 270)) {
        *dw = b->h;
        *dh = b->w;
    } else if (s->op == OP_CROP) {
        *dw = b->crop[2];
        *dh = b->crop[3];
    }
}

static int bench_prepare(Bench *b, const char *dll_path, const char *input_dir, char *reason, size_t rn) {
    const Scenario *s = b->sc;
    HMODULE lib = NULL;
    int inplace = 0;
    char sym[64] = { 0 };

    crop_of(s, b->w, b->h, b->crop);
    if (s->roi) {
        roi_of(b->w, b->h, b->rect);
        b->rect_ptr = b->rect;
    }

    if (b->ver != VER_MEMCPY) {
        wchar_t *wdll = widen(dll_path);
        /* Altered search path: the DLL's own dependencies resolve next to it, never from the CWD. */
        lib = LoadLibraryExW(wdll, NULL, LOAD_WITH_ALTERED_SEARCH_PATH);
        free(wdll);
        if (!lib) {
            snprintf(reason, rn, "LoadLibraryExW(%s) failed: error %lu", dll_path, GetLastError());
            return 0;
        }
        if (b->ver == VER_ABI_V1) {
            snprintf(sym, sizeof(sym), "%s", kAbiSymbol[s->op]);
            b->abi_fn = (AbiFn)(void *)GetProcAddress(lib, sym);
            if (!b->abi_fn) {
                snprintf(reason, rn, "missing symbol %s", sym);
                return 0;
            }
        } else {
            if (!legacy_resolve(s, sym, sizeof(sym), &b->lk, &inplace)) {
                snprintf(reason, rn, "no 0.2.4 counterpart");
                return 0;
            }
            b->legacy_fn = GetProcAddress(lib, sym);
            if (!b->legacy_fn) {
                snprintf(reason, rn, "missing symbol %s", sym);
                return 0;
            }
        }
    }

    if (!img_alloc(&b->pristine, s->src, b->w, b->h) || !img_alloc(&b->work, s->src, b->w, b->h)) {
        snprintf(reason, rn, "source allocation failed");
        return 0;
    }
    if (!prepare_input(&b->pristine, input_dir, reason, rn)) return 0;
    img_copy(&b->work, &b->pristine);

    b->has_dst = !(b->ver == VER_V024 && inplace);
    if (b->has_dst) {
        int dfmt;
        uint32_t dw, dh;
        dst_geometry(b, &dfmt, &dw, &dh);
        if (!img_alloc(&b->dst, dfmt, dw, dh)) {
            snprintf(reason, rn, "destination allocation failed");
            return 0;
        }
        img_fill(&b->dst, BENCH_PREFILL);
    }

    if (b->ver == VER_ABI_V1) {
        const_frame(&b->src_frame, &b->work);
        mutable_frame(&b->dst_frame, &b->dst);
        abi_options(b);
    } else if (b->ver == VER_V024) {
        fill_def(&b->src_def, &b->work);
        if (b->has_dst) fill_def(&b->dst_def, &b->dst);
    }
    return 1;
}

static YuvStatus bench_call(Bench *b) {
    const Scenario *s = b->sc;
    switch (b->ver) {
        case VER_ABI_V1: return b->abi_fn(&b->src_frame, &b->dst_frame, &b->opt);
        case VER_MEMCPY:
            for (int i = 0; i < b->work.np; ++i) memcpy(b->dst.p[i], b->work.p[i], b->work.len[i]);
            return YUV_STATUS_OK;
        case VER_V024: break;
    }
    switch (b->lk) {
        case LK_DEF1: ((LegacyDef1Fn)(void *)b->legacy_fn)(&b->src_def); break;
        case LK_DEF2: ((LegacyDef2Fn)(void *)b->legacy_fn)(&b->src_def, &b->dst_def); break;
        case LK_DEF_OUT: ((LegacyDefOutFn)(void *)b->legacy_fn)(&b->src_def, b->dst.p[0]); break;
        case LK_RGBA: ((LegacyRgbaFn)(void *)b->legacy_fn)(b->work.p[0], &b->dst_def); break;
        case LK_ROT: ((LegacyRotFn)(void *)b->legacy_fn)(&b->src_def, &b->dst_def, s->arg); break;
        case LK_CROP:
            ((LegacyCropFn)(void *)b->legacy_fn)(&b->src_def, &b->dst_def, (int)b->crop[0], (int)b->crop[1],
                (int)b->crop[2], (int)b->crop[3]);
            break;
        case LK_BLUR_RECT: ((LegacyBlurRectFn)(void *)b->legacy_fn)(&b->src_def, s->arg, b->rect_ptr); break;
        case LK_GAUSS_INT: ((LegacyGaussIntFn)(void *)b->legacy_fn)(&b->src_def, s->arg, s->sigma); break;
        case LK_GAUSS_FLOAT: ((LegacyGaussFloatFn)(void *)b->legacy_fn)(&b->src_def, s->arg, (float)s->sigma); break;
        case LK_SWAP:
            ((LegacySwapFn)(void *)b->legacy_fn)(b->work.p[1], b->dst.p[1], (int)b->w, (int)b->h, (int)b->work.rs[1]);
            break;
        case LK_NONE: return YUV_STATUS_INTERNAL_ERROR;
    }
    return YUV_STATUS_OK;
}

static LARGE_INTEGER g_qpf;

/*
 * One iteration of the per-iteration protocol. Steps 1-2 (restore, pre-fill) are outside
 * the timed region. The pre-fill touches only a separate destination: for a 0.2.4
 * in-place row the destination IS the restored source, and filling it would destroy
 * the input before the call.
 */
static double bench_iteration(Bench *b, YuvStatus *status) {
    LARGE_INTEGER t0, t1;
    img_copy(&b->work, &b->pristine);
    if (b->has_dst) img_fill(&b->dst, BENCH_PREFILL);
    QueryPerformanceCounter(&t0);
    *status = bench_call(b);
    QueryPerformanceCounter(&t1);
    return (double)(t1.QuadPart - t0.QuadPart) * 1000.0 / (double)g_qpf.QuadPart;
}

static const Img *bench_output(const Bench *b) { return b->has_dst ? &b->dst : &b->work; }

static void bench_free(Bench *b) {
    img_free(&b->pristine);
    img_free(&b->work);
    img_free(&b->dst);
}

/* ===========================================================================
 * Statistics and the CSV record (doc: "Metrics per row", "Result record")
 * =========================================================================== */

static const char *const kCsvHeader =
    "platform,machine,round,version,sha,src_tree_id,scenario_id,op,src_fmt,dst_fmt,width,height,params,layout,level,"
    "status,reason,warmup,n,min_ms,median_ms,p95_or_max_ms,upper_kind,mean_ms,stdev_ms,spread,checksum_sha256,raw_ms,"
    "started_at,finished_at,compiler,flags,power_plan,affinity";

typedef struct {
    const char *platform;
    const char *machine;
    int round;
    const char *version;
    const char *sha;
    const char *tree;
    const char *compiler;
    const char *flags;
    const char *power_plan;
    const char *affinity;
} Meta;

typedef struct {
    char status[48];
    char reason[512];
    int warmup;
    int n;
    double *raw;
    char checksum[65];
    char started[32];
    char finished[32];
} Result;

static int cmp_double(const void *a, const void *b) {
    const double x = *(const double *)a, y = *(const double *)b;
    return x < y ? -1 : x > y ? 1 : 0;
}

static void format_row(Str *out, const Meta *m, const Scenario *s, uint32_t w, uint32_t h, const Result *r) {
    char params[128];
    int dfmt = s->op == OP_CVT ? s->dst : s->src;
    scenario_params(s, w, h, params, sizeof(params));

    csv_field(out, m->platform);
    csv_field(out, m->machine);
    csv_fieldf(out, "%d", m->round);
    csv_field(out, m->version);
    csv_field(out, m->sha);
    csv_field(out, m->tree);
    csv_field(out, s->id);
    csv_field(out, kOpName[s->op]);
    csv_field(out, fmt_name(s->src));
    csv_field(out, fmt_name(dfmt));
    csv_fieldf(out, "%u", w);
    csv_fieldf(out, "%u", h);
    csv_field(out, params);
    csv_field(out, "tight");
    csv_field(out, "c");
    csv_field(out, r->status);
    csv_field(out, r->reason);

    if (r->n > 0 && r->raw) {
        const int n = r->n;
        double *sorted = (double *)malloc(sizeof(double) * (size_t)n);
        if (!sorted) exit(1);
        memcpy(sorted, r->raw, sizeof(double) * (size_t)n);
        qsort(sorted, (size_t)n, sizeof(double), cmp_double);
        const double median = (n % 2) ? sorted[n / 2] : 0.5 * (sorted[n / 2 - 1] + sorted[n / 2]);
        const int use_p95 = n >= 20;
        /* Nearest rank: the ceil(0.95 * N)-th sorted sample, 1-based. */
        const double upper = use_p95 ? sorted[(int)ceil(0.95 * n) - 1] : sorted[n - 1];
        double sum = 0.0;
        for (int i = 0; i < n; ++i) sum += sorted[i];
        const double mean = sum / n;
        double var = 0.0;
        for (int i = 0; i < n; ++i) var += (sorted[i] - mean) * (sorted[i] - mean);
        const double stdev = n > 1 ? sqrt(var / (n - 1)) : 0.0;

        csv_fieldf(out, "%d", r->warmup);
        csv_fieldf(out, "%d", n);
        csv_fieldf(out, "%.4f", sorted[0]);
        csv_fieldf(out, "%.4f", median);
        csv_fieldf(out, "%.4f", upper);
        csv_field(out, use_p95 ? "p95" : "max");
        csv_fieldf(out, "%.4f", mean);
        csv_fieldf(out, "%.4f", stdev);
        csv_fieldf(out, "%.4f", median > 0.0 ? (upper - median) / median : 0.0);
        free(sorted);
    } else {
        csv_fieldf(out, "%d", r->warmup);
        csv_fieldf(out, "%d", r->n);
        for (int i = 0; i < 7; ++i) csv_field(out, "");
    }
    csv_field(out, r->checksum);

    if (r->n > 0 && r->raw) {
        Str raw = { 0 };
        for (int i = 0; i < r->n; ++i) str_addf(&raw, i ? ";%.4f" : "%.4f", r->raw[i]);
        csv_field(out, raw.s);
        free(raw.s);
    } else {
        csv_field(out, "");
    }
    csv_field(out, r->started);
    csv_field(out, r->finished);
    csv_field(out, m->compiler);
    csv_field(out, m->flags);
    csv_field(out, m->power_plan);
    csv_field(out, m->affinity);
}

/* stdout always gets the row; --out additionally gets it appended, with the header if the file is new. */
static void emit_row(const char *out_path, const Meta *m, const Scenario *s, uint32_t w, uint32_t h, const Result *r) {
    Str row = { 0 };
    format_row(&row, m, s, w, h, r);
    printf("%s\n", row.s);
    fflush(stdout);
    if (out_path && out_path[0]) {
        wchar_t *wout = widen(out_path);
        FILE *f = _wfopen(wout, L"ab");
        free(wout);
        if (f) {
            fseek(f, 0, SEEK_END);
            if (ftell(f) == 0) fprintf(f, "%s\r\n", kCsvHeader);
            fprintf(f, "%s\r\n", row.s);
            fclose(f);
        } else {
            fprintf(stderr, "yuv_bench: cannot append to %s\n", out_path);
        }
    }
    free(row.s);
}

/* A row with placeholders that the driver fills in when it has to kill or bury this
 * process: the harness cannot write its own TIMEOUT row once the watchdog fired. */
static void emit_driver_template(const Meta *m, const Scenario *s, uint32_t w, uint32_t h, const Result *r) {
    Result t = *r;
    snprintf(t.status, sizeof(t.status), "@STATUS@");
    snprintf(t.reason, sizeof(t.reason), "@REASON@");
    snprintf(t.finished, sizeof(t.finished), "@FINISHED@");
    t.n = 0;
    t.raw = NULL;
    t.checksum[0] = 0;
    Str row = { 0 };
    format_row(&row, m, s, w, h, &t);
    fprintf(stderr, "row-template: %s\n", row.s);
    fflush(stderr);
    free(row.s);
}

/* Adaptive rule (doc: "Warm-up and repetitions"). Returns 0 when t1 exceeds the watchdog. */
static int plan_for(double t1, int *warmup, int *n) {
    if (t1 < 5.0) *warmup = 10, *n = 50;
    else if (t1 < 100.0) *warmup = 5, *n = 30;
    else if (t1 < 2000.0) *warmup = 2, *n = 15;
    else if (t1 < 30000.0) *warmup = 1, *n = 5;
    else if (t1 <= BENCH_TIMEOUT_MS) *warmup = 0, *n = 3;
    else return 0;
    return 1;
}

/* ===========================================================================
 * CLI
 * =========================================================================== */

static void usage(void) {
    fprintf(stderr,
        "usage: yuv_bench --version v024|abi_v1|ref.memcpy --dll <yuv_ffi.dll> --inputs <dir> --out <csv>\n"
        "                 --scenario <ID> [--size WxH] [--round N] [--sha S] [--tree T] [--machine M]\n"
        "                 [--power-plan P] [--compiler C] [--flags F] [--platform P] [--affinity 0xMASK]\n"
        "                 [--priority high|normal]\n"
        "       yuv_bench --list        (prints '<ID><TAB><1080p-only flag>' per matrix row)\n");
}

int wmain(int argc, wchar_t **wargv) {
    char **argv = (char **)calloc((size_t)argc + 1, sizeof(char *));
    if (!argv) return 1;
    for (int i = 0; i < argc; ++i) argv[i] = narrow(wargv[i]);

    build_matrix();

    const char *version = NULL, *dll = NULL, *inputs = NULL, *out = NULL, *scenario_id = NULL;
    const char *size = "1920x1080", *affinity = "", *priority = "normal";
    char compiler_default[64];
    snprintf(compiler_default, sizeof(compiler_default), "msvc-cl-%d.%02d.%05d", _MSC_FULL_VER / 10000000,
        (_MSC_FULL_VER / 100000) % 100, _MSC_FULL_VER % 100000);
    const char *machine_env = getenv("COMPUTERNAME");
    Meta meta = { "windows-x64", machine_env ? machine_env : "", 1, "", "", "", compiler_default,
        "/MD /O2 /Ob2 /DNDEBUG", "", "" };

    for (int i = 1; i < argc; ++i) {
        const char *a = argv[i];
        const char *v = i + 1 < argc ? argv[i + 1] : NULL;
        if (strcmp(a, "--list") == 0) {
            for (int k = 0; k < g_matrix_count; ++k) printf("%s\t%d\n", g_matrix[k].id, g_matrix[k].only1080);
            return 0;
        }
        if (!v) {
            usage();
            return 1;
        }
        if (strcmp(a, "--version") == 0) version = v;
        else if (strcmp(a, "--dll") == 0) dll = v;
        else if (strcmp(a, "--inputs") == 0) inputs = v;
        else if (strcmp(a, "--out") == 0) out = v;
        else if (strcmp(a, "--scenario") == 0) scenario_id = v;
        else if (strcmp(a, "--size") == 0) size = v;
        else if (strcmp(a, "--round") == 0) meta.round = atoi(v);
        else if (strcmp(a, "--sha") == 0) meta.sha = v;
        else if (strcmp(a, "--tree") == 0) meta.tree = v;
        else if (strcmp(a, "--machine") == 0) meta.machine = v;
        else if (strcmp(a, "--power-plan") == 0) meta.power_plan = v;
        else if (strcmp(a, "--compiler") == 0) meta.compiler = v;
        else if (strcmp(a, "--flags") == 0) meta.flags = v;
        else if (strcmp(a, "--platform") == 0) meta.platform = v;
        else if (strcmp(a, "--affinity") == 0) affinity = v;
        else if (strcmp(a, "--priority") == 0) priority = v;
        else {
            fprintf(stderr, "yuv_bench: unknown argument %s\n", a);
            usage();
            return 1;
        }
        ++i;
    }

    Version ver;
    if (!version || !inputs || !scenario_id) {
        usage();
        return 1;
    }
    if (strcmp(version, "abi_v1") == 0) ver = VER_ABI_V1;
    else if (strcmp(version, "v024") == 0) ver = VER_V024;
    else if (strcmp(version, "ref.memcpy") == 0) ver = VER_MEMCPY;
    else {
        fprintf(stderr, "yuv_bench: unknown --version %s\n", version);
        return 1;
    }
    if (ver != VER_MEMCPY && !dll) {
        fprintf(stderr, "yuv_bench: --dll is required for %s\n", version);
        return 1;
    }
    meta.version = version;

    const Scenario *sc = find_scenario(scenario_id);
    if (!sc) {
        fprintf(stderr, "yuv_bench: unknown scenario %s (see --list)\n", scenario_id);
        return 1;
    }
    unsigned w = 0, h = 0;
    if (sscanf(size, "%ux%u", &w, &h) != 2 || w < 2 || h < 2) {
        fprintf(stderr, "yuv_bench: bad --size %s\n", size);
        return 1;
    }

    /* Pinning and priority are applied by the process itself, before any input is built,
     * so no measured call can run on an unpinned or normal-priority thread. */
    if (affinity[0]) {
        unsigned long long mask = _strtoui64(affinity, NULL, 0);
        if (!mask || !SetProcessAffinityMask(GetCurrentProcess(), (DWORD_PTR)mask)) {
            fprintf(stderr, "yuv_bench: cannot set affinity %s (error %lu)\n", affinity, GetLastError());
            return 1;
        }
    }
    if (strcmp(priority, "high") == 0 && !SetPriorityClass(GetCurrentProcess(), HIGH_PRIORITY_CLASS)) {
        fprintf(stderr, "yuv_bench: cannot set high priority (error %lu)\n", GetLastError());
        return 1;
    }
    meta.affinity = affinity;
    QueryPerformanceFrequency(&g_qpf);

    Result res;
    memset(&res, 0, sizeof(res));
    utc_now(res.started, sizeof(res.started));

    const char *na = na_reason(sc, ver, w, h);
    if (na) {
        snprintf(res.status, sizeof(res.status), "N/A");
        snprintf(res.reason, sizeof(res.reason), "%s", na);
        utc_now(res.finished, sizeof(res.finished));
        emit_row(out, &meta, sc, w, h, &res);
        return 0;
    }

    Bench b;
    memset(&b, 0, sizeof(b));
    b.sc = sc;
    b.ver = ver;
    b.w = w;
    b.h = h;

    int exit_code = 0;
    if (!bench_prepare(&b, dll, inputs, res.reason, sizeof(res.reason))) {
        snprintf(res.status, sizeof(res.status), "ERROR:setup");
        exit_code = 2;
        goto done;
    }

    emit_driver_template(&meta, sc, w, h, &res);
    fprintf(stderr, "ready\n");
    fflush(stderr);

    YuvStatus st = YUV_STATUS_OK;
    const double t1 = bench_iteration(&b, &st);
    if (st != YUV_STATUS_OK) {
        snprintf(res.status, sizeof(res.status), "ERROR:%d", (int)st);
        snprintf(res.reason, sizeof(res.reason), "calibration call returned status %d", (int)st);
        exit_code = 2;
        goto done;
    }
    if (!plan_for(t1, &res.warmup, &res.n)) {
        snprintf(res.status, sizeof(res.status), "TIMEOUT");
        snprintf(res.reason, sizeof(res.reason), ">120 s; t1=%.4f ms is a lower bound", t1);
        res.warmup = 1;
        res.n = 0;
        goto done;
    }
    fprintf(stderr, "calibrated t1_ms=%.4f warmup=%d n=%d\n", t1, res.warmup, res.n);
    fflush(stderr);

    for (int i = 0; i < res.warmup; ++i) {
        bench_iteration(&b, &st);
        if (st != YUV_STATUS_OK) {
            snprintf(res.status, sizeof(res.status), "ERROR:%d", (int)st);
            snprintf(res.reason, sizeof(res.reason), "warm-up call returned status %d", (int)st);
            exit_code = 2;
            goto done;
        }
    }
    /* The calibration run counts as warm-up; the recorded figure is the total. */
    res.warmup += 1;

    res.raw = (double *)calloc((size_t)res.n, sizeof(double));
    if (!res.raw) exit(1);
    char first_sum[65] = { 0 };
    for (int i = 0; i < res.n; ++i) {
        res.raw[i] = bench_iteration(&b, &st);
        if (st != YUV_STATUS_OK) {
            snprintf(res.status, sizeof(res.status), "ERROR:%d", (int)st);
            snprintf(res.reason, sizeof(res.reason), "measured call %d returned status %d", i + 1, (int)st);
            res.n = 0;
            exit_code = 2;
            goto done;
        }
        if (i == 0 && !sha256_img(bench_output(&b), first_sum)) {
            snprintf(res.status, sizeof(res.status), "ERROR:checksum");
            snprintf(res.reason, sizeof(res.reason), "SHA-256 of the output failed");
            res.n = 0;
            exit_code = 2;
            goto done;
        }
    }
    if (!sha256_img(bench_output(&b), res.checksum)) {
        snprintf(res.status, sizeof(res.status), "ERROR:checksum");
        snprintf(res.reason, sizeof(res.reason), "SHA-256 of the output failed");
        res.n = 0;
        exit_code = 2;
        goto done;
    }
    if (strcmp(first_sum, res.checksum) != 0) {
        snprintf(res.status, sizeof(res.status), "ERROR:nondeterministic");
        snprintf(res.reason, sizeof(res.reason), "first measured %s != last measured %s", first_sum, res.checksum);
        exit_code = 2;
        goto done;
    }
    snprintf(res.status, sizeof(res.status), "OK");

done:
    utc_now(res.finished, sizeof(res.finished));
    emit_row(out, &meta, sc, w, h, &res);
    free(res.raw);
    bench_free(&b);
    return exit_code;
}
