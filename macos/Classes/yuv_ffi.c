// Relative import to be able to reuse the C sources.
// See the comment in ../yuv_ffi.podspec for more information.
//
// The per-format forwarders (bgra8888.c, nv21.c, yuv420.c) sit next to this
// file and pull in the operation implementations. This one carries the shared
// support code they all depend on, mirroring ios/Classes/yuv_ffi.c. Each
// translation unit is included exactly once across the four forwarders, so the
// pod target never compiles the same source twice.

#include "../../src/yuv_ffi.c"
#include "../../src/yuv/utils/gauss.c"
#include "../../src/yuv/yuv.c"
