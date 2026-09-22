// Relative import to be able to reuse the C sources.
// See the comment in ../yuv_ffi.podspec for more information.
#include "../../src/yuv/yuv420/yuv420_blackwhite.c"
#include "../../src/yuv/yuv420/yuv420_crop.c"
#include "../../src/yuv/yuv420/yuv420_flip.c"
#include "../../src/yuv/yuv420/yuv420_gaussblur.c"
#include "../../src/yuv/yuv420/yuv420_grayscale.c"
#include "../../src/yuv/yuv420/yuv420_mean_blur.c"
#include "../../src/yuv/yuv420/yuv420_rotate.c"
#include "../../src/yuv/yuv420/yuv420_to_bgra.c"
#include "../../src/yuv/yuv420/yuv420_negate.c"
#include "../../src/yuv/yuv420/yuv420_box_blur.c"
#include "../../src/yuv/yuv420/yuv420_from_rgba.c"
#include "../../src/yuv/yuv420/yuv420_to_nv21.c"

// Forwarded here rather than from yuv_ffi.c: yuv_rotate_v1.c and
// yuv_flip_v1.c each define a file-local
// `yuv_axis_reversal_is_block_aligned`, which only collides when both land in
// the same translation unit. See the note in yuv_ffi.c.
#include "../../src/yuv/abi/yuv_rotate_v1.c"