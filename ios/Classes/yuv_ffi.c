// Relative import to be able to reuse the C sources.
// See the comment in ../{projectName}}.podspec for more information.
//#include "../../src/yuv/yuv.h"
//#include "../../src/yuv/yuv420.h"
//#include "../../src/yuv/nv21.h"
//#include "../../src/yuv/bgra8888.h"
#include "../../src/yuv_ffi.h"
#include "../../src/yuv_ffi.c"
#include "../../src/yuv/gauss.c"
#include "../../src/yuv/yuv.c"
#include "nv21.c"
#include "bgra8888.c"
#include "yuv420.c"
