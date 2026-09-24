// Relative import to be able to reuse the C sources.
// See the comment in ../yuv_ffi.podspec for more information.
//
// yuv_rotate_v1.c gets a forwarder of its own because it and yuv_flip_v1.c
// each define a file-local `yuv_axis_reversal_is_block_aligned`, which only
// collides when both land in the same translation unit. See the note in
// yuv_ffi.c.
#include "../../src/yuv/abi/yuv_rotate_v1.c"
