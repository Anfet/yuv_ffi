// Relative import to be able to reuse the C sources.
// See the comment in ../yuv_ffi.podspec for more information.
//
// The per-format forwarders (bgra8888.c, nv21.c, yuv420.c) sit next to this
// file and pull in the operation implementations. This one carries the shared
// support code and most of the versioned ABI kernels, mirroring
// ios/Classes/yuv_ffi.c. Each translation unit is included exactly once across
// the four forwarders, so the pod target never compiles the same source twice.
//
// yuv_rotate_v1.c is deliberately NOT here — it is forwarded from yuv420.c.
// It and yuv_flip_v1.c each define their own file-local
// `yuv_axis_reversal_is_block_aligned`, which is legal because CMake compiles
// them as separate translation units, but including both in one forwarder
// concatenates them into a single TU and clang rejects the redefinition. The
// two must therefore stay in different forwarders.
//
// test/apple_forwarder_sources_test.dart compares this set against
// src/CMakeLists.txt: a source built on Linux/Windows/Android but absent here
// is a symbol that only goes missing once an Apple consumer calls it.

#include "../../src/yuv_ffi.c"
#include "../../src/yuv/utils/gauss.c"
#include "../../src/yuv/utils/checked_arithmetic.c"
#include "../../src/yuv/utils/validated_view.c"
#include "../../src/yuv/yuv.c"
#include "../../src/yuv/abi/yuv_validate_v1.c"
#include "../../src/yuv/abi/yuv_kernel_v1.c"
#include "../../src/yuv/abi/yuv_convert_v1.c"
#include "../../src/yuv/abi/yuv_black_white_v1.c"
#include "../../src/yuv/abi/yuv_grayscale_v1.c"
#include "../../src/yuv/abi/yuv_negate_v1.c"
#include "../../src/yuv/abi/yuv_gaussian_blur_v1.c"
#include "../../src/yuv/abi/yuv_mean_blur_v1.c"
#include "../../src/yuv/abi/yuv_box_blur_v1.c"
#include "../../src/yuv/abi/yuv_crop_v1.c"
#include "../../src/yuv/abi/yuv_flip_v1.c"
#include "../../src/yuv/abi/yuv_chroma_swap_v1.c"
